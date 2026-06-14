import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_channel.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.jellyfin');

/// A [BasePlayer] that drives the **Jellyfin Cast receiver** (app id `F007D354`)
/// over its custom protocol, the way the official Jellyfin web/Android apps do.
///
/// Unlike the default media receiver, this receiver fetches and plays the item
/// itself (doing its own PlaybackInfo/transcoding on the server), so we only
/// hand it credentials + the item — no media URL or client-side transcode.
class JellyfinCastPlayer extends BasePlayer implements RemotePlayer {
  JellyfinCastPlayer._(this.deviceName, this._context) {
    _itemStub = _context.itemStub;
    _mediaSourceId = _context.mediaSourceId;
    _audioStreamIndex = _context.audioStreamIndex;
    _subtitleStreamIndex = _context.subtitleStreamIndex;
    _image = _context.image;
    _maxBitrate = _context.maxBitrate;
  }

  @override
  final String deviceName;

  // The receiver registers its own session and reports start/progress/stop to
  // the server itself; the phone must stay quiet to avoid a duplicate session.
  @override
  bool get reportsOwnProgress => true;

  final JellyfinCastContext _context;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  final List<StreamSubscription> _subs = [];

  // The receiver's web app registers its message listener a beat after the
  // session connects, so early messages are silently dropped. Retry PlayNow
  // until the receiver acknowledges, then stop. CRUCIAL: once the receiver is
  // known to be alive, retries are harmful — a live receiver processes every
  // duplicate PlayNow and restarts playback (a fresh server transcode each
  // time), so it never gets past LOADING.
  bool _acknowledged = false;

  // Set on any sign of life (custom message or active media status) and never
  // reset: a live receiver has its listener registered, so one send suffices.
  bool _receiverAlive = false;
  Map<String, dynamic>? _playNowOptions;
  Timer? _playNowTimer;

  // The item/tracks currently being played. Seeded from the connect-time
  // context, updated when a new item is loaded while casting (the context is
  // frozen at connect, but the user can switch media mid-cast).
  late Map<String, dynamic> _itemStub;
  String? _mediaSourceId;
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;
  ImageProvider? _image;
  int? _maxBitrate;

  /// Caps the receiver's stream quality (bits/second; null lets the receiver
  /// auto-detect) and restarts playback so it takes effect. The server still
  /// negotiates against the receiver's device profile, so a high cap simply
  /// allows direct play when the file is compatible — never an unplayable
  /// stream.
  Future<void> setMaxBitrate(int? bitrate) async {
    _maxBitrate = bitrate;
    await _restartAtCurrentPosition('quality ${bitrate == null ? 'auto' : '${(bitrate / 1000000).round()}Mbps'}');
  }

  /// Points the player at a new item (called when the user starts different
  /// media while the cast session is active).
  void updateItem({
    required Map<String, dynamic> itemStub,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    ImageProvider? image,
  }) {
    _itemStub = itemStub;
    _mediaSourceId = mediaSourceId;
    _audioStreamIndex = audioStreamIndex;
    _subtitleStreamIndex = subtitleStreamIndex;
    _image = image;
  }

  CastMediaPlayerState? _lastMediaState;

  // The item the receiver reports it is playing (empty reports are ignored).
  String? _nowPlayingItemId;
  Completer<String>? _nowPlayingWaiter;

  /// Waits for the receiver to report an item in progress (it announces its
  /// state in response to the Identify sent at init). Returns null when the
  /// receiver is idle — i.e. there is nothing to adopt.
  Future<String?> waitForNowPlayingItem(Duration timeout) async {
    if (_nowPlayingItemId != null) return _nowPlayingItemId;
    final waiter = _nowPlayingWaiter = Completer<String>();
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      _nowPlayingWaiter = null;
    }
  }

  /// Whether the receiver currently has a stream (a rejoined session can carry
  /// a zombie stream from a previous cast).
  bool get _mediaActive =>
      _lastMediaState == CastMediaPlayerState.loading ||
      _lastMediaState == CastMediaPlayerState.buffering ||
      _lastMediaState == CastMediaPlayerState.playing ||
      _lastMediaState == CastMediaPlayerState.paused;

  // The receiver only reports position every few seconds; tick locally in
  // between so the scrubber advances smoothly, correcting from each report.
  Timer? _positionTicker;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  /// Connects to [device] (launching app id F007D354, set at SDK init) and
  /// registers the Jellyfin message namespace.
  static Future<JellyfinCastPlayer> connect(
    GoogleCastDevice device,
    JellyfinCastContext context, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.friendlyName}"');
    final sessions = GoogleCastSessionManager.instance;

    final connected = Completer<void>();
    late final StreamSubscription sub;
    sub = sessions.currentSessionStream.listen((session) {
      if (session?.connectionState == GoogleCastConnectState.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    try {
      await sessions.startSessionWithDevice(device);
      if (sessions.connectionState != GoogleCastConnectState.connected) {
        await connected.future.timeout(timeout);
      }
    } finally {
      await sub.cancel();
    }

    await JellyfinCastChannel.instance.registerNamespace(jellyfinCastNamespace);
    _log.info('Jellyfin cast session connected to "${device.friendlyName}"');
    final player = JellyfinCastPlayer._(device.friendlyName, context);

    // A rejoined receiver announces itself (volumechange/progress) right after
    // connect, but the first loadVideo runs before that lands — catch it here
    // so loadVideo takes the safe stop-before-PlayNow path instead of treating
    // a live receiver as a cold boot (which races its internal stop event and
    // wedges the display).
    try {
      await JellyfinCastChannel.instance.messages.first.timeout(const Duration(milliseconds: 1500));
      player._receiverAlive = true;
      _log.info('Receiver is already live (rejoined session)');
    } on TimeoutException {
      // Fresh receiver boot — the PlayNow retry schedule handles its startup.
    }
    return player;
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _subs.add(JellyfinCastChannel.instance.messages.listen(_onMessage));
    // The Cast media status reacts to PlayNow (LOADING) well before the
    // receiver's first custom message — use it as the earliest acknowledgment
    // so the retry loop stops before it can restart playback.
    _subs.add(GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((status) {
      final state = status?.playerState;
      _lastMediaState = state;
      if (state == CastMediaPlayerState.loading ||
          state == CastMediaPlayerState.buffering ||
          state == CastMediaPlayerState.playing) {
        _markReceiverAlive('media status ${state!.name}');
      }
      if (state == CastMediaPlayerState.idle && _stopCompleter?.isCompleted == false) {
        _stopCompleter?.complete();
      }
    }));
    // Handshake — the receiver replies with its capabilities/state.
    await _send('Identify', {});
  }

  void _markReceiverAlive(String via) {
    _receiverAlive = true;
    if (!_acknowledged) {
      _acknowledged = true;
      _playNowTimer?.cancel();
      _log.info('Receiver acknowledged ($via) — playback handed off');
    }
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // Connected without active playback (remote-control mode) — nothing to
    // play until the user starts an item, which updates the stub first.
    if (_itemStub['Id'] == null) {
      _log.info('Cast session idle — waiting for an item to play');
      return;
    }
    // The receiver fetches the item itself; `url` is ignored.
    _acknowledged = false;
    _playNowOptions = _buildPlayNowOptions(startPosition);
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    if (_receiverAlive) {
      // A live receiver may still hold a previous stream (rejoined session,
      // or one being torn down) — and its media status isn't always reported
      // yet, so don't trust _mediaActive here. Always stop and wait for idle:
      // PlayNow on top of an active stream races the late stop event, leaving
      // the idle splash stuck over the new video. On an already-idle receiver
      // the stop is a cheap no-op that confirms quickly.
      _log.info('Stopping any active stream on "$deviceName" before PlayNow'
          '${_mediaActive ? ' (media active)' : ''}');
      await _send('Stop', {});
      await _waitForReceiverStop(const Duration(seconds: 3));
      // The listener is registered — one send is reliable, and a duplicate
      // would restart playback.
      _log.info('PlayNow → "$deviceName" (receiver alive, single send)');
      await _send('PlayNow', _playNowOptions!);
    } else {
      _startPlayNowAttempts();
    }
  }

  /// Sends PlayNow, retrying until the receiver acknowledges (so the request
  /// isn't lost while the receiver's web app is still loading its listener).
  ///
  /// Retries are spaced WIDE apart on purpose: a landed PlayNow's first
  /// acknowledgment (the LOADING media status) only arrives after the
  /// receiver's PlaybackInfo round-trip (5-9s for a movie). Retrying inside
  /// that window lands duplicate PlayNows on a live receiver, racing loads
  /// and wedging its display.
  void _startPlayNowAttempts() {
    _playNowTimer?.cancel();
    const retryDelays = [Duration(seconds: 5), Duration(seconds: 12), Duration(seconds: 18)];
    var attempts = 0;

    Future<void> attempt() async {
      final options = _playNowOptions;
      if (_acknowledged || options == null) return;
      attempts++;
      _log.info('PlayNow → "$deviceName" (attempt $attempts, item ${_itemStub['Id']})');
      await _send('PlayNow', options);
    }

    void scheduleNext(int index) {
      if (index >= retryDelays.length) return;
      _playNowTimer = Timer(retryDelays[index], () {
        if (_acknowledged) return;
        if (index == retryDelays.length - 1) {
          _log.warning('Receiver still silent — final PlayNow attempt');
        }
        attempt();
        scheduleNext(index + 1);
      });
    }

    attempt();
    scheduleNext(0);
  }

  @override
  Future<void> play() async {
    // Optimistically reflect the action; the receiver confirms via playstatechange.
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _syncPositionTicker(true);
    await _send('Unpause', {});
  }

  @override
  Future<void> pause() async {
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _syncPositionTicker(false);
    await _send('Pause', {});
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _playNowOptions = null;
    await _send('Stop', {});
  }

  @override
  Future<void> seek(Duration position) async {
    await _send('Seek', {'position': position.inSeconds});
    lastState = lastState.update(position: position);
    _stateController.add(lastState);
  }

  Map<String, dynamic> _buildPlayNowOptions(Duration startPosition) => buildPlayNowOptions(
        itemStub: _itemStub,
        startPosition: startPosition,
        mediaSourceId: _mediaSourceId,
        audioStreamIndex: _audioStreamIndex,
        subtitleStreamIndex: _subtitleStreamIndex,
      );

  // Track switching restarts playback via PlayNow at the current position
  // rather than SetAudio/SetSubtitleStreamIndex: the receiver's internal
  // changeStream path has a display race (the old stream's stop event flips
  // the UI back to the idle splash on top of the playing video). The PlayNow
  // path is the same flow as starting a cast, which renders correctly.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    // null = "apply defaults" (called during load); PlayNow already carries
    // the selected tracks, so only an explicit user choice restarts.
    if (model == null) return _audioStreamIndex ?? -1;
    _audioStreamIndex = model.index;
    await _restartAtCurrentPosition('audio track ${model.index}');
    return model.index;
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _subtitleStreamIndex ?? -1;
    _subtitleStreamIndex = model.index;
    await _restartAtCurrentPosition('subtitle track ${model.index}');
    return model.index;
  }

  Future<void> _restartAtCurrentPosition(String reason) async {
    final resumeAt = lastState.position;
    final options = _buildPlayNowOptions(resumeAt);
    _playNowOptions = options;
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _log.info('Restarting on "$deviceName" ($reason, resume at ${resumeAt.inSeconds}s)');
    // Stop first and wait for the receiver to reach idle: a PlayNow on top of
    // an active stream races the old stream's late stop event, which flips
    // the receiver UI to the idle splash on top of the new video.
    await _send('Stop', {});
    await _waitForReceiverStop(const Duration(seconds: 5));
    await _send('PlayNow', options);
  }

  Completer<void>? _stopCompleter;

  /// Completes when the receiver confirms the current stream stopped (its
  /// `playbackstop` message or an idle media status), or after [timeout].
  Future<void> _waitForReceiverStop(Duration timeout) async {
    final completer = Completer<void>();
    _stopCompleter = completer;
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      _log.fine('Receiver did not confirm stop within ${timeout.inSeconds}s — continuing');
    } finally {
      _stopCompleter = null;
    }
    // Brief settle so the receiver's stop UI flip lands before our new load.
    await Future.delayed(const Duration(milliseconds: 400));
  }

  /// Sets the Cast device's volume. The receiver protocol's volume commands
  /// are stubs ("implemented on the sender"), so this goes through the Cast
  /// SDK's device volume. [volume] arrives on the app's 0-100 scale.
  @override
  Future<void> setVolume(double volume) async {
    final normalized = (volume > 1 ? volume / 100 : volume).clamp(0.0, 1.0);
    try {
      GoogleCastSessionManager.instance.setDeviceVolume(normalized);
    } catch (error) {
      _log.fine('Failed to set device volume: $error');
    }
  }

  // The receiver owns the playback rate (no protocol command exists).
  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => _CastingPlaceholder(key: key, deviceName: deviceName, image: _image);

  @override
  Future<void> dispose() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
    if (!_stateController.isClosed) await _stateController.close();
  }

  /// Builds the full message envelope (command + credentials) the receiver
  /// expects, and sends it as JSON on the Jellyfin namespace.
  Future<void> _send(String command, Map<String, dynamic> options) async {
    final message = buildJellyfinEnvelope(
      command: command,
      options: options,
      context: _context,
      receiverName: deviceName,
      maxBitrate: _maxBitrate,
    );
    try {
      await JellyfinCastChannel.instance.sendMessage(jellyfinCastNamespace, message);
    } catch (error) {
      _log.warning('Failed to send $command: $error');
    }
  }

  void _onMessage(String raw) {
    _markReceiverAlive('receiver message');
    // Messages are `{type, data:{PlayState:{...}, NowPlayingItem:{...}}}`,
    // where type ∈ {playbackstart, playstatechange, playbackprogress, ...}.
    final report = parseReceiverMessage(raw);
    if (report == null) return;

    if (report.type == 'playbackstop' && _stopCompleter?.isCompleted == false) {
      _stopCompleter?.complete();
    }
    if (report.itemId != null) {
      _nowPlayingItemId = report.itemId;
      if (_nowPlayingWaiter?.isCompleted == false) _nowPlayingWaiter!.complete(report.itemId!);
    }
    if (report.audioStreamIndex != null) _audioStreamIndex = report.audioStreamIndex;
    if (report.subtitleStreamIndex != null) _subtitleStreamIndex = report.subtitleStreamIndex;

    lastState = lastState.update(
      playing: report.playing,
      buffering: false,
      position: report.position,
      duration: report.duration,
    );
    _stateController.add(lastState);
    // Resync the local ticker to the receiver's authoritative position/state.
    _syncPositionTicker(report.playing ?? lastState.playing);
    _log.fine('Receiver ${report.type}: pos=${report.position?.inSeconds}s playing=${report.playing}');
  }

  /// Runs a 1s local clock that advances [lastState] position while playing, so
  /// the scrubber moves smoothly between the receiver's periodic reports. Each
  /// report calls this to correct drift; pausing/stopping cancels it.
  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      lastState = lastState.update(position: lastState.position + const Duration(seconds: 1));
      _stateController.add(lastState);
    });
  }
}

/// Shown in place of the video while casting: the item's backdrop with a cast
/// badge. Scales down to the mini player-bar preview (icon only).
class _CastingPlaceholder extends StatelessWidget {
  const _CastingPlaceholder({super.key, required this.deviceName, this.image});

  final String deviceName;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 140;
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (image != null)
            Image(
              image: image!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Scrim so the badge stays readable on bright backdrops.
          ColoredBox(color: Colors.black.withValues(alpha: compact ? 0.35 : 0.55)),
          Center(
            child: compact
                ? const Icon(Icons.cast_connected, size: 22, color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cast_connected, size: 36, color: Colors.white70),
                      const SizedBox(height: 12),
                      Text(
                        'Casting to $deviceName',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
          ),
        ],
      );
    });
  }
}

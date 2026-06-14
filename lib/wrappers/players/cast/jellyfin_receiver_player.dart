import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/screens/video_player/components/casting_placeholder.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/cast_message_transport.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.jellyfin');

/// Drives the **Jellyfin Cast receiver** (app id `F007D354`) over its custom
/// protocol — the receiver fetches and plays the item itself, so we only hand
/// it credentials + the item. All receiver-control logic lives here; the
/// native ([JellyfinCastPlayer]) and web (`WebJellyfinCastPlayer`) senders
/// subclass this and provide only a [CastMessageTransport] (plus, on mobile, a
/// few platform-specific timing overrides).
abstract class JellyfinReceiverPlayer extends BasePlayer implements RemotePlayer {
  JellyfinReceiverPlayer(this.transport, this.context, this.deviceName, {required this.onSessionEnded}) {
    _itemStub = context.itemStub;
    _mediaSourceId = context.mediaSourceId;
    _audioStreamIndex = context.audioStreamIndex;
    _subtitleStreamIndex = context.subtitleStreamIndex;
    _image = context.image;
    _maxBitrate = context.maxBitrate;
  }

  @protected
  final CastMessageTransport transport;
  @protected
  final JellyfinCastContext context;

  /// Called when the receiver session ends out from under us — the device was
  /// turned off/taken over by another sender (detected by the staleness
  /// watchdog), or the transport reports an explicit end. Lets the app restore
  /// local playback. Fired at most once.
  final void Function() onSessionEnded;

  @override
  final String deviceName;

  // The receiver registers its own server session and reports start/progress/
  // stop itself; the phone must stay quiet to avoid a duplicate session.
  @override
  bool get reportsOwnProgress => true;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  @protected
  final List<StreamSubscription> subs = [];

  /// Set once the receiver shows any sign of life, so the PlayNow retry loop
  /// stops (a live receiver restarts playback on every duplicate PlayNow).
  @protected
  bool acknowledged = false;

  Map<String, dynamic>? _playNowOptions;
  Timer? _playNowTimer;
  Timer? _positionTicker;

  // The receiver sends `playbackprogress` every few seconds while playing. If it
  // goes quiet for this long *while we believe we're playing*, the session was
  // lost — another sender took over, or the device went away — so restore local.
  static const _staleTimeout = Duration(seconds: 20);
  Timer? _staleWatchdog;
  bool _sessionEnded = false;

  // Item/tracks currently playing — seeded from the connect-time context,
  // updated when media changes mid-cast.
  late Map<String, dynamic> _itemStub;
  String? _mediaSourceId;
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;
  ImageProvider? _image;
  int? _maxBitrate;

  String? _nowPlayingItemId;
  Completer<String>? _nowPlayingWaiter;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    subs.add(transport.messages.listen(_onMessage));
    await onInit();
    // Handshake — the receiver replies with its capabilities/state.
    await sendCommand('Identify', {});
  }

  /// Subclass-specific init (e.g. the native media-status subscription).
  @protected
  Future<void> onInit() async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // Connected without active playback (remote-control mode) — nothing to play
    // until the user starts an item (which updates the stub first).
    if (_itemStub['Id'] == null) {
      _log.info('Cast session idle — waiting for an item to play');
      return;
    }
    // The receiver fetches the item itself; `url` is ignored.
    acknowledged = false;
    // A fresh transcode can take >20s with no progress reports — suspend the
    // staleness watchdog until the new stream starts reporting again.
    _staleWatchdog?.cancel();
    _playNowOptions = _buildPlayNowOptions(startPosition);
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);
    await beginPlayback();
  }

  /// How to deliver the first PlayNow. Default retries until acknowledged; the
  /// native player overrides to stop a live (rejoined) receiver first.
  @protected
  Future<void> beginPlayback() async => startPlayNowAttempts();

  @protected
  Map<String, dynamic>? get playNowOptions => _playNowOptions;

  /// Sends PlayNow, retrying on a wide schedule until the receiver acknowledges
  /// (its web app registers its listener a beat after connect, so the first
  /// sends can be silently dropped). Retries are spaced wide because a landed
  /// PlayNow's first ack only arrives after the receiver's PlaybackInfo
  /// round-trip — retrying inside that window stacks duplicate loads.
  @protected
  void startPlayNowAttempts() {
    _playNowTimer?.cancel();
    const retryDelays = [Duration(seconds: 5), Duration(seconds: 12), Duration(seconds: 18)];
    var attempts = 0;

    Future<void> attempt() async {
      final options = _playNowOptions;
      if (acknowledged || options == null) return;
      attempts++;
      _log.info('PlayNow → "$deviceName" (attempt $attempts, item ${_itemStub['Id']})');
      await sendCommand('PlayNow', options);
    }

    void scheduleNext(int index) {
      if (index >= retryDelays.length) return;
      _playNowTimer = Timer(retryDelays[index], () {
        if (acknowledged) return;
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

  /// Marks the receiver acknowledged (stops the retry loop). Idempotent; the
  /// native player overrides to also flag the receiver as live.
  @protected
  void markAcknowledged(String via) {
    if (acknowledged) return;
    acknowledged = true;
    _playNowTimer?.cancel();
    _log.info('Receiver acknowledged ($via) — playback handed off');
  }

  @override
  Future<void> play() async {
    // Optimistic; the receiver confirms via playstatechange.
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _syncPositionTicker(true);
    await sendCommand('Unpause', {});
  }

  @override
  Future<void> pause() async {
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _syncPositionTicker(false);
    _staleWatchdog?.cancel(); // paused → the receiver legitimately goes quiet
    await sendCommand('Pause', {});
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _staleWatchdog?.cancel();
    _playNowOptions = null;
    await sendCommand('Stop', {});
  }

  @override
  Future<void> seek(Duration position) async {
    await sendCommand('Seek', {'position': position.inSeconds});
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
  // rather than SetAudio/SetSubtitleStreamIndex — the receiver's in-place
  // changeStream has a display race that flips it to the idle splash.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
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

  /// Caps the receiver's stream quality (bits/s; null = auto) and restarts so it
  /// takes effect.
  Future<void> setMaxBitrate(int? bitrate) async {
    _maxBitrate = bitrate;
    await _restartAtCurrentPosition('quality ${bitrate == null ? 'auto' : '${(bitrate / 1000000).round()}Mbps'}');
  }

  /// Points the player at a new item (user started different media mid-cast).
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

  Future<void> _restartAtCurrentPosition(String reason) async {
    final resumeAt = lastState.position;
    // Restart spins up a fresh transcode (no progress for a while) — suspend
    // the watchdog so it doesn't mistake the restart for a lost session.
    _staleWatchdog?.cancel();
    _playNowOptions = _buildPlayNowOptions(resumeAt);
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _log.info('Restarting on "$deviceName" ($reason, resume at ${resumeAt.inSeconds}s)');
    // Stop and let the receiver settle before PlayNow, else the old stream's
    // late stop event flips the receiver UI onto the new video.
    await sendCommand('Stop', {});
    await awaitReceiverStop();
    await sendCommand('PlayNow', _playNowOptions!);
  }

  /// How long/whether to wait after Stop before the new PlayNow. Default is a
  /// fixed settle; the native player overrides to wait for the receiver's idle
  /// confirmation.
  @protected
  Future<void> awaitReceiverStop() async => Future.delayed(const Duration(milliseconds: 800));

  /// The item the receiver reports it's playing — null while idle (used by
  /// remote-control adopt).
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

  @override
  Future<void> setVolume(double volume) async {
    final normalized = (volume > 1 ? volume / 100 : volume).clamp(0.0, 1.0);
    try {
      await transport.setVolume(normalized);
    } catch (error) {
      _log.fine('Failed to set device volume: $error');
    }
  }

  // The receiver owns playback rate (no protocol command exists).
  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => CastingPlaceholder(key: key, deviceName: deviceName, image: _image);

  @override
  Future<void> dispose() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _staleWatchdog?.cancel();
    for (final sub in subs) {
      await sub.cancel();
    }
    await transport.dispose();
    if (!_stateController.isClosed) await _stateController.close();
  }

  /// Builds the credentials+command envelope and sends it on the Jellyfin
  /// namespace via the [transport].
  @protected
  Future<void> sendCommand(String command, Map<String, dynamic> options) async {
    final message = buildJellyfinEnvelope(
      command: command,
      options: options,
      context: context,
      receiverName: deviceName,
      maxBitrate: _maxBitrate,
    );
    try {
      await transport.sendMessage(message);
    } catch (error) {
      _log.warning('Failed to send $command: $error');
    }
  }

  /// Subclass hook to react to each parsed report (e.g. the native player
  /// completing its stop-waiter on `playbackstop`).
  @protected
  void onReport(ReceiverReport report) {}

  void _onMessage(String raw) {
    // Any message is a sign of life — stop the retry loop.
    markAcknowledged('receiver message');
    final report = parseReceiverMessage(raw);
    if (report == null) return;
    onReport(report);

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
    // The receiver is talking to us — (re)arm the staleness watchdog while
    // playing; a takeover/teardown stops these reports and the watchdog fires.
    if (lastState.playing) {
      _armStaleWatchdog();
    } else {
      _staleWatchdog?.cancel();
    }
    _log.fine('Receiver ${report.type}: pos=${report.position?.inSeconds}s playing=${report.playing}');
  }

  void _armStaleWatchdog() {
    _staleWatchdog?.cancel();
    _staleWatchdog = Timer(_staleTimeout, () {
      signalSessionEnded('no receiver updates for ${_staleTimeout.inSeconds}s — session may have been taken over');
    });
  }

  /// Fires [onSessionEnded] once. Subclasses/transports call this on an explicit
  /// session end; the staleness watchdog calls it on silence.
  @protected
  void signalSessionEnded(String why) {
    if (_sessionEnded) return;
    _sessionEnded = true;
    _staleWatchdog?.cancel();
    _log.info('Receiver session ended ($why)');
    onSessionEnded();
  }

  /// Runs a 1s local clock advancing position while playing, so the scrubber
  /// moves smoothly between the receiver's periodic reports.
  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      lastState = lastState.update(position: lastState.position + const Duration(seconds: 1));
      _stateController.add(lastState);
    });
  }
}

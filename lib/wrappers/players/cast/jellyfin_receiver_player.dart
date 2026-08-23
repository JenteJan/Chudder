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

  // Wall-clock anchor for the position ticker: the receiver's last reported
  // position and when it arrived. Position is always computed as
  // anchor + elapsed wall time, so a frozen process (Android cached-app
  // freezer) wakes up with the position still correct instead of minutes
  // behind. Session loss is detected by each transport's authoritative signal
  // (Cast SDK session events / socket close / SESSION_ENDED) — there is
  // deliberately no message-staleness watchdog, matching the official clients.
  Duration _anchorPosition = Duration.zero;
  DateTime? _anchorTime;
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

  /// Latest device volume the receiver reported (0–100).
  int? _volumeLevel;

  @override
  int? get remoteVolumeLevel => _volumeLevel;

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
    _playNowOptions = _buildPlayNowOptions(startPosition);
    _setAnchor(startPosition);
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
    _setAnchor(lastState.position);
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _syncPositionTicker(true);
    await sendCommand('Unpause', {});
  }

  @override
  Future<void> pause() async {
    _setAnchor(lastState.position);
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _syncPositionTicker(false);
    await sendCommand('Pause', {});
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _playNowOptions = null;
    await sendCommand('Stop', {});
  }

  @override
  Future<void> seek(Duration position) async {
    await sendCommand('Seek', {'position': position.inSeconds});
    _setAnchor(position);
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
    _playNowOptions = _buildPlayNowOptions(resumeAt);
    _setAnchor(resumeAt);
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
  bool get supportsPlaybackRate => false;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) => CastingPlaceholder(key: key, deviceName: deviceName, image: _image);

  @override
  Future<void> dispose() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
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
    // Commands are user/group actions (a few per session) — log them all so
    // the cast log shows both sides of the conversation.
    _log.info('→ $command${command == 'Seek' ? ' ${options['position']}s' : ''}');
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
    if (report.volumeLevel != null) _volumeLevel = report.volumeLevel;

    // The receiver's report is the authoritative position — re-anchor to it.
    if (report.position != null) _setAnchor(report.position!);
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

  /// Fires [onSessionEnded] once. Called by transports/the provider on an
  /// authoritative session end (SDK `ended` event, socket close, SESSION_ENDED).
  @protected
  void signalSessionEnded(String why) {
    if (_sessionEnded) return;
    _sessionEnded = true;
    _log.info('Receiver session ended ($why)');
    onSessionEnded();
  }

  /// The Cast SDK suspended the session (transient network loss — it will try
  /// to reconnect on its own). Freeze the position clock and show buffering;
  /// nothing is torn down.
  void onConnectionSuspended() {
    _positionTicker?.cancel();
    _setAnchor(lastState.position);
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _log.info('Cast session suspended — waiting for the SDK to reconnect');
  }

  /// The Cast SDK re-established the suspended session. Ask the receiver where
  /// it is — its report re-anchors position, clears buffering, and restarts
  /// the ticker via [_onMessage].
  Future<void> onConnectionResumed() async {
    _log.info('Cast session resumed — resyncing with the receiver');
    await sendCommand('Identify', {});
  }

  void _setAnchor(Duration position) {
    _anchorPosition = position;
    _anchorTime = DateTime.now();
  }

  /// Runs a 1s UI clock while playing, so the scrubber moves smoothly between
  /// the receiver's periodic reports. Position is computed from the wall-clock
  /// anchor rather than incremented, so frozen timers can't make it drift.
  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final anchorTime = _anchorTime;
      if (anchorTime == null) return;
      lastState = lastState.update(position: _anchorPosition + DateTime.now().difference(anchorTime));
      _stateController.add(lastState);
    });
  }
}

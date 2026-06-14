import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/screens/video_player/components/casting_placeholder.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.web');

// --- Cast Web Sender (cast.framework) JS-interop bindings -------------------
// The framework is loaded by web/index.html, which also sets the receiver app
// id and the `__fladderCastReady` flag once `__onGCastApiAvailable` fires.

@JS('__fladderCastReady')
external JSBoolean? get _fladderCastReady;

@JS('cast.framework.CastContext')
extension type _CastContext._(JSObject _) implements JSObject {
  external static _CastContext getInstance();
  external JSPromise<JSAny?> requestSession();
  external _CastSession? getCurrentSession();
  external void addEventListener(JSString type, JSFunction handler);
  external void removeEventListener(JSString type, JSFunction handler);
}

extension type _CastSession._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> sendMessage(JSString namespace, JSString message);
  external void addMessageListener(JSString namespace, JSFunction listener);
  external void removeMessageListener(JSString namespace, JSFunction listener);
  external JSPromise<JSAny?> setVolume(JSNumber volume);
  external JSPromise<JSAny?> endSession(JSBoolean stopCasting);
}

/// The `sessionstatechanged` event payload — we only need the new state string.
extension type _SessionStateEvent._(JSObject _) implements JSObject {
  external JSString get sessionState;
}

const _sessionStateChanged = 'sessionstatechanged';
const _sessionEnded = 'SESSION_ENDED';

/// Whether the Cast Web Sender framework loaded and initialised (Chromium only).
bool webCastAvailable() => _fladderCastReady?.toDart ?? false;

/// Pops Chrome's device picker, then hands the current item to the Jellyfin
/// receiver over the session's custom namespace. [onSessionEnded] fires if the
/// session is ended from *outside* the app (Chrome's own cast UI).
Future<BasePlayer> connectWebCast(
  JellyfinCastContext context, {
  required void Function() onSessionEnded,
}) async {
  final castContext = _CastContext.getInstance();
  // requestSession() shows Chrome's own device chooser; resolves once the user
  // picks a receiver (rejects if cancelled).
  await castContext.requestSession().toDart;
  final session = castContext.getCurrentSession();
  if (session == null) {
    throw StateError('No Cast session after device selection');
  }
  _log.info('Web Cast session established');
  return WebJellyfinCastPlayer._(castContext, session, context, onSessionEnded);
}

/// A [BasePlayer] driving the Jellyfin Cast receiver from the **web** build via
/// the Cast Web Sender. Reuses the shared Jellyfin protocol
/// ([buildJellyfinEnvelope] / [parseReceiverMessage]); only the transport
/// (`session.sendMessage` / `addMessageListener`) differs from mobile.
class WebJellyfinCastPlayer extends BasePlayer implements RemotePlayer {
  WebJellyfinCastPlayer._(this._castContext, this._session, this._context, this._onSessionEnded) {
    _itemStub = _context.itemStub;
    _mediaSourceId = _context.mediaSourceId;
    _audioStreamIndex = _context.audioStreamIndex;
    _subtitleStreamIndex = _context.subtitleStreamIndex;
  }

  final _CastContext _castContext;
  final _CastSession _session;
  final JellyfinCastContext _context;
  final void Function() _onSessionEnded;

  // Mutable playback selection (seeded from the connect context), so track
  // switching mid-cast works — same model as the native player.
  late Map<String, dynamic> _itemStub;
  String? _mediaSourceId;
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  JSFunction? _messageListener;
  JSFunction? _sessionListener;
  bool _acknowledged = false;
  bool _sessionEndedFired = false;
  Timer? _playNowTimer;
  Timer? _positionTicker;

  @override
  String get deviceName => 'Chromecast';

  @override
  bool get reportsOwnProgress => true;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    final messageListener = ((JSString _, JSString message) {
      _onMessage(message.toDart);
    }).toJS;
    _messageListener = messageListener;
    _session.addMessageListener(jellyfinCastNamespace.toJS, messageListener);

    // Detect the session being ended outside the app (Chrome's cast UI).
    final sessionListener = ((_SessionStateEvent event) {
      if (event.sessionState.toDart == _sessionEnded) _handleSessionEnded();
    }).toJS;
    _sessionListener = sessionListener;
    _castContext.addEventListener(_sessionStateChanged.toJS, sessionListener);

    await _send('Identify', {});
  }

  void _handleSessionEnded() {
    if (_sessionEndedFired) return;
    _sessionEndedFired = true;
    _log.info('Cast session ended externally (Chrome UI)');
    _onSessionEnded();
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    if (_itemStub['Id'] == null) {
      _log.info('Web cast session idle — nothing to play');
      return;
    }
    _acknowledged = false;
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);
    _startPlayNowAttempts(_buildPlayNowOptions(startPosition));
  }

  Map<String, dynamic> _buildPlayNowOptions(Duration startPosition) => buildPlayNowOptions(
        itemStub: _itemStub,
        startPosition: startPosition,
        mediaSourceId: _mediaSourceId,
        audioStreamIndex: _audioStreamIndex,
        subtitleStreamIndex: _subtitleStreamIndex,
      );

  /// PlayNow with a few wide-spaced retries until the receiver acknowledges —
  /// its web app registers its listener a beat after connect (same reason as
  /// the native sender).
  void _startPlayNowAttempts(Map<String, dynamic> options) {
    _playNowTimer?.cancel();
    const retryDelays = [Duration(seconds: 5), Duration(seconds: 12), Duration(seconds: 18)];

    Future<void> attempt() async {
      if (_acknowledged) return;
      await _send('PlayNow', options);
    }

    void scheduleNext(int index) {
      if (index >= retryDelays.length) return;
      _playNowTimer = Timer(retryDelays[index], () {
        if (_acknowledged) return;
        attempt();
        scheduleNext(index + 1);
      });
    }

    attempt();
    scheduleNext(0);
  }

  @override
  Future<void> play() async {
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
  Future<void> seek(Duration position) async {
    await _send('Seek', {'position': position.inSeconds});
    lastState = lastState.update(position: position);
    _stateController.add(lastState);
  }

  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    await _send('Stop', {});
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalized = (volume > 1 ? volume / 100 : volume).clamp(0.0, 1.0);
    try {
      await _session.setVolume(normalized.toJS).toDart;
    } catch (error) {
      _log.fine('Failed to set web cast volume: $error');
    }
  }

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  // Track switching restarts playback via PlayNow at the current position (the
  // receiver has no reliable in-place changeStream) — same as the native path.
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

  Future<void> _restartAtCurrentPosition(String reason) async {
    final resumeAt = lastState.position;
    // Capture the options NOW (with the just-selected track), before the Stop:
    // progress/stop reports arriving during the settle window would otherwise
    // clobber _subtitleStreamIndex/_audioStreamIndex back to the receiver's
    // current (old) values via _onMessage, and the restart would replay the
    // original tracks. (This is why the native path builds options up front.)
    final options = _buildPlayNowOptions(resumeAt);
    _acknowledged = false;
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _log.info('Restarting web cast ($reason, resume at ${resumeAt.inSeconds}s)');
    // Stop and let the receiver settle before PlayNow, so the old stream's stop
    // event doesn't flip the receiver UI onto the new video (the native path
    // waits for an idle status; a short delay approximates that on web).
    await _send('Stop', {});
    await Future.delayed(const Duration(milliseconds: 800));
    await _send('PlayNow', options);
  }

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) =>
      CastingPlaceholder(key: key, deviceName: deviceName, image: _context.image);

  @override
  Future<void> dispose() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    // Remove the session-state listener BEFORE ending so our own endSession
    // doesn't re-enter the external-end handler.
    final sessionListener = _sessionListener;
    if (sessionListener != null) {
      try {
        _castContext.removeEventListener(_sessionStateChanged.toJS, sessionListener);
      } catch (_) {}
    }
    final messageListener = _messageListener;
    if (messageListener != null) {
      try {
        _session.removeMessageListener(jellyfinCastNamespace.toJS, messageListener);
      } catch (_) {}
    }
    try {
      await _session.endSession(false.toJS).toDart;
    } catch (_) {}
    if (!_stateController.isClosed) await _stateController.close();
  }

  Future<void> _send(String command, Map<String, dynamic> options) async {
    final message = buildJellyfinEnvelope(
      command: command,
      options: options,
      context: _context,
      receiverName: deviceName,
      maxBitrate: _context.maxBitrate,
    );
    try {
      await _session.sendMessage(jellyfinCastNamespace.toJS, message.toJS).toDart;
    } catch (error) {
      _log.warning('Failed to send $command over web cast: $error');
    }
  }

  void _onMessage(String raw) {
    _acknowledged = true;
    _playNowTimer?.cancel();
    final report = parseReceiverMessage(raw);
    if (report == null) return;
    // Mirror the receiver's authoritative track selection so the controls match.
    if (report.audioStreamIndex != null) _audioStreamIndex = report.audioStreamIndex;
    if (report.subtitleStreamIndex != null) _subtitleStreamIndex = report.subtitleStreamIndex;
    lastState = lastState.update(
      playing: report.playing,
      buffering: false,
      position: report.position,
      duration: report.duration,
    );
    _stateController.add(lastState);
    _syncPositionTicker(report.playing ?? lastState.playing);
  }

  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      lastState = lastState.update(position: lastState.position + const Duration(seconds: 1));
      _stateController.add(lastState);
    });
  }
}

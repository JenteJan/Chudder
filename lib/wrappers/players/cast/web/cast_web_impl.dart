import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
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
}

extension type _CastSession._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> sendMessage(JSString namespace, JSString message);
  external void addMessageListener(JSString namespace, JSFunction listener);
  external void removeMessageListener(JSString namespace, JSFunction listener);
  external JSPromise<JSAny?> setVolume(JSNumber volume);
  external JSPromise<JSAny?> endSession(JSBoolean stopCasting);
}

/// Whether the Cast Web Sender framework loaded and initialised (Chromium only).
bool webCastAvailable() => _fladderCastReady?.toDart ?? false;

/// Pops Chrome's device picker, then hands the current item to the Jellyfin
/// receiver over the session's custom namespace.
Future<BasePlayer> connectWebCast(JellyfinCastContext context) async {
  final ctx = _CastContext.getInstance();
  // requestSession() shows Chrome's own device chooser; resolves once the user
  // picks a receiver (rejects if cancelled).
  await ctx.requestSession().toDart;
  final session = ctx.getCurrentSession();
  if (session == null) {
    throw StateError('No Cast session after device selection');
  }
  _log.info('Web Cast session established');
  return WebJellyfinCastPlayer._(session, context);
}

/// A [BasePlayer] driving the Jellyfin Cast receiver from the **web** build via
/// the Cast Web Sender. Reuses the shared Jellyfin protocol
/// ([buildJellyfinEnvelope] / [parseReceiverMessage]); only the transport
/// (`session.sendMessage` / `addMessageListener`) differs from mobile.
///
/// v1 limitations: plays the item captured at connect (no mid-cast item switch
/// or track switch wired); volume via the Cast session.
class WebJellyfinCastPlayer extends BasePlayer implements RemotePlayer {
  WebJellyfinCastPlayer._(this._session, this._context);

  final _CastSession _session;
  final JellyfinCastContext _context;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  JSFunction? _messageListener;
  bool _acknowledged = false;
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
    // Listen for receiver → sender status on the Jellyfin namespace.
    final listener = ((JSString _, JSString message) {
      _onMessage(message.toDart);
    }).toJS;
    _messageListener = listener;
    _session.addMessageListener(jellyfinCastNamespace.toJS, listener);
    await _send('Identify', {});
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    if (_context.itemStub['Id'] == null) {
      _log.info('Web cast session idle — nothing to play');
      return;
    }
    _acknowledged = false;
    final options = buildPlayNowOptions(
      itemStub: _context.itemStub,
      startPosition: startPosition,
      mediaSourceId: _context.mediaSourceId,
      audioStreamIndex: _context.audioStreamIndex,
      subtitleStreamIndex: _context.subtitleStreamIndex,
    );
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);
    _startPlayNowAttempts(options);
  }

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

  // Track switching is not wired on web v1 (would restart via PlayNow).
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async =>
      model?.index ?? _context.audioStreamIndex ?? -1;

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async =>
      model?.index ?? _context.subtitleStreamIndex ?? -1;

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => _WebCastPlaceholder(key: key, deviceName: deviceName);

  @override
  Future<void> dispose() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    final listener = _messageListener;
    if (listener != null) {
      try {
        _session.removeMessageListener(jellyfinCastNamespace.toJS, listener);
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

class _WebCastPlaceholder extends StatelessWidget {
  const _WebCastPlaceholder({super.key, required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'Casting to $deviceName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

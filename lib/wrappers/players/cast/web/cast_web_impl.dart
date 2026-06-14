import 'dart:async';
import 'dart:js_interop';

import 'package:logging/logging.dart';

import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/cast_message_transport.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_receiver_player.dart';

final _log = Logger('Cast.jellyfin.web');

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

/// Pops Chrome's device picker, then returns a player driving the Jellyfin
/// receiver over the session. [onSessionEnded] fires if the session is ended
/// from *outside* the app (Chrome's own cast UI).
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
  return WebJellyfinCastPlayer(_WebCastTransport(castContext, session, onSessionEnded), context);
}

/// [CastMessageTransport] over the Cast Web Sender session: custom-namespace
/// messaging via `session.sendMessage`/`addMessageListener`, device volume via
/// `session.setVolume`, and detection of the session being ended outside the
/// app (Chrome's cast UI) via the `sessionstatechanged` event.
class _WebCastTransport implements CastMessageTransport {
  _WebCastTransport(this._castContext, this._session, this._onSessionEnded) {
    final messageListener = ((JSString _, JSString message) {
      if (!_messages.isClosed) _messages.add(message.toDart);
    }).toJS;
    _messageListener = messageListener;
    _session.addMessageListener(jellyfinCastNamespace.toJS, messageListener);

    final sessionListener = ((_SessionStateEvent event) {
      if (event.sessionState.toDart == _sessionEnded) _handleSessionEnded();
    }).toJS;
    _sessionListener = sessionListener;
    _castContext.addEventListener(_sessionStateChanged.toJS, sessionListener);
  }

  final _CastContext _castContext;
  final _CastSession _session;
  final void Function() _onSessionEnded;
  final StreamController<String> _messages = StreamController.broadcast();
  JSFunction? _messageListener;
  JSFunction? _sessionListener;
  bool _sessionEndedFired = false;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> sendMessage(String json) async {
    await _session.sendMessage(jellyfinCastNamespace.toJS, json.toJS).toDart;
  }

  @override
  Future<void> setVolume(double level) async {
    await _session.setVolume(level.toJS).toDart;
  }

  void _handleSessionEnded() {
    if (_sessionEndedFired) return;
    _sessionEndedFired = true;
    _log.info('Cast session ended externally (Chrome UI)');
    _onSessionEnded();
  }

  @override
  Future<void> dispose() async {
    // Remove the session listener BEFORE ending so our own endSession doesn't
    // re-enter the external-end handler.
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
    if (!_messages.isClosed) await _messages.close();
  }
}

/// The web Jellyfin Cast receiver player. The Cast Web Sender is reliable enough
/// that the base behaviour (PlayNow retry, fixed stop settle) needs no
/// platform-specific overrides — only the [_WebCastTransport].
class WebJellyfinCastPlayer extends JellyfinReceiverPlayer {
  WebJellyfinCastPlayer(CastMessageTransport transport, JellyfinCastContext context)
      : super(transport, context, 'Chromecast');
}

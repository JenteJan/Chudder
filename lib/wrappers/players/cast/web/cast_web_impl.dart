import 'dart:async';
import 'dart:js_interop';

import 'package:logging/logging.dart';

import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/cast/cast_message_transport.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_receiver_player.dart';

final _log = Logger('Cast.jellyfin.web');

// --- Cast Web Sender (cast.framework) JS-interop bindings -------------------
// The framework is loaded by web/index.html, which also sets the receiver app
// id and the `__fladderCastReady` flag once `__onGCastApiAvailable` fires.

@JS('__fladderCastReady')
external JSBoolean? get _fladderCastReady;

@JS('cast.framework.CastContext')
extension type _CastContext._(JSObject _) implements JSObject {
  external static _CastContext getInstance();
  external void setOptions(_CastOptions options);
  external JSPromise<JSAny?> requestSession();
  external _CastSession? getCurrentSession();
  external void addEventListener(JSString type, JSFunction handler);
  external void removeEventListener(JSString type, JSFunction handler);
}

extension type _CastOptions._(JSObject _) implements JSObject {
  external factory _CastOptions({JSString receiverApplicationId, JSString autoJoinPolicy});
}

extension type _CastSession._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> sendMessage(JSString namespace, JSString message);
  external void addMessageListener(JSString namespace, JSFunction listener);
  external void removeMessageListener(JSString namespace, JSFunction listener);
  external JSPromise<JSAny?> setVolume(JSNumber volume);
  external void endSession(JSBoolean stopCasting);
  external _CastDevice getCastDevice();
}

extension type _CastDevice._(JSObject _) implements JSObject {
  external JSString get friendlyName;
}

/// The `sessionstatechanged` event payload — we only need the new state string.
extension type _SessionStateEvent._(JSObject _) implements JSObject {
  external JSString get sessionState;
}

const _sessionStateChanged = 'sessionstatechanged';
const _sessionEnded = 'SESSION_ENDED';

/// `chrome.cast.AutoJoinPolicy.ORIGIN_SCOPED`: a reloaded tab of this site
/// joins the session it had.
const _originScoped = 'origin_scoped';

/// Whether the Cast Web Sender framework loaded and initialised (Chromium only).
bool webCastAvailable() => _fladderCastReady?.toDart ?? false;

/// Pops Chrome's device picker for receiver [appId], then returns a player
/// driving the Jellyfin receiver over the session. [onSessionEnded] fires if
/// the session is ended from *outside* the app (Chrome's own cast UI).
Future<BasePlayer> connectWebCast(
  JellyfinCastContext context, {
  required String appId,
  required void Function() onSessionEnded,
}) async {
  final castContext = _CastContext.getInstance();
  // The page set Jellyfin's stable receiver when the framework loaded; the
  // user may have picked another since.
  try {
    castContext.setOptions(_CastOptions(receiverApplicationId: appId.toJS, autoJoinPolicy: _originScoped.toJS));
  } catch (error) {
    _log.warning('Could not switch the Cast receiver to $appId: $error');
  }
  // requestSession() shows Chrome's own device chooser; resolves once the user
  // picks a receiver (rejects if cancelled).
  await castContext.requestSession().toDart;
  final session = castContext.getCurrentSession();
  if (session == null) {
    throw StateError('No Cast session after device selection');
  }
  _log.info('Web Cast session established');
  return _player(castContext, session, context, onSessionEnded);
}

/// The session this tab joined on its own after a reload (the framework's
/// origin-scoped auto-join), as a player — or null when there is none.
Future<BasePlayer?> resumeWebCast(
  JellyfinCastContext context, {
  required void Function() onSessionEnded,
}) async {
  if (!webCastAvailable()) return null;
  final castContext = _CastContext.getInstance();
  final session = castContext.getCurrentSession();
  if (session == null) return null;
  _log.info('Rejoining the Web Cast session');
  return _player(castContext, session, context, onSessionEnded);
}

BasePlayer _player(
  _CastContext castContext,
  _CastSession session,
  JellyfinCastContext context,
  void Function() onSessionEnded,
) {
  String deviceName;
  try {
    deviceName = session.getCastDevice().friendlyName.toDart;
  } catch (_) {
    deviceName = 'Chromecast';
  }
  return WebJellyfinCastPlayer(_WebCastTransport(castContext, session), context, deviceName, onSessionEnded);
}

/// [CastMessageTransport] over the Cast Web Sender session: custom-namespace
/// messaging via `session.sendMessage`/`addMessageListener`, device volume via
/// `session.setVolume`, and the session being ended outside the app (Chrome's
/// cast UI) via the `sessionstatechanged` event.
class _WebCastTransport implements CastMessageTransport {
  _WebCastTransport(this._castContext, this._session) {
    final messageListener = ((JSString _, JSString message) {
      if (!_messages.isClosed) _messages.add(message.toDart);
    }).toJS;
    _messageListener = messageListener;
    _session.addMessageListener(jellyfinCastNamespace.toJS, messageListener);

    final sessionListener = ((_SessionStateEvent event) {
      if (event.sessionState.toDart == _sessionEnded && !_linkEvents.isClosed) {
        _log.info('Cast session ended outside the app (Chrome UI)');
        _linkEvents.add(CastLinkEvent.ended);
      }
    }).toJS;
    _sessionListener = sessionListener;
    _castContext.addEventListener(_sessionStateChanged.toJS, sessionListener);
  }

  final _CastContext _castContext;
  final _CastSession _session;
  final StreamController<String> _messages = StreamController.broadcast();
  final StreamController<CastLinkEvent> _linkEvents = StreamController.broadcast();
  JSFunction? _messageListener;
  JSFunction? _sessionListener;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<CastLinkEvent> get linkEvents => _linkEvents.stream;

  @override
  Future<void> sendMessage(String json) async {
    await _session.sendMessage(jellyfinCastNamespace.toJS, json.toJS).toDart;
  }

  @override
  Future<void> setVolume(double level) async {
    await _session.setVolume(level.toJS).toDart;
  }

  @override
  Future<void> close({required bool stopReceiver}) async {
    // Remove the session listener BEFORE ending so our own endSession doesn't
    // read as an external end.
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
      _session.endSession(stopReceiver.toJS);
    } catch (_) {}
    if (!_messages.isClosed) await _messages.close();
    if (!_linkEvents.isClosed) await _linkEvents.close();
  }
}

/// The web Jellyfin Cast receiver player. The Cast Web Sender is reliable enough
/// that the base behaviour (PlayNow retry, stop confirmation) needs no
/// platform-specific overrides — only the [_WebCastTransport].
class WebJellyfinCastPlayer extends JellyfinReceiverPlayer {
  WebJellyfinCastPlayer(super.transport, super.context, super.deviceName, void Function() onSessionEnded)
      : super(onSessionEnded: onSessionEnded);
}

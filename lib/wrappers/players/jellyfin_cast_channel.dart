import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _log = Logger('Cast.session');

/// A granular Cast SDK session lifecycle event, relayed from the native
/// `SessionManagerListener` (see MainActivity). These are the single source of
/// truth for connection state — `suspended` is transient (the SDK
/// auto-reconnects after a network blip) and must NOT be treated as an end.
enum CastSessionEvent {
  started,
  startFailed,
  ended,
  suspended,
  resumed,
  resumeFailed;

  static CastSessionEvent? fromName(String? name) =>
      CastSessionEvent.values.where((e) => e.name == name).firstOrNull;
}

/// Bridges to the native Cast custom-message channel (see MainActivity), used to
/// talk to the Jellyfin Cast receiver over its `urn:x-cast:com.connectsdk`
/// namespace. The native side sends/receives on the active Cast session that
/// `flutter_chrome_cast` manages (same CastContext singleton).
class JellyfinCastChannel {
  JellyfinCastChannel._();
  static final JellyfinCastChannel instance = JellyfinCastChannel._();

  static const _channel = MethodChannel('uk.jentejan.chudder/cast');
  final StreamController<String> _messages = StreamController<String>.broadcast();
  final StreamController<CastSessionEvent> _sessionEvents = StreamController<CastSessionEvent>.broadcast();
  bool _handlerInstalled = false;

  /// Raw JSON messages received from the receiver on the registered namespace.
  Stream<String> get messages => _messages.stream;

  /// Session lifecycle events from the native Cast SDK listener (Android).
  /// Only flows after [startSessionMonitoring].
  Stream<CastSessionEvent> get sessionEvents => _sessionEvents.stream;

  void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments as Map?;
      switch (call.method) {
        case 'onCastMessage':
          final message = args?['message'] as String?;
          if (message != null && !_messages.isClosed) _messages.add(message);
        case 'onSessionEvent':
          final event = CastSessionEvent.fromName(args?['event'] as String?);
          _log.info('SDK session event: ${args?['event']} (detail: ${args?['detail']})');
          if (event != null && !_sessionEvents.isClosed) _sessionEvents.add(event);
      }
    });
  }

  /// Registers the native `SessionManagerListener` that feeds [sessionEvents].
  /// Requires the Cast SDK (CastContext) to already be initialized. Idempotent.
  Future<void> startSessionMonitoring() async {
    _ensureHandler();
    await _channel.invokeMethod('startSessionMonitoring');
  }

  /// Registers a message-received callback for [namespace] on the active
  /// session. The native side remembers the namespace and re-attaches it when
  /// a session restarts or resumes, so this only needs to be called once per
  /// connect.
  Future<void> registerNamespace(String namespace) async {
    _ensureHandler();
    await _channel.invokeMethod('registerNamespace', {'namespace': namespace});
  }

  /// Sends [message] (a JSON string) on [namespace] to the receiver.
  Future<void> sendMessage(String namespace, String message) async {
    await _channel.invokeMethod('sendMessage', {'namespace': namespace, 'message': message});
  }
}

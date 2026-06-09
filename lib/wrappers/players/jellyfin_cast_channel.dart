import 'dart:async';

import 'package:flutter/services.dart';

/// Bridges to the native Cast custom-message channel (see MainActivity), used to
/// talk to the Jellyfin Cast receiver over its `urn:x-cast:com.connectsdk`
/// namespace. The native side sends/receives on the active Cast session that
/// `flutter_chrome_cast` manages (same CastContext singleton).
class JellyfinCastChannel {
  JellyfinCastChannel._();
  static final JellyfinCastChannel instance = JellyfinCastChannel._();

  static const _channel = MethodChannel('nl.jknaapen.fladder/cast');
  final StreamController<String> _messages = StreamController<String>.broadcast();
  bool _handlerInstalled = false;

  /// Raw JSON messages received from the receiver on the registered namespace.
  Stream<String> get messages => _messages.stream;

  void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onCastMessage') {
        final args = call.arguments as Map?;
        final message = args?['message'] as String?;
        if (message != null && !_messages.isClosed) _messages.add(message);
      }
    });
  }

  /// Registers a message-received callback for [namespace] on the active session.
  Future<void> registerNamespace(String namespace) async {
    _ensureHandler();
    await _channel.invokeMethod('registerNamespace', {'namespace': namespace});
  }

  /// Sends [message] (a JSON string) on [namespace] to the receiver.
  Future<void> sendMessage(String namespace, String message) async {
    await _channel.invokeMethod('sendMessage', {'namespace': namespace, 'message': message});
  }
}

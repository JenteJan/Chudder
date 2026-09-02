import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:fladder/providers/websocket/websocket_log.dart';

/// WebSocket connection state.
///
/// Moved here from `lib/models/syncplay/syncplay_models.dart` so the
/// socket layer no longer depends on SyncPlay models.
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Pure platform classification for the lifecycle gate.
///
/// A "phone" (Android/iOS handheld, not Android-TV/leanback) is the only
/// platform that gets the background/resume disconnect-reconnect cycle.
/// Desktop, Web, and Android-TV/leanback stay always-alive.
///
/// Kept as a free function with no Flutter-binding dependency so it is
/// unit-testable without `TestWidgetsFlutterBinding`.
bool isPhonePlatform({
  required bool isWeb,
  required TargetPlatform platform,
  required bool leanBackMode,
}) {
  if (isWeb) {
    return false;
  }
  final isAndroidOrIos = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  return isAndroidOrIos && !leanBackMode;
}

/// Base delay of the reconnect ladder, doubled per attempt.
const Duration kBaseReconnectDelay = Duration(seconds: 2);

/// Ceiling of the reconnect ladder. Reached at attempt 4 and held forever
/// after: a socket that keeps knocking every 30s costs nothing and is the
/// difference between "SyncPlay came back on its own" and "restart the app".
const Duration kMaxReconnectDelay = Duration(seconds: 30);

/// Backoff before reconnect attempt [attempt] (0-based).
///
/// Exponential up to [kMaxReconnectDelay], then flat - the ladder never ends.
/// It used to stop after five attempts, which is only ~62s of trying: any
/// network blip longer than a minute (a laptop sleeping, a proxy dropping the
/// connection, wifi handing over) left the socket down for the entire
/// remaining life of the process. Nothing on desktop asked it to try again,
/// and `SyncPlayController.joinGroup` bails on `!isConnected` without so much
/// as contacting the server - so every later join failed instantly with
/// "Failed to join group" and no trace on either side.
///
/// Kept as a pure free function, like [isPhonePlatform], so the ladder is
/// unit-testable without a socket or a Flutter binding.
Duration reconnectDelay(
  int attempt, {
  Duration base = kBaseReconnectDelay,
  Duration max = kMaxReconnectDelay,
}) {
  if (attempt <= 0) {
    return base;
  }
  // Cap the shift before it overflows / balloons; 2^30 * base is already
  // astronomically past `max` for any sane base.
  final shift = attempt > 30 ? 30 : attempt;
  final scaled = base * (1 << shift);
  return scaled > max ? max : scaled;
}

/// Manages a single WebSocket connection to the Jellyfin server.
///
/// App-level shared connection (formerly `WebSocketManager`, owned by
/// SyncPlay). Connection / keep-alive / reconnect logic is unchanged.
class JellyfinWebSocket {
  JellyfinWebSocket({
    required this.serverUrl,
    required this.token,
    required this.deviceId,
  });

  final String serverUrl;
  final String token;
  final String deviceId;

  WebSocketChannel? _channel;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Set only by [disconnect]: the caller wants this socket to stay down.
  /// Previously expressed by pinning `_reconnectAttempts` to the give-up
  /// threshold, which conflated "the user closed it" with "it has failed a
  /// lot" - and, since the threshold was also reachable by plain bad luck,
  /// made a transient outage indistinguishable from a deliberate close.
  bool _closedByCaller = false;

  final _connectionStateController = StreamController<WebSocketConnectionState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<WebSocketConnectionState> get connectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  WebSocketConnectionState _currentState = WebSocketConnectionState.disconnected;
  WebSocketConnectionState get currentState => _currentState;

  /// Build WebSocket URL for Jellyfin
  Uri get _webSocketUri {
    final baseUri = Uri.parse(serverUrl);
    final scheme = baseUri.scheme == 'https' ? 'wss' : 'ws';
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    return Uri(
      scheme: scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: '$basePath/socket',
      queryParameters: {
        // Jellyfin 12 renamed the socket's query-string auth parameter from
        // `api_key` to `ApiKey`; a 12.x server rejects the handshake outright
        // when only the old name is sent. Older servers (<= 10.11) bind only
        // `api_key`, and the names differ by more than case so neither binds
        // the other. Send both so a single build works against either — the
        // server ignores whichever parameter it does not know.
        'api_key': token,
        'ApiKey': token,
        'deviceId': deviceId,
      },
    );
  }

  /// The socket URI with every token-bearing query parameter masked, for
  /// logging. Covers both auth parameter names sent by [_webSocketUri].
  String get _redactedUri => _webSocketUri.toString().replaceAllMapped(
        RegExp(r'(api_key|ApiKey)=[^&]+'),
        (match) => '${match[1]}=***',
      );

  /// Connect to WebSocket
  Future<void> connect() async {
    if (_currentState == WebSocketConnectionState.connected || _currentState == WebSocketConnectionState.connecting) {
      return;
    }

    // Asking to connect revokes an earlier deliberate close.
    _closedByCaller = false;
    _updateState(WebSocketConnectionState.connecting);

    try {
      log('WebSocket: Connecting to $_redactedUri');
      _channel = WebSocketChannel.connect(_webSocketUri);
      await _channel!.ready;

      _updateState(WebSocketConnectionState.connected);
      _reconnectAttempts = 0;

      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );
    } catch (e) {
      log('WebSocket connection failed: $e');
      _updateState(WebSocketConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    _closedByCaller = true; // Prevent auto-reconnect

    await _channel?.sink.close();
    _channel = null;
    _updateState(WebSocketConnectionState.disconnected);
  }

  /// Force reconnect (e.g., after app resume)
  /// Resets attempt counter and immediately reconnects
  Future<void> forceReconnect() async {
    _reconnectTimer?.cancel();
    _keepAliveTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _reconnectAttempts = 0;
    _updateState(WebSocketConnectionState.disconnected);
    await connect();
  }

  /// Send a message through WebSocket
  void send(Map<String, dynamic> message) {
    if (_currentState != WebSocketConnectionState.connected) {
      log('Cannot send message: WebSocket not connected');
      return;
    }

    try {
      _channel?.sink.add(json.encode(message));
    } catch (e) {
      log('Failed to send WebSocket message: $e');
    }
  }

  /// Send keep-alive message
  void _sendKeepAlive() {
    send({'MessageType': 'KeepAlive'});
  }

  void _handleMessage(dynamic data) {
    try {
      final message = json.decode(data as String) as Map<String, dynamic>;
      final messageType = message['MessageType'] as String?;

      // Log all received messages for debugging (except KeepAlive spam)
      if (messageType != 'KeepAlive' && messageType != 'RefreshProgress') {
        // The whole payload only for SyncPlay, whose messages are small and
        // whose traces are read; a Sessions payload is kilobytes, and
        // stringifying it for a log line was paid on the UI isolate for
        // every one the server pushed.
        final isSyncPlay = messageType?.startsWith('SyncPlay') ?? false;
        log(isSyncPlay || kDebugMode ? 'WebSocket: Received message: $message' : 'WebSocket: Received $messageType');
      }

      // Handle ForceKeepAlive to set up keep-alive interval
      if (messageType == 'ForceKeepAlive') {
        final timeoutSeconds = message['Data'] as int? ?? 60;
        _setupKeepAlive(timeoutSeconds);
      }

      // Forward message to listeners
      _messageController.add(message);
    } catch (e) {
      log('Failed to parse WebSocket message: $e\nRaw data: $data');
    }
  }

  void _handleError(dynamic error) {
    log('WebSocket error: $error');
    _updateState(WebSocketConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _handleDone() {
    log('WebSocket connection closed');
    _keepAliveTimer?.cancel();

    if (_currentState != WebSocketConnectionState.disconnected) {
      _updateState(WebSocketConnectionState.disconnected);
      _scheduleReconnect();
    }
  }

  void _setupKeepAlive(int timeoutSeconds) {
    _keepAliveTimer?.cancel();
    // Send keep-alive at half the timeout interval
    final interval = Duration(seconds: (timeoutSeconds * 0.5).round());
    _keepAliveTimer = Timer.periodic(interval, (_) => _sendKeepAlive());
  }

  void _scheduleReconnect() {
    if (_closedByCaller) {
      log('WebSocket: closed by caller, not reconnecting');
      return;
    }

    _reconnectTimer?.cancel();
    _updateState(WebSocketConnectionState.reconnecting);

    final delay = reconnectDelay(_reconnectAttempts);
    _reconnectAttempts++;

    log('WebSocket: scheduling reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(delay, connect);
  }

  void _updateState(WebSocketConnectionState state) {
    _currentState = state;
    _connectionStateController.add(state);
  }

  /// Dispose resources
  Future<void> dispose() async {
    await disconnect();
    await _connectionStateController.close();
    await _messageController.close();
  }
}

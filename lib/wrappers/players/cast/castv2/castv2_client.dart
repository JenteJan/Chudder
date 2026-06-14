import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:fladder/wrappers/players/cast/castv2/cast_message.dart';
import 'package:fladder/wrappers/players/cast/castv2/cast_protocol.dart';

final _log = Logger('Cast.castv2');

/// The byte transport under [Castv2Client]. Abstracted so the protocol state
/// machine can be exercised with a fake in tests; the real implementation is
/// [TlsCastSocket] over a Chromecast's self-signed TLS endpoint (port 8009).
abstract class CastSocket {
  Stream<List<int>> get stream;
  void add(List<int> data);
  Future<void> close();
}

/// Live TLS socket to a Chromecast. Not unit-tested (needs a device); the
/// protocol logic that uses it lives in [Castv2Client] and is tested via a
/// fake [CastSocket].
class TlsCastSocket implements CastSocket {
  TlsCastSocket._(this._socket);
  final SecureSocket _socket;

  static Future<TlsCastSocket> connect(String host, int port,
      {Duration timeout = const Duration(seconds: 10)}) async {
    // Chromecasts present a self-signed certificate; trust it for the LAN
    // control channel (the media itself is fetched separately).
    final socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    socket.setOption(SocketOption.tcpNoDelay, true);
    return TlsCastSocket._(socket);
  }

  @override
  Stream<List<int>> get stream => _socket;
  @override
  void add(List<int> data) => _socket.add(data);
  @override
  Future<void> close() => _socket.close();
}

/// A pending request awaiting its response (correlated by `requestId`).
class _PendingRequest {
  final Completer<Map<String, dynamic>> completer = Completer();
  Timer? timeout;
}

/// Minimal CASTV2 client: frames/deframes [CastMessage]s over a [CastSocket],
/// keeps the heartbeat alive, opens virtual connections, correlates
/// request/response by `requestId`, and exposes incoming custom-namespace
/// messages (the Jellyfin receiver protocol).
///
/// This owns *transport*; the receiver-protocol envelopes and media policy
/// live a layer up (reused from the existing players).
class Castv2Client {
  Castv2Client(this._socket);

  final CastSocket _socket;
  final CastFramer _framer = CastFramer();
  final Map<int, _PendingRequest> _pending = {};
  final StreamController<CastMessage> _incoming = StreamController.broadcast();

  int _requestId = 1;
  Timer? _heartbeat;
  bool _closed = false;

  /// All incoming messages, after PING auto-reply. Most callers want
  /// [customMessages] instead.
  Stream<CastMessage> get messages => _incoming.stream;

  /// Incoming messages on the Jellyfin custom namespace, as raw JSON strings —
  /// the same shape the mobile bridge delivers.
  Stream<String> get customMessages => _incoming.stream
      .where((m) => m.namespace == CastProtocol.jellyfin && m.payloadUtf8 != null)
      .map((m) => m.payloadUtf8!);

  int nextRequestId() => _requestId++;

  /// Begins reading from the socket, opens the virtual connection to the
  /// platform receiver, and starts the heartbeat.
  void start({Duration heartbeatInterval = const Duration(seconds: 5)}) {
    _socket.stream.listen(
      _onData,
      onError: (Object e, StackTrace s) => _log.warning('socket error', e, s),
      onDone: _onDone,
      cancelOnError: false,
    );
    _sendString(CastProtocol.platformReceiverId, CastProtocol.tpConnection, CastProtocol.connect());
    _heartbeat = Timer.periodic(heartbeatInterval, (_) {
      if (!_closed) {
        _sendString(CastProtocol.platformReceiverId, CastProtocol.tpHeartbeat, CastProtocol.ping());
      }
    });
  }

  /// Launches [appId] and resolves with the receiver status once that app
  /// reports a transport id. Also opens the virtual connection to it.
  Future<ReceiverStatus> launch(String appId,
      {Duration timeout = const Duration(seconds: 15)}) async {
    final reply = await _request(
      CastProtocol.platformReceiverId,
      CastProtocol.receiver,
      (id) => CastProtocol.launch(appId, id),
      timeout: timeout,
    );
    final status = ReceiverStatus.parse(jsonEncode(reply));
    final transport = status.transportFor(appId);
    if (transport != null) {
      // Open a virtual connection to the launched app so it accepts messages.
      _sendString(transport, CastProtocol.tpConnection, CastProtocol.connect());
    }
    return status;
  }

  /// Sends a custom-namespace (Jellyfin) JSON message to [transportId].
  void sendCustom(String transportId, String json) =>
      _sendString(transportId, CastProtocol.jellyfin, json);

  /// Sends a media-namespace command to [transportId] and returns nothing;
  /// status arrives asynchronously on [messages] as MEDIA_STATUS.
  void sendMedia(String transportId, String json) =>
      _sendString(transportId, CastProtocol.media, json);

  Future<void> setVolume(double level) async {
    await _request(
      CastProtocol.platformReceiverId,
      CastProtocol.receiver,
      (id) => CastProtocol.setVolume(level, id),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    for (final p in _pending.values) {
      p.timeout?.cancel();
      if (!p.completer.isCompleted) {
        p.completer.completeError(StateError('client closed'));
      }
    }
    _pending.clear();
    try {
      _sendString(CastProtocol.platformReceiverId, CastProtocol.tpConnection, CastProtocol.close());
    } catch (_) {/* socket may already be gone */}
    await _socket.close();
    await _incoming.close();
  }

  /// Sends a message with a fresh requestId and resolves when a reply carrying
  /// the same requestId arrives.
  Future<Map<String, dynamic>> _request(
    String destination,
    String namespace,
    String Function(int requestId) build, {
    Duration timeout = const Duration(seconds: 10),
  }) {
    final id = nextRequestId();
    final pending = _PendingRequest();
    _pending[id] = pending;
    pending.timeout = Timer(timeout, () {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(TimeoutException('Cast request $id timed out'));
      }
      _pending.remove(id);
    });
    _sendString(destination, namespace, build(id));
    return pending.completer.future;
  }

  void _onData(List<int> data) {
    for (final message in _framer.addBytes(data)) {
      _handle(message);
    }
  }

  void _handle(CastMessage message) {
    // Auto-reply to heartbeat PINGs so the receiver doesn't drop the channel.
    if (message.namespace == CastProtocol.tpHeartbeat) {
      if (message.payloadUtf8 != null &&
          CastProtocol.messageType(message.payloadUtf8!) == 'PING') {
        _sendString(message.sourceId, CastProtocol.tpHeartbeat, CastProtocol.pong());
      }
      return;
    }

    // Correlate replies to pending requests by requestId.
    final payload = message.payloadUtf8;
    if (payload != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {
        decoded = null;
      }
      if (decoded is Map && decoded['requestId'] is int) {
        final pending = _pending.remove(decoded['requestId'] as int);
        if (pending != null) {
          pending.timeout?.cancel();
          if (!pending.completer.isCompleted) {
            pending.completer.complete(decoded.cast<String, dynamic>());
          }
        }
      }
    }

    if (!_incoming.isClosed) _incoming.add(message);
  }

  void _onDone() {
    if (!_closed) {
      _log.info('Cast socket closed by peer');
      close();
    }
  }

  void _sendString(String destination, String namespace, String payload) {
    if (_closed) return;
    final message = CastMessage.string(
      sourceId: CastProtocol.senderId,
      destinationId: destination,
      namespace: namespace,
      payload: payload,
    );
    _socket.add(message.frame());
  }
}

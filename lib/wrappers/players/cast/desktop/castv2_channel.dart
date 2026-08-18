import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger('Cast.castv2');

/// The three system namespaces every Cast receiver speaks, plus the framing
/// constants. See the (unofficial but stable since 2013) CASTV2 protocol.
const _connectionNs = 'urn:x-cast:com.google.cast.tp.connection';
const _heartbeatNs = 'urn:x-cast:com.google.cast.tp.heartbeat';
const _receiverNs = 'urn:x-cast:com.google.cast.receiver';

const _defaultSender = 'sender-0';
const _platformReceiver = 'receiver-0';

/// Chromecasts drop a connection that goes quiet for ~10s.
const _heartbeatInterval = Duration(seconds: 5);

/// A `CastMessage` as it goes over the wire.
class _CastMessage {
  _CastMessage(this.sourceId, this.destinationId, this.namespace, this.payload);

  final String sourceId;
  final String destinationId;
  final String namespace;
  final String payload;
}

// --- Minimal protobuf codec -------------------------------------------------
// `CastMessage` has seven fields and we only ever use the STRING payload, so a
// hand-rolled encoder is far cheaper than pulling in protoc codegen:
//
//   1 protocol_version (varint enum, CASTV2_1_0 = 0)   5 payload_type (varint enum, STRING = 0)
//   2 source_id        (string)                        6 payload_utf8 (string)
//   3 destination_id   (string)                        7 payload_binary (bytes, unused)
//   4 namespace        (string)

void _writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
}

void _writeString(BytesBuilder out, int field, String value) {
  final bytes = utf8.encode(value);
  _writeVarint(out, (field << 3) | 2); // wire type 2: length-delimited
  _writeVarint(out, bytes.length);
  out.add(bytes);
}

Uint8List _encodeCastMessage(_CastMessage message) {
  final out = BytesBuilder();
  _writeVarint(out, (1 << 3) | 0); // protocol_version
  _writeVarint(out, 0); // CASTV2_1_0
  _writeString(out, 2, message.sourceId);
  _writeString(out, 3, message.destinationId);
  _writeString(out, 4, message.namespace);
  _writeVarint(out, (5 << 3) | 0); // payload_type
  _writeVarint(out, 0); // STRING
  _writeString(out, 6, message.payload);
  return out.toBytes();
}

/// Reads a varint, returning the value and the offset just past it.
(int value, int next) _readVarint(Uint8List bytes, int offset) {
  var result = 0;
  var shift = 0;
  var i = offset;
  while (i < bytes.length) {
    final byte = bytes[i++];
    result |= (byte & 0x7F) << shift;
    if (byte & 0x80 == 0) return (result, i);
    shift += 7;
  }
  throw const FormatException('Truncated varint in CastMessage');
}

_CastMessage _decodeCastMessage(Uint8List bytes) {
  var offset = 0;
  var sourceId = '', destinationId = '', namespace = '', payload = '';
  while (offset < bytes.length) {
    final (tag, afterTag) = _readVarint(bytes, offset);
    offset = afterTag;
    final field = tag >> 3;
    final wireType = tag & 7;
    if (wireType == 0) {
      final (_, afterValue) = _readVarint(bytes, offset);
      offset = afterValue;
      continue;
    }
    if (wireType != 2) throw FormatException('Unsupported wire type $wireType in CastMessage');
    final (length, afterLength) = _readVarint(bytes, offset);
    final value = bytes.sublist(afterLength, afterLength + length);
    offset = afterLength + length;
    switch (field) {
      case 2:
        sourceId = utf8.decode(value);
      case 3:
        destinationId = utf8.decode(value);
      case 4:
        namespace = utf8.decode(value);
      case 6:
        payload = utf8.decode(value);
      // 7 (payload_binary) is never sent by the receivers we talk to.
    }
  }
  return _CastMessage(sourceId, destinationId, namespace, payload);
}

/// A live CASTV2 connection to one Chromecast, with an application launched and
/// a virtual connection open to it.
///
/// This is the desktop stand-in for the Google Cast SDK (Android/iOS) and the
/// Cast Web Sender (web) — Windows/Linux have no first-party SDK, but the wire
/// protocol is the same everywhere, so the receiver can't tell the difference.
class CastV2Channel {
  CastV2Channel._(this._socket, this._socketSub, this._transportId, this._sessionId);

  final SecureSocket _socket;

  /// The launched application's virtual-connection id — every custom-namespace
  /// message is addressed here, not to `receiver-0`.
  final String _transportId;
  final String _sessionId;

  Timer? _heartbeat;
  StreamSubscription<Uint8List>? _socketSub;
  bool _disposed = false;

  final _custom = StreamController<String>.broadcast();

  /// Messages received on a non-system namespace (i.e. the Jellyfin receiver's).
  Stream<String> get customMessages => _custom.stream;

  /// Fires when the connection drops from the far end — receiver closed, device
  /// powered off, or another sender took it over.
  final _closed = Completer<void>();
  Future<void> get onClosed => _closed.future;

  var _requestId = 1;
  int _nextRequestId() => _requestId++;

  /// Opens a connection to [host]:[port] and launches [appId].
  ///
  /// Chromecasts present a self-signed device certificate, so verification is
  /// necessarily disabled — the Cast SDKs do the same. The link is still
  /// encrypted; it just isn't authenticated, which is why we never put anything
  /// but the Jellyfin session envelope over it.
  static Future<CastV2Channel> connect(
    String host,
    int port,
    String appId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _log.info('Opening CASTV2 connection to $host:$port');
    final socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    // Nagle would delay our small JSON control messages.
    socket.setOption(SocketOption.tcpNoDelay, true);

    // A Socket is single-subscription, so there is exactly one listener for the
    // life of the connection and the handler is swapped once the handshake is
    // done. Messages seen during the handshake are kept so any that arrive on
    // the custom namespace in that window can be replayed rather than dropped.
    final pending = StreamController<_CastMessage>.broadcast();
    final backlog = <_CastMessage>[];
    CastV2Channel? channel;
    void handle(_CastMessage message) {
      final active = channel;
      if (active != null) {
        active._route(message);
        return;
      }
      backlog.add(message);
      if (!pending.isClosed) pending.add(message);
    }

    final buffer = BytesBuilder();
    final sub = socket.listen(
      (chunk) {
        buffer.add(chunk);
        _drainFrames(buffer, handle);
      },
      onError: (Object error, StackTrace stack) {
        _log.warning('CASTV2 socket error', error, stack);
        channel?._handleClosed();
      },
      onDone: () => channel?._handleClosed(),
      cancelOnError: false,
    );

    void sendRaw(String destination, String namespace, Map<String, dynamic> payload) {
      final message = _CastMessage(_defaultSender, destination, namespace, jsonEncode(payload));
      final body = _encodeCastMessage(message);
      final frame = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
        ..add(body);
      socket.add(frame.toBytes());
    }

    try {
      // Virtual connection to the platform receiver, then launch the app.
      sendRaw(_platformReceiver, _connectionNs, {'type': 'CONNECT'});
      final launchRequest = 1;
      sendRaw(_platformReceiver, _receiverNs, {
        'type': 'LAUNCH',
        'appId': appId,
        'requestId': launchRequest,
      });

      // RECEIVER_STATUS arrives repeatedly while the app boots; wait for the one
      // that actually carries our app with a transportId.
      final status = await pending.stream
          .where((message) => message.namespace == _receiverNs)
          .map((message) => jsonDecode(message.payload) as Map<String, dynamic>)
          .where((payload) => payload['type'] == 'RECEIVER_STATUS')
          .map((payload) => _findApplication(payload, appId))
          .where((application) => application != null)
          .cast<Map<String, dynamic>>()
          .first
          .timeout(timeout, onTimeout: () => throw TimeoutException('Receiver never launched $appId', timeout));

      final transportId = status['transportId'] as String;
      final sessionId = status['sessionId'] as String;
      _log.info('Launched $appId (session $sessionId, transport $transportId)');

      // Second virtual connection, this time to the running application.
      sendRaw(transportId, _connectionNs, {'type': 'CONNECT'});

      final connected = CastV2Channel._(socket, sub, transportId, sessionId);
      // Publishing `channel` is what switches `handle` over to routing.
      channel = connected;
      await pending.close();

      // Replay only non-system traffic from the handshake window. System
      // frames must not be replayed: a RECEIVER_STATUS captured before our app
      // appeared would look like our session had vanished and immediately tear
      // the connection down.
      for (final message in backlog) {
        if (message.namespace != _connectionNs &&
            message.namespace != _heartbeatNs &&
            message.namespace != _receiverNs) {
          connected._route(message);
        }
      }

      connected._start();
      return connected;
    } catch (error) {
      await sub.cancel();
      await pending.close();
      socket.destroy();
      rethrow;
    }
  }

  /// Pulls every complete `[4-byte length][body]` frame out of [buffer].
  static void _drainFrames(BytesBuilder buffer, void Function(_CastMessage) emit) {
    var bytes = buffer.toBytes();
    var consumed = 0;
    while (bytes.length - consumed >= 4) {
      final length = ByteData.sublistView(bytes, consumed, consumed + 4).getUint32(0);
      if (bytes.length - consumed - 4 < length) break;
      final body = bytes.sublist(consumed + 4, consumed + 4 + length);
      consumed += 4 + length;
      try {
        emit(_decodeCastMessage(body));
      } catch (error, stack) {
        _log.warning('Dropping malformed CastMessage', error, stack);
      }
    }
    if (consumed > 0) {
      final rest = bytes.sublist(consumed);
      buffer.clear();
      buffer.add(rest);
    }
  }

  static Map<String, dynamic>? _findApplication(Map<String, dynamic> payload, String appId) {
    final applications = (payload['status'] as Map<String, dynamic>?)?['applications'] as List<dynamic>?;
    if (applications == null) return null;
    for (final application in applications.cast<Map<String, dynamic>>()) {
      if (application['appId'] == appId && application['transportId'] != null) return application;
    }
    return null;
  }

  /// Starts the keepalive once the handshake is done.
  void _start() {
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (_disposed) return;
      _send(_platformReceiver, _heartbeatNs, {'type': 'PING'});
    });
  }

  void _route(_CastMessage message) {
    switch (message.namespace) {
      case _heartbeatNs:
        // The receiver pings us too; silence gets the connection dropped.
        if (_payloadType(message) == 'PING') {
          _send(_platformReceiver, _heartbeatNs, {'type': 'PONG'});
        }
      case _connectionNs:
        if (_payloadType(message) == 'CLOSE') {
          _log.info('Receiver closed the virtual connection');
          _handleClosed();
        }
      case _receiverNs:
        // A RECEIVER_STATUS with our app gone means it was stopped or replaced.
        final payload = _tryDecode(message.payload);
        if (payload != null && payload['type'] == 'RECEIVER_STATUS' && _sessionGone(payload)) {
          _log.info('Receiver dropped our session');
          _handleClosed();
        }
      default:
        if (!_custom.isClosed) _custom.add(message.payload);
    }
  }

  bool _sessionGone(Map<String, dynamic> payload) {
    final applications = (payload['status'] as Map<String, dynamic>?)?['applications'] as List<dynamic>?;
    // A status with no applications at all is the idle screen; one listing other
    // sessions means someone else took the device.
    if (applications == null) return false;
    return !applications.cast<Map<String, dynamic>>().any((app) => app['sessionId'] == _sessionId);
  }

  String? _payloadType(_CastMessage message) => _tryDecode(message.payload)?['type'] as String?;

  Map<String, dynamic>? _tryDecode(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void _send(String destination, String namespace, Map<String, dynamic> payload) {
    if (_disposed) return;
    try {
      final body = _encodeCastMessage(_CastMessage(_defaultSender, destination, namespace, jsonEncode(payload)));
      final frame = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
        ..add(body);
      _socket.add(frame.toBytes());
    } catch (error, stack) {
      _log.warning('Failed to write to the Cast socket', error, stack);
    }
  }

  /// Sends a raw JSON string on [namespace] to the launched application.
  void sendCustom(String namespace, String json) {
    if (_disposed) return;
    // The Jellyfin envelope is already-encoded JSON, so it's spliced in rather
    // than re-encoded through a Map.
    final body = _encodeCastMessage(_CastMessage(_defaultSender, _transportId, namespace, json));
    final frame = BytesBuilder()
      ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
      ..add(body);
    try {
      _socket.add(frame.toBytes());
    } catch (error, stack) {
      _log.warning('Failed to send custom message', error, stack);
    }
  }

  /// Sets the *device* volume (0.0–1.0), matching what the SDK senders expose.
  void setVolume(double level) {
    _send(_platformReceiver, _receiverNs, {
      'type': 'SET_VOLUME',
      'volume': {'level': level.clamp(0.0, 1.0)},
      'requestId': _nextRequestId(),
    });
  }

  void _handleClosed() {
    if (_closed.isCompleted) return;
    _closed.complete();
  }

  /// Stops the receiver app and tears the socket down.
  Future<void> dispose({bool stopReceiver = true}) async {
    if (_disposed) return;
    if (stopReceiver) {
      _send(_platformReceiver, _receiverNs, {
        'type': 'STOP',
        'sessionId': _sessionId,
        'requestId': _nextRequestId(),
      });
      // Give the STOP a moment to reach the wire before we close under it.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _socketSub?.cancel();
    _socketSub = null;
    _handleClosed();
    await _custom.close();
    try {
      await _socket.close();
    } catch (_) {}
    _socket.destroy();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:logging/logging.dart';

final _log = Logger('Cast.castv2');

/// The three system namespaces every Cast receiver speaks, plus the framing
/// constants. See the (unofficial but stable since 2013) CASTV2 protocol.
const _connectionNs = 'urn:x-cast:com.google.cast.tp.connection';
const _heartbeatNs = 'urn:x-cast:com.google.cast.tp.heartbeat';
const _receiverNs = 'urn:x-cast:com.google.cast.receiver';

const _defaultSender = 'sender-0';
const _platformReceiver = 'receiver-0';

/// Chromecasts drop a connection that goes quiet for ~10s, so we ping well
/// inside that.
const _heartbeatInterval = Duration(seconds: 5);

/// No frame at all from the device for this long means the link is dead — the
/// device answers every PING, so silence is not a quiet receiver. Matches
/// node-castv2-client (3 × 5s) and pychromecast (10s + 10s).
const _silenceLimit = Duration(seconds: 20);

/// Why a [CastV2Channel] is over.
enum CastChannelEnd {
  /// We closed it ([CastV2Channel.close] / [CastV2Channel.stop]).
  closedByUs,

  /// The receiver app went away: stopped from the TV, idle timeout, or
  /// another app took the device. Nothing to reconnect to.
  sessionEnded,

  /// The link broke (Wi-Fi drop, device rebooting, silence) while the app on
  /// the device may well still be running — worth rejoining.
  connectionLost,
}

/// The session asked to rejoin is no longer running on the device.
class CastSessionGoneException implements Exception {
  const CastSessionGoneException(this.sessionId);
  final String sessionId;

  @override
  String toString() => 'Cast session $sessionId is no longer running';
}

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

/// A length-prefixed frame, as it goes on the socket.
Uint8List _frame(_CastMessage message) {
  final body = _encodeCastMessage(message);
  return (BytesBuilder()
        ..add((ByteData(4)..setUint32(0, body.length)).buffer.asUint8List())
        ..add(body))
      .toBytes();
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

/// Encodes one frame; for tests of the codec.
@visibleForTesting
Uint8List encodeCastFrameForTest(String namespace, String payload, {String destination = _platformReceiver}) =>
    _frame(_CastMessage(_defaultSender, destination, namespace, payload));

/// Decodes the frames in [bytes] to (namespace, payload); for tests of the codec.
@visibleForTesting
List<(String, String)> decodeCastFramesForTest(Uint8List bytes) {
  final out = <(String, String)>[];
  CastV2Channel._drainFrames(BytesBuilder()..add(bytes), (message) => out.add((message.namespace, message.payload)));
  return out;
}

/// Finds [appId] among the applications of a `RECEIVER_STATUS` payload.
Map<String, dynamic>? _findApplication(Map<String, dynamic> payload, String appId) {
  final applications = (payload['status'] as Map<String, dynamic>?)?['applications'] as List<dynamic>?;
  if (applications == null) return null;
  for (final application in applications.cast<Map<String, dynamic>>()) {
    if (application['appId'] == appId && application['transportId'] != null) return application;
  }
  return null;
}

/// Whether a `RECEIVER_STATUS` [payload] shows session [sessionId] gone. The
/// device always sends its whole status; with no app running (its idle screen)
/// that status has no `applications` at all, and one listing other apps means
/// someone else took the device.
@visibleForTesting
bool receiverStatusShowsSessionGone(Map<String, dynamic> payload, String sessionId) {
  final status = payload['status'];
  if (status is! Map) return false;
  final applications = status['applications'];
  if (applications is! List) return true;
  return !applications.whereType<Map>().any((app) => app['sessionId'] == sessionId);
}

/// A live CASTV2 connection to one Chromecast, with an application launched
/// (or joined) and a virtual connection open to it.
///
/// This is the desktop stand-in for the Google Cast SDK (Android/iOS) and the
/// Cast Web Sender (web) — Windows/Linux have no first-party SDK, but the wire
/// protocol is the same everywhere, so the receiver can't tell the difference.
class CastV2Channel {
  CastV2Channel._(this._socket, this.host, this.port, this._transportId, this.sessionId);

  final SecureSocket _socket;
  final String host;
  final int port;

  /// The launched application's virtual-connection id — every custom-namespace
  /// message is addressed here, not to `receiver-0`.
  final String _transportId;

  /// The receiver app's session, which a later connection can rejoin.
  final String sessionId;

  StreamSubscription<Uint8List>? _socketSub;
  Timer? _heartbeat;
  DateTime _lastInbound = DateTime.now();
  bool _disposed = false;

  final _custom = StreamController<String>.broadcast();

  /// Messages received on a non-system namespace (i.e. the Jellyfin receiver's).
  Stream<String> get customMessages => _custom.stream;

  final _ended = Completer<CastChannelEnd>();

  /// Completes once, with why the channel is over.
  Future<CastChannelEnd> get onEnded => _ended.future;

  var _requestId = 1;
  int _nextRequestId() => _requestId++;

  /// Opens a connection to [host]:[port] and gets [appId] running.
  ///
  /// When the app already runs on the device it is joined rather than
  /// launched again (a relaunch drops whatever it was playing). With
  /// [joinSessionId] only that very session is joined, and a
  /// [CastSessionGoneException] says it is over — how a dropped connection or
  /// a restarted app finds its way back without starting anything new.
  ///
  /// Chromecasts present a self-signed device certificate, so verification is
  /// necessarily disabled — the Cast SDKs do the same. The link is still
  /// encrypted; it just isn't authenticated, which is why we never put anything
  /// but the Jellyfin session envelope over it.
  static Future<CastV2Channel> connect(
    String host,
    int port,
    String appId, {
    String? joinSessionId,
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
        channel?._lastInbound = DateTime.now();
        buffer.add(chunk);
        _drainFrames(buffer, handle);
      },
      onError: (Object error, StackTrace stack) {
        _log.warning('CASTV2 socket error', error, stack);
        channel?._end(CastChannelEnd.connectionLost);
      },
      onDone: () => channel?._end(CastChannelEnd.connectionLost),
      cancelOnError: false,
    );

    void sendRaw(String destination, String namespace, Map<String, dynamic> payload) =>
        socket.add(_frame(_CastMessage(_defaultSender, destination, namespace, jsonEncode(payload))));

    Future<Map<String, dynamic>> nextStatus(bool Function(Map<String, dynamic> status) accept) => pending.stream
        .where((message) => message.namespace == _receiverNs)
        .map((message) => jsonDecode(message.payload) as Map<String, dynamic>)
        .where((payload) => payload['type'] == 'RECEIVER_STATUS' && accept(payload))
        .first
        .timeout(timeout, onTimeout: () => throw TimeoutException('No receiver status from $host', timeout));

    try {
      sendRaw(_platformReceiver, _connectionNs, {'type': 'CONNECT'});
      // Each wait subscribes before its request goes out.
      final currentStatus = nextStatus((_) => true);
      sendRaw(_platformReceiver, _receiverNs, {'type': 'GET_STATUS', 'requestId': 1});
      var application = _findApplication(await currentStatus, appId);

      if (joinSessionId != null && application?['sessionId'] != joinSessionId) {
        throw CastSessionGoneException(joinSessionId);
      }
      if (application != null) {
        _log.info('$appId already running on $host — joining it');
      } else {
        // RECEIVER_STATUS arrives repeatedly while the app boots; wait for the
        // one that actually carries our app with a transportId.
        final launched = nextStatus((status) => _findApplication(status, appId) != null);
        sendRaw(_platformReceiver, _receiverNs, {'type': 'LAUNCH', 'appId': appId, 'requestId': 2});
        application = _findApplication(await launched, appId);
      }

      final transportId = application!['transportId'] as String;
      final sessionId = application['sessionId'] as String;
      _log.info('Connected to $appId (session $sessionId, transport $transportId)');

      // Second virtual connection, this time to the running application.
      sendRaw(transportId, _connectionNs, {'type': 'CONNECT'});

      final connected = CastV2Channel._(socket, host, port, transportId, sessionId).._socketSub = sub;
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

  /// Starts the keepalive and the silence watch once the handshake is done.
  void _start() {
    _lastInbound = DateTime.now();
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) {
      if (_disposed) return;
      if (DateTime.now().difference(_lastInbound) > _silenceLimit) {
        _log.warning('No word from $host for ${_silenceLimit.inSeconds}s — treating the link as lost');
        _end(CastChannelEnd.connectionLost);
        return;
      }
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
          _end(CastChannelEnd.sessionEnded);
        }
      case _receiverNs:
        final payload = _tryDecode(message.payload);
        if (payload != null &&
            payload['type'] == 'RECEIVER_STATUS' &&
            receiverStatusShowsSessionGone(payload, sessionId)) {
          _log.info('Receiver dropped our session');
          _end(CastChannelEnd.sessionEnded);
        }
      default:
        if (!_custom.isClosed) _custom.add(message.payload);
    }
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
      _socket.add(_frame(_CastMessage(_defaultSender, destination, namespace, jsonEncode(payload))));
    } catch (error, stack) {
      _log.warning('Failed to write to the Cast socket', error, stack);
    }
  }

  /// Sends a raw JSON string on [namespace] to the launched application.
  void sendCustom(String namespace, String json) {
    if (_disposed) return;
    // The Jellyfin envelope is already-encoded JSON, so it's spliced in rather
    // than re-encoded through a Map.
    try {
      _socket.add(_frame(_CastMessage(_defaultSender, _transportId, namespace, json)));
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

  void _end(CastChannelEnd reason) {
    if (_ended.isCompleted) return;
    _ended.complete(reason);
    if (reason != CastChannelEnd.closedByUs) unawaited(_release());
  }

  /// Leaves: closes our virtual connections and the socket, and the app on the
  /// device plays on. What pychromecast, VLC and go-chromecast do on
  /// disconnect; stopping the app is a separate, explicit [stop].
  Future<void> close() async {
    if (_disposed) return;
    _send(_transportId, _connectionNs, {'type': 'CLOSE'});
    _send(_platformReceiver, _connectionNs, {'type': 'CLOSE'});
    await _flushAndRelease();
  }

  /// Stops the receiver app, then closes the connection.
  Future<void> stop() async {
    if (_disposed) return;
    _send(_platformReceiver, _receiverNs, {
      'type': 'STOP',
      'sessionId': sessionId,
      'requestId': _nextRequestId(),
    });
    await _flushAndRelease();
  }

  Future<void> _flushAndRelease() async {
    _end(CastChannelEnd.closedByUs);
    // Give the last frames a moment to reach the wire before closing under
    // them.
    try {
      await _socket.flush().timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    await _release();
  }

  Future<void> _release() async {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _custom.close();
    try {
      await _socket.close().timeout(const Duration(seconds: 1));
    } catch (_) {}
    _socket.destroy();
  }
}

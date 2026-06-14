import 'dart:convert';
import 'dart:typed_data';

/// The CASTV2 wire message (`cast_channel.proto`'s `CastMessage`) plus the
/// length-prefixed framing the Cast protocol uses on the TLS socket.
///
/// Hand-encoded rather than pulled from a generated protobuf: the message has
/// only a handful of fields and we never need the full descriptor, so this
/// keeps the desktop Cast sender free of a code-gen step. The encoding matches
/// what `castv2` (node) and `pychromecast` put on the wire.
///
/// Field numbers (all the real protocol uses):
///   1 protocol_version (varint, always 0 = CASTV2_1_0)
///   2 source_id        (string)
///   3 destination_id   (string)
///   4 namespace        (string)
///   5 payload_type     (varint, 0 = STRING, 1 = BINARY)
///   6 payload_utf8     (string)
///   7 payload_binary   (bytes)
class CastMessage {
  static const int payloadTypeString = 0;
  static const int payloadTypeBinary = 1;

  final int protocolVersion;
  final String sourceId;
  final String destinationId;
  final String namespace;
  final int payloadType;
  final String? payloadUtf8;
  final Uint8List? payloadBinary;

  const CastMessage({
    this.protocolVersion = 0,
    required this.sourceId,
    required this.destinationId,
    required this.namespace,
    this.payloadType = payloadTypeString,
    this.payloadUtf8,
    this.payloadBinary,
  });

  /// A STRING-payload message (the only kind the app sends — all Cast control
  /// and the Jellyfin receiver protocol are JSON strings).
  factory CastMessage.string({
    required String sourceId,
    required String destinationId,
    required String namespace,
    required String payload,
  }) =>
      CastMessage(
        sourceId: sourceId,
        destinationId: destinationId,
        namespace: namespace,
        payloadType: payloadTypeString,
        payloadUtf8: payload,
      );

  /// Serializes just the protobuf body (no length prefix).
  Uint8List encode() {
    final b = BytesBuilder(copy: false);
    _writeVarintField(b, 1, protocolVersion);
    _writeStringField(b, 2, sourceId);
    _writeStringField(b, 3, destinationId);
    _writeStringField(b, 4, namespace);
    _writeVarintField(b, 5, payloadType);
    if (payloadType == payloadTypeBinary) {
      _writeBytesField(b, 7, payloadBinary ?? Uint8List(0));
    } else {
      _writeStringField(b, 6, payloadUtf8 ?? '');
    }
    return b.toBytes();
  }

  /// Serializes the message framed for the socket: a 4-byte big-endian length
  /// prefix followed by the protobuf body.
  Uint8List frame() {
    final body = encode();
    final out = Uint8List(4 + body.length);
    ByteData.view(out.buffer).setUint32(0, body.length, Endian.big);
    out.setRange(4, out.length, body);
    return out;
  }

  /// Parses a protobuf body (no length prefix). Unknown fields are skipped so
  /// forward-compatible additions on the wire don't break decoding.
  static CastMessage decode(Uint8List data) {
    int pos = 0;
    int protocolVersion = 0;
    int payloadType = payloadTypeString;
    String sourceId = '';
    String destinationId = '';
    String namespace = '';
    String? payloadUtf8;
    Uint8List? payloadBinary;

    while (pos < data.length) {
      final tag = _readVarint(data, pos);
      pos = tag.next;
      final field = tag.value >> 3;
      final wire = tag.value & 0x7;
      switch (wire) {
        case 0: // varint
          final v = _readVarint(data, pos);
          pos = v.next;
          if (field == 1) protocolVersion = v.value;
          if (field == 5) payloadType = v.value;
          break;
        case 2: // length-delimited
          final len = _readVarint(data, pos);
          pos = len.next;
          final end = pos + len.value;
          if (end > data.length) {
            throw const FormatException('CastMessage: truncated field');
          }
          final bytes = Uint8List.sublistView(data, pos, end);
          pos = end;
          switch (field) {
            case 2:
              sourceId = utf8.decode(bytes);
              break;
            case 3:
              destinationId = utf8.decode(bytes);
              break;
            case 4:
              namespace = utf8.decode(bytes);
              break;
            case 6:
              payloadUtf8 = utf8.decode(bytes);
              break;
            case 7:
              payloadBinary = Uint8List.fromList(bytes);
              break;
          }
          break;
        case 5: // 32-bit
          pos += 4;
          break;
        case 1: // 64-bit
          pos += 8;
          break;
        default:
          throw FormatException('CastMessage: unsupported wire type $wire');
      }
    }

    return CastMessage(
      protocolVersion: protocolVersion,
      sourceId: sourceId,
      destinationId: destinationId,
      namespace: namespace,
      payloadType: payloadType,
      payloadUtf8: payloadUtf8,
      payloadBinary: payloadBinary,
    );
  }

  static void _writeVarintField(BytesBuilder b, int field, int value) {
    b.addByte((field << 3) | 0); // wire type 0
    _writeVarint(b, value);
  }

  static void _writeStringField(BytesBuilder b, int field, String value) =>
      _writeBytesField(b, field, utf8.encode(value));

  static void _writeBytesField(BytesBuilder b, int field, List<int> value) {
    b.addByte((field << 3) | 2); // wire type 2
    _writeVarint(b, value.length);
    b.add(value);
  }

  static void _writeVarint(BytesBuilder b, int value) {
    if (value < 0) throw ArgumentError('varint must be non-negative: $value');
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static _Varint _readVarint(Uint8List data, int pos) {
    int result = 0;
    int shift = 0;
    int p = pos;
    while (true) {
      if (p >= data.length) {
        throw const FormatException('CastMessage: truncated varint');
      }
      final byte = data[p++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return _Varint(result, p);
  }

  @override
  String toString() => 'CastMessage($sourceId -> $destinationId, $namespace, '
      '${payloadType == payloadTypeString ? payloadUtf8 : '<binary>'})';
}

class _Varint {
  final int value;
  final int next;
  const _Varint(this.value, this.next);
}

/// Reassembles length-prefixed [CastMessage]s from a byte stream that may
/// deliver partial frames or several frames in one chunk (TCP gives no message
/// boundaries). Feed it raw socket data; it returns whatever complete messages
/// are now available and buffers the remainder.
class CastFramer {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  List<CastMessage> addBytes(List<int> data) {
    _buffer.add(data);
    var bytes = _buffer.toBytes();
    final messages = <CastMessage>[];
    int offset = 0;
    while (bytes.length - offset >= 4) {
      final len = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset, 4)
          .getUint32(0, Endian.big);
      if (bytes.length - offset - 4 < len) break; // wait for more bytes
      final body = Uint8List.sublistView(bytes, offset + 4, offset + 4 + len);
      messages.add(CastMessage.decode(body));
      offset += 4 + len;
    }
    _buffer.clear();
    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
    return messages;
  }
}

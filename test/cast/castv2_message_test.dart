import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/wrappers/players/cast/castv2/cast_message.dart';

void main() {
  group('CastMessage encode/decode', () {
    test('round-trips a string-payload message', () {
      const message = CastMessage(
        sourceId: 'sender-0',
        destinationId: 'receiver-0',
        namespace: 'urn:x-cast:com.google.cast.tp.connection',
        payloadUtf8: '{"type":"CONNECT"}',
      );

      final decoded = CastMessage.decode(message.encode());

      expect(decoded.protocolVersion, 0);
      expect(decoded.sourceId, 'sender-0');
      expect(decoded.destinationId, 'receiver-0');
      expect(decoded.namespace, 'urn:x-cast:com.google.cast.tp.connection');
      expect(decoded.payloadType, CastMessage.payloadTypeString);
      expect(decoded.payloadUtf8, '{"type":"CONNECT"}');
    });

    test('preserves unicode in the payload', () {
      const payload = '{"name":"Wöhnzimmer 📺","emoji":"🎬"}';
      final message = CastMessage.string(
        sourceId: 'sender-0',
        destinationId: 'transport-1',
        namespace: 'urn:x-cast:com.connectsdk',
        payload: payload,
      );

      expect(CastMessage.decode(message.encode()).payloadUtf8, payload);
    });

    test('encodes the documented field tags', () {
      final message = CastMessage.string(
        sourceId: 'a',
        destinationId: 'b',
        namespace: 'n',
        payload: 'p',
      );
      final bytes = message.encode();
      // field 1 (protocol_version) varint 0 → tag 0x08, value 0x00
      expect(bytes[0], 0x08);
      expect(bytes[1], 0x00);
      // field 2 (source_id) string → tag 0x12, len 1, 'a'
      expect(bytes[2], 0x12);
      expect(bytes[3], 0x01);
      expect(bytes[4], 'a'.codeUnitAt(0));
    });

    test('skips unknown fields without failing', () {
      // Hand-build a message with an extra varint field 9 and a 32-bit field 10
      // interleaved, then ensure the known fields still decode.
      final b = BytesBuilder();
      // field 1 varint 0
      b.add([0x08, 0x00]);
      // unknown field 9 varint (tag = 9<<3 = 0x48), value 300 (needs 2 bytes)
      b.add([0x48, 0xAC, 0x02]);
      // field 4 namespace 'n'
      b.add([0x22, 0x01, 'n'.codeUnitAt(0)]);
      // unknown field 10 32-bit (tag = (10<<3)|5 = 0x55) + 4 bytes
      b.add([0x55, 0xDE, 0xAD, 0xBE, 0xEF]);
      // field 5 payload_type 0
      b.add([0x28, 0x00]);
      // field 6 payload 'p'
      b.add([0x32, 0x01, 'p'.codeUnitAt(0)]);

      final decoded = CastMessage.decode(b.toBytes());
      expect(decoded.namespace, 'n');
      expect(decoded.payloadUtf8, 'p');
    });

    test('frame() prepends a big-endian length', () {
      final message = CastMessage.string(
        sourceId: 's',
        destinationId: 'd',
        namespace: 'n',
        payload: 'hello',
      );
      final framed = message.frame();
      final body = message.encode();
      final len = ByteData.view(framed.buffer).getUint32(0, Endian.big);
      expect(len, body.length);
      expect(framed.sublist(4), body);
    });
  });

  group('CastFramer', () {
    Uint8List frameOf(String payload) => CastMessage.string(
          sourceId: 's',
          destinationId: 'd',
          namespace: 'n',
          payload: payload,
        ).frame();

    test('emits a single complete frame', () {
      final framer = CastFramer();
      final messages = framer.addBytes(frameOf('one'));
      expect(messages, hasLength(1));
      expect(messages.first.payloadUtf8, 'one');
    });

    test('reassembles a frame split across two chunks', () {
      final framer = CastFramer();
      final framed = frameOf('split me');
      final cut = framed.length ~/ 2;

      expect(framer.addBytes(framed.sublist(0, cut)), isEmpty);
      final messages = framer.addBytes(framed.sublist(cut));
      expect(messages, hasLength(1));
      expect(messages.first.payloadUtf8, 'split me');
    });

    test('splits two frames delivered in one chunk', () {
      final framer = CastFramer();
      final combined = <int>[...frameOf('first'), ...frameOf('second')];
      final messages = framer.addBytes(combined);
      expect(messages.map((m) => m.payloadUtf8), ['first', 'second']);
    });

    test('handles a frame split mid length-prefix', () {
      final framer = CastFramer();
      final framed = frameOf('x');
      // Feed only 2 of the 4 length bytes first.
      expect(framer.addBytes(framed.sublist(0, 2)), isEmpty);
      final messages = framer.addBytes(framed.sublist(2));
      expect(messages.single.payloadUtf8, 'x');
    });

    test('keeps trailing partial bytes buffered for the next frame', () {
      final framer = CastFramer();
      final a = frameOf('alpha');
      final b = frameOf('beta');
      // First frame plus 3 bytes of the second.
      final first = framer.addBytes([...a, ...b.sublist(0, 3)]);
      expect(first.single.payloadUtf8, 'alpha');
      final second = framer.addBytes(b.sublist(3));
      expect(second.single.payloadUtf8, 'beta');
    });

    test('round-trips a large payload (multi-byte varint length)', () {
      final framer = CastFramer();
      final big = jsonEncode({'data': 'q' * 5000});
      final messages = framer.addBytes(frameOf(big));
      expect(messages.single.payloadUtf8, big);
    });
  });
}

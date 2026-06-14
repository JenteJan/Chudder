import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/wrappers/players/cast/castv2/cast_protocol.dart';

void main() {
  group('payload builders', () {
    test('launch carries appId and requestId', () {
      final json = jsonDecode(CastProtocol.launch('F007D354', 7));
      expect(json['type'], 'LAUNCH');
      expect(json['appId'], 'F007D354');
      expect(json['requestId'], 7);
    });

    test('setVolume clamps to 0..1 and nests under volume.level', () {
      expect(jsonDecode(CastProtocol.setVolume(1.5, 1))['volume']['level'], 1.0);
      expect(jsonDecode(CastProtocol.setVolume(-0.2, 1))['volume']['level'], 0.0);
      expect(jsonDecode(CastProtocol.setVolume(0.4, 1))['volume']['level'], 0.4);
    });

    test('load uses seconds for currentTime and builds the media object', () {
      final json = jsonDecode(CastProtocol.load(
        contentId: 'http://10.0.0.2:54321/stream?t=1',
        contentType: 'video/mp4',
        requestId: 3,
        currentTime: const Duration(seconds: 90),
      ));
      expect(json['type'], 'LOAD');
      expect(json['autoplay'], true);
      expect(json['currentTime'], 90.0);
      expect(json['media']['contentId'], 'http://10.0.0.2:54321/stream?t=1');
      expect(json['media']['contentType'], 'video/mp4');
      expect(json['media']['streamType'], 'BUFFERED');
    });

    test('seek converts to fractional seconds', () {
      final json = jsonDecode(CastProtocol.seek(12, const Duration(milliseconds: 1500), 4));
      expect(json['type'], 'SEEK');
      expect(json['mediaSessionId'], 12);
      expect(json['currentTime'], 1.5);
    });

    test('messageType extracts the type, tolerating junk', () {
      expect(CastProtocol.messageType('{"type":"PONG"}'), 'PONG');
      expect(CastProtocol.messageType('{"requestId":1}'), '');
      expect(CastProtocol.messageType('[]'), '');
    });
  });

  group('ReceiverStatus.parse', () {
    test('finds the transport id for a launched app', () {
      const json = '''
      {"requestId":1,"type":"RECEIVER_STATUS","status":{
        "applications":[{
          "appId":"F007D354","displayName":"Jellyfin",
          "transportId":"web-5","sessionId":"sess-9",
          "namespaces":[{"name":"urn:x-cast:com.connectsdk"}]
        }],
        "volume":{"level":0.35,"muted":false}
      }}''';
      final status = ReceiverStatus.parse(json);
      expect(status.transportFor('F007D354'), 'web-5');
      expect(status.transportFor('CC1AD845'), isNull);
      expect(status.volumeLevel, 0.35);
      expect(status.muted, false);
      expect(status.applications.single.namespaces, contains('urn:x-cast:com.connectsdk'));
    });

    test('handles an idle receiver with no applications', () {
      const json = '{"type":"RECEIVER_STATUS","status":{"volume":{"level":0.5}}}';
      final status = ReceiverStatus.parse(json);
      expect(status.applications, isEmpty);
      expect(status.transportFor('F007D354'), isNull);
      expect(status.volumeLevel, 0.5);
    });

    test('survives a malformed status block', () {
      expect(ReceiverStatus.parse('{"status":42}').applications, isEmpty);
      expect(ReceiverStatus.parse('"nope"').applications, isEmpty);
    });
  });

  group('MediaStatus.parse', () {
    test('reads player state and position (seconds → Duration)', () {
      const json = '''
      {"type":"MEDIA_STATUS","status":[{
        "mediaSessionId":3,"playerState":"PLAYING","currentTime":149.31
      }]}''';
      final status = MediaStatus.parse(json)!;
      expect(status.mediaSessionId, 3);
      expect(status.isPlaying, true);
      expect(status.currentTime, const Duration(milliseconds: 149310));
    });

    test('returns null for an empty status list', () {
      expect(MediaStatus.parse('{"type":"MEDIA_STATUS","status":[]}'), isNull);
    });
  });
}

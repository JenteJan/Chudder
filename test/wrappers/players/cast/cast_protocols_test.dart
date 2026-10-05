import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/wrappers/players/cast/desktop/castv2_channel.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/dlna_player.dart';

void main() {
  group('receiver subtitle look', () {
    test('the default look is white, outlined, on no background', () {
      expect(receiverSubtitleAppearance(const SubtitleSettingsModel()), {
        'textColor': '#FFFFFF',
        'dropShadow': 'OUTLINE',
        'textBackground': 'transparent',
      });
    });

    test('sizes fall into the receiver\'s buckets', () {
      String? size(double fontSize) =>
          receiverSubtitleAppearance(const SubtitleSettingsModel().copyWith(fontSize: fontSize))['textSize'];
      expect(size(30), 'smaller');
      expect(size(50), 'small');
      expect(size(60), isNull);
      expect(size(70), 'large');
      expect(size(80), 'larger');
      expect(size(100), 'extralarge');
    });

    test('a shadow without an outline, and a solid background', () {
      final look = receiverSubtitleAppearance(const SubtitleSettingsModel().copyWith(
        outlineSize: 0,
        shadow: 0.5,
        color: const Color(0xFFFFEE00),
        backGroundColor: const Color(0xCC000000),
      ));
      expect(look['dropShadow'], 'DROP_SHADOW');
      expect(look['textColor'], '#FFEE00');
      expect(look.containsKey('textBackground'), isFalse);
    });
  });

  group('receiver reports', () {
    test('errors carry their message', () {
      final report = parseReceiverMessage('{"type":"playbackerror","message":"NoCompatibleStream"}')!;
      expect(report.isError, isTrue);
      expect(report.message, 'NoCompatibleStream');
    });

    test('progress is not an error', () {
      expect(parseReceiverMessage('{"type":"playbackprogress","data":{}}')!.isError, isFalse);
    });
  });

  group('CASTV2', () {
    test('frames survive the codec, several in one chunk', () {
      final bytes = [
        ...encodeCastFrameForTest('urn:x-cast:com.connectsdk', '{"command":"Identify"}'),
        ...encodeCastFrameForTest('urn:x-cast:com.google.cast.tp.heartbeat', '{"type":"PING"}'),
      ];
      expect(decodeCastFramesForTest(Uint8List.fromList(bytes)), [
        ('urn:x-cast:com.connectsdk', '{"command":"Identify"}'),
        ('urn:x-cast:com.google.cast.tp.heartbeat', '{"type":"PING"}'),
      ]);
    });

    test('our session is gone when the device is idle or runs something else', () {
      Map<String, dynamic> status(List<Map<String, dynamic>>? applications) => {
            'type': 'RECEIVER_STATUS',
            'status': {
              'volume': {'level': 0.5},
              if (applications != null) 'applications': applications,
            },
          };
      expect(receiverStatusShowsSessionGone(status([{'sessionId': 'ours'}]), 'ours'), isFalse);
      expect(receiverStatusShowsSessionGone(status([{'sessionId': 'theirs'}]), 'ours'), isTrue);
      // The idle screen: no applications at all.
      expect(receiverStatusShowsSessionGone(status(null), 'ours'), isTrue);
      expect(receiverStatusShowsSessionGone({'type': 'RECEIVER_STATUS'}, 'ours'), isFalse);
    });
  });

  group('DLNA metadata', () {
    test('offers a subtitle every way renderers look for one', () {
      final didl = DlnaPlayer.didlMetadata(
        'http://10.0.0.2:8080/media.mkv',
        'video/x-matroska',
        subtitleUrl: 'http://10.0.0.2:8080/sub.srt',
        title: 'Tom & Jerry',
      );
      expect(didl, contains('<sec:CaptionInfoEx sec:type="srt">http://10.0.0.2:8080/sub.srt</sec:CaptionInfoEx>'));
      expect(didl, contains('pv:subtitleFileUri="http://10.0.0.2:8080/sub.srt"'));
      expect(didl, contains('protocolInfo="http-get:*:text/srt:*"'));
      expect(didl, contains('protocolInfo="http-get:*:smi/caption:*"'));
      expect(didl, contains('<dc:title>Tom &amp; Jerry</dc:title>'));
      // The video stays the first resource: renderers play the first they can.
      final firstResource = didl.substring(didl.indexOf('<res'), didl.indexOf('</res>'));
      expect(firstResource, contains('media.mkv'));
    });

    test('says nothing about subtitles when there are none', () {
      final didl = DlnaPlayer.didlMetadata('http://10.0.0.2:8080/media.mp4', 'video/mp4');
      expect(didl, isNot(contains('srt')));
      expect(didl, isNot(contains('subtitleFileUri')));
    });
  });
}

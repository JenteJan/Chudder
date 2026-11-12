import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/screens/video_player/components/media_info_tag.dart';
import 'package:chudder/wrappers/players/windows_hdr.dart';

MediaStreamsModel _streams({required bool hdr}) => MediaStreamsModel(
      versionStreams: [
        VersionStreamModel(
          name: 'main',
          index: 0,
          id: 'source',
          defaultAudioStreamIndex: null,
          defaultSubStreamIndex: null,
          videoStreams: [
            VideoStreamModel(
              name: 'video',
              codec: 'hevc',
              isDefault: true,
              isExternal: false,
              index: 0,
              width: 3840,
              height: 2160,
              frameRate: 24,
              bitRate: null,
              videoDoViTitle: null,
              videoRangeType: hdr ? VideoRangeType.hdr10 : VideoRangeType.sdr,
            ),
          ],
          audioStreams: const [],
          subStreams: const [],
        ),
      ],
    );

void main() {
  tearDown(() => WindowsHdr.active.value = false);

  Widget host(MediaStreamsModel streams) =>
      MaterialApp(home: Scaffold(body: Center(child: MediaInfoTag(streams: streams))));

  testWidgets('an HDR file shown in SDR reads plainly', (tester) async {
    await tester.pumpWidget(host(_streams(hdr: true)));
    expect(find.text(_streams(hdr: true).mediaInfoTag!), findsOneWidget);
    expect(find.byKey(const Key('hdr-rainbow')), findsNothing);
  });

  testWidgets('shown in HDR, the format turns rainbow and back', (tester) async {
    final streams = _streams(hdr: true);
    await tester.pumpWidget(host(streams));
    WindowsHdr.active.value = true;
    await tester.pump();
    expect(find.byKey(const Key('hdr-rainbow')), findsOneWidget);
    expect(find.text(streams.displayProfile!.value), findsOneWidget);
    expect(find.text(' ${streams.resolution!.value}'), findsOneWidget);

    WindowsHdr.active.value = false;
    await tester.pump();
    expect(find.byKey(const Key('hdr-rainbow')), findsNothing);
    expect(find.text(streams.mediaInfoTag!), findsOneWidget);
  });

  testWidgets('an SDR file never turns rainbow', (tester) async {
    WindowsHdr.active.value = true;
    await tester.pumpWidget(host(_streams(hdr: false)));
    expect(find.byKey(const Key('hdr-rainbow')), findsNothing);
  });

  testWidgets('takes no focus, so remote navigation passes it by', (tester) async {
    WindowsHdr.active.value = true;
    await tester.pumpWidget(host(_streams(hdr: true)));
    expect(find.descendant(of: find.byType(MediaInfoTag), matching: find.byType(Focus)), findsNothing);
  });
}

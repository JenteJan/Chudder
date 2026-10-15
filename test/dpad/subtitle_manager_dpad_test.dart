import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_item.dart';
import 'package:chudder/screens/subtitles/subtitle_track_actions.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

MediaStream _sub(int index, String language, {String? path}) => MediaStream(
      index: index,
      type: MediaStreamType.subtitle,
      language: language,
      displayTitle: '${language.toUpperCase()} - SUBRIP',
      codec: 'subrip',
      isExternal: path != null,
      path: path,
    );

final _lookup = SubtitleLookup(
  item: SubtitleItem(
    itemId: 'film',
    title: 'A film',
    isEpisode: false,
    mediaSource: MediaSourceInfo(
      id: 'source',
      mediaStreams: [
        _sub(2, 'eng'),
        _sub(3, 'eng', path: '/films/A film.en.srt'),
        _sub(4, 'dut', path: '/films/A film.nl.srt'),
      ],
    ),
  ),
);

void main() {
  Future<void> open(WidgetTester tester) => openDpad(
        tester,
        (context) => showSubtitleManager(context, itemId: 'film', itemName: 'A film'),
        overrides: [
          ...playerFakes,
          subtitleItemProvider.overrideWith((ref, key) async => _lookup),
        ],
      );

  testWidgets('the subtitle manager: every file and button by remote', (tester) async {
    await open(tester);
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(Dialog));
    walk.expectAllReachable(within: find.byType(Dialog));
  });

  testWidgets('select on a file lists what can be done with it', (tester) async {
    await open(tester);
    final row = find.ancestor(of: find.text('A film.nl.srt'), matching: find.byType(ListTile));
    focusNodeIn(row).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final actions = find.byType(SimpleDialog);
    expect(find.descendant(of: actions, matching: find.text('Remove')), findsOneWidget);
    expect(find.descendant(of: actions, matching: find.text('Replace with a better one')), findsOneWidget);
    expect(find.descendant(of: actions, matching: find.text('Shift timing…')), findsOneWidget);
    // It opens with its first entry selected, not on nothing, and every
    // entry is a press away.
    final walk = await walkDpad(tester);
    walk.expectStartsInside(actions);
    walk.expectAllReachable(within: actions);
  });
}

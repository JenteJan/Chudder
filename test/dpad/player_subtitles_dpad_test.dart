import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/subtitles/subtitle_cues.dart';
import 'package:chudder/models/subtitles/subtitle_line_match.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_timing_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/subtitle_fixes.dart';
import 'package:chudder/screens/video_player/components/track_option_row.dart';
import 'package:chudder/screens/video_player/components/video_player_options_sheet.dart';

import 'package:chudder/util/focus_provider.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

SubStreamModel _sub(int index, String language, {bool external = false}) => SubStreamModel(
      name: language,
      id: '$index',
      title: language,
      displayTitle: '${language.toUpperCase()} - SUBRIP${external ? ' - External' : ''}',
      language: language,
      codec: 'subrip',
      isDefault: false,
      isExternal: external,
      index: index,
      path: external ? '/films/film.$language.srt' : null,
    );

MediaStreamsModel get _streams => MediaStreamsModel(
      defaultAudioStreamIndex: 1,
      defaultSubStreamIndex: 3,
      versionStreams: [
        VersionStreamModel(
          name: 'main',
          index: 0,
          id: 'source',
          defaultAudioStreamIndex: 1,
          defaultSubStreamIndex: 3,
          videoStreams: const [],
          audioStreams: const [],
          subStreams: [_sub(2, 'eng'), _sub(3, 'eng', external: true), _sub(4, 'dut', external: true)],
        ),
      ],
    );

PlaybackModel get _playing {
  final streams = _streams;
  return DirectPlaybackModel(
    item: MovieModel(
      originalTitle: 'Film',
      premiereDate: DateTime(2019),
      sortName: 'Film',
      status: '',
      name: 'Film',
      id: 'film',
      overview: const OverviewModel(),
      userData: const UserData(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      parentImages: null,
      mediaStreams: streams,
      canDownload: null,
      canDelete: null,
    ),
    media: const Media(url: 'film'),
    mediaStreams: streams,
  );
}

/// The timing as a test sets it: on a player that moves subtitles itself.
class _Timing extends SubtitleTimingNotifier {
  _Timing(super.ref, SubtitleTiming initial) {
    state = initial;
  }

  @override
  SubtitleTimingMode get mode => SubtitleTimingMode.player;

  @override
  bool get canMatchLine => true;
}

final _cues = SubtitleCueList([
  for (var i = 0; i < 8; i++)
    SubtitleCue(Duration(seconds: 10 + i * 3), Duration(seconds: 12 + i * 3), 'Line number $i of the film'),
]);

List<Override> _overrides(SubtitleTiming timing) => [
      ...playerFakes,
      playBackModel.overrideWith((ref) => _playing),
      subtitleTimingProvider.overrideWith((ref) => _Timing(ref, timing)),
    ];

/// The bar the way the player holds it: over a player that has the focus.
Widget get _overPlayer => const Stack(
      children: [
        Focus(autofocus: true, child: SizedBox.expand()),
        SubtitleTimingBar(controlsVisible: true),
      ],
    );

void main() {
  testWidgets('the subtitle picker: every track, its menu and the extras by remote', (tester) async {
    await openDpad(tester, (context) => showSubSelection(context), overrides: _overrides(const SubtitleTiming()));
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SimpleDialog));
    walk.expectAllReachable(within: find.byType(SimpleDialog));

    // Right from a track is its own menu, and left goes back to it.
    var checked = 0;
    for (final row in find.byType(TrackOptionRow).evaluate().toList()) {
      final widget = row.widget as TrackOptionRow;
      if (widget.menu == null) continue;
      final rowFinder = find.byWidget(widget);
      final button = find.descendant(of: rowFinder, matching: find.byType(FocusButton));
      final menu = find.descendant(of: rowFinder, matching: find.byType(PopupMenuButton<String>));
      await expectPress(tester, from: button, key: LogicalKeyboardKey.arrowRight, to: menu);
      await expectPress(tester, from: menu, key: LogicalKeyboardKey.arrowLeft, to: button);
      checked++;
    }
    expect(checked, 3, reason: 'every track here has something to do with it');
  });

  testWidgets('holding OK on a track opens its menu, as a second way to it', (tester) async {
    await openDpad(tester, (context) => showSubSelection(context), overrides: _overrides(const SubtitleTiming()));
    final row = find.byWidgetPredicate((widget) => widget is TrackOptionRow && widget.menu != null).first;
    focusNodeIn(find.descendant(of: row, matching: find.byType(FocusButton)).first).requestFocus();
    await tester.pump();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
  });

  testWidgets('the options sheet: every row by remote', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await openDpad(
      tester,
      (context) => showDialog(
        context: context,
        builder: (context) => Dialog(child: VideoOptions(controller: ScrollController(), minimizePlayer: () {})),
      ),
      overrides: [
        ..._overrides(const SubtitleTiming()),
        // The walk slides the brightness, which is stored.
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(VideoOptions));
    expect(find.byType(OptionRow), findsWidgets);
  });

  testWidgets('the timing bar opened from the menu takes the remote', (tester) async {
    await pumpDpad(
      tester,
      child: _overPlayer,
      overrides: _overrides(const SubtitleTiming(open: true, pinned: true, delay: Duration(milliseconds: 500))),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SubtitleTimingBar));
    walk.expectAllReachable(within: find.byType(SubtitleTimingBar));
  });

  testWidgets('finding the line: the search and every nearby line by remote', (tester) async {
    await pumpDpad(
      tester,
      child: _overPlayer,
      overrides: _overrides(SubtitleTiming(
        open: true,
        pinned: true,
        match: SubtitleLineMatch(heardAt: const Duration(seconds: 25), wasPlaying: true, cues: _cues),
      )),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SubtitleTimingBar));
    walk.expectAllReachable(within: find.byType(SubtitleTimingBar));
  });

  testWidgets('tapping the line: Now has the remote, and the rest is reachable', (tester) async {
    final picked = SubtitleLineCandidate(cue: _cues.cues[3], score: 1, delay: Duration.zero);
    await pumpDpad(
      tester,
      child: _overPlayer,
      overrides: _overrides(SubtitleTiming(
        open: true,
        pinned: true,
        match:
            SubtitleLineMatch(heardAt: const Duration(seconds: 25), wasPlaying: true, cues: _cues).withPicked(picked),
      )),
    );
    final now = find.widgetWithText(FilledButton, 'Now');
    expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FilledButton>(), tester.widget(now));
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(SubtitleTimingBar));
    // Back steps out of tapping, to the list of lines.
    focusNodeIn(now).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/release_info.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/screens/subtitles/subtitle_finder_view.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

import 'dpad_walk.dart';

SubtitleMatch _match(String key, MatchVerdict verdict) => SubtitleMatch(
      candidate: SubtitleCandidate(
        key: key,
        source: SubtitleSourceKind.jellyfin,
        provider: 'OpenSubtitles',
        language: 'eng',
        payload: key,
        releaseName: 'Film.2019.1080p.BluRay.x264-$key',
      ),
      percent: 80,
      verdict: verdict,
      matched: const {},
      mismatched: const {},
      release: const ReleaseInfo(),
    );

Widget _finder({List<SubtitleMatch>? matches}) => SubtitleFinderView(
      itemName: 'A film',
      languages: const [FinderLanguage('eng', 'English'), FinderLanguage('dut', 'Dutch')],
      language: 'eng',
      results: LanguageResults(
        matches: matches ??
            [
              _match('a', MatchVerdict.exact),
              _match('b', MatchVerdict.likely),
              _match('c', MatchVerdict.unknown),
              _match('d', MatchVerdict.unlikely),
            ],
        jellyfin: SourceStatus.done,
      ),
      onLanguage: (_) {},
      onUse: (_) {},
      onClose: () {},
      onMoreLanguages: () {},
      onHearingImpaired: (_) {},
      onRetry: () {},
    );

void main() {
  testWidgets('the subtitle finder: every result, chip and button by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => Dialog(child: _finder())),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SubtitleFinderView));
    walk.expectAllReachable(within: find.byType(SubtitleFinderView));
  });

  testWidgets('down from the languages is the first result, and the results follow in order', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => Dialog(child: _finder())),
    );
    final cards = find.descendant(of: find.byType(SubtitleFinderView), matching: find.byType(FocusButton));
    await expectPress(tester,
        from: find.widgetWithText(ChoiceChip, 'English'), key: LogicalKeyboardKey.arrowDown, to: cards.at(0));
    await expectPress(tester, from: cards.at(0), key: LogicalKeyboardKey.arrowDown, to: cards.at(1));
    await expectPress(tester, from: cards.at(1), key: LogicalKeyboardKey.arrowUp, to: cards.at(0));
  });

  testWidgets('the subtitle finder with nothing found: retry by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => Dialog(child: _finder(matches: const []))),
    );
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(SubtitleFinderView));
  });
}

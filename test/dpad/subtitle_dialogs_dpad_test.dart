import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_file_actions.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/screens/subtitles/subtitle_track_actions.dart';
import 'package:chudder/screens/video_player/components/subtitle_fixes.dart';
import 'package:chudder/screens/video_player/components/video_subtitle_controls.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

/// A removal the server allows and Bazarr can also block.
class _Actions extends SubtitleFileActions {
  _Actions(super.ref);

  @override
  Future<SubtitleRemoval> plan({
    required String itemId,
    String? mediaSourceId,
    required int index,
    String? path,
  }) async =>
      SubtitleRemoval(itemId: itemId, index: index, path: path, jellyfinCanDelete: true);
}

Future<List<Override>> _withSettings() async {
  SharedPreferences.setMockInitialValues({});
  return [sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()), ...playerFakes];
}

void main() {
  testWidgets('shifting a file\'s timing: the amount and both buttons by remote', (tester) async {
    await openDpad(tester, (context) => askShift(context), overrides: playerFakes);
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(AlertDialog));
    walk.expectAllReachable(within: find.byType(AlertDialog));
  });

  testWidgets('the frame-rate fix: every rate and both buttons by remote', (tester) async {
    await openDpad(tester, (context) => askFrameRate(context, videoRate: 23.976), overrides: playerFakes);
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(AlertDialog));
    walk.expectAllReachable(within: find.byType(AlertDialog));
  });

  testWidgets('picking a language: the search and the languages by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(
        context: context,
        builder: (_) => const LanguagePicker(cultures: [
          CultureDto(displayName: 'English', twoLetterISOLanguageName: 'en', threeLetterISOLanguageName: 'eng'),
          CultureDto(displayName: 'Dutch', twoLetterISOLanguageName: 'nl', threeLetterISOLanguageName: 'dut'),
          CultureDto(displayName: 'French', twoLetterISOLanguageName: 'fr', threeLetterISOLanguageName: 'fre'),
        ]),
      ),
      overrides: await _withSettings(),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(LanguagePicker));
    walk.expectAllReachable(within: find.byType(LanguagePicker));
  });

  testWidgets('removing a file: cancel and remove by remote', (tester) async {
    await openDpad(
      tester,
      (context) => confirmRemoveSubtitle(
        context,
        context as WidgetRef,
        itemId: 'film',
        index: 3,
        path: '/films/film.en.srt',
        label: 'film.en.srt',
      ),
      overrides: [...playerFakes, subtitleFileActionsProvider.overrideWith((ref) => _Actions(ref))],
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(AlertDialog));
    walk.expectAllReachable(within: find.byType(AlertDialog));
  });

  testWidgets('the subtitle style: every slider and button by remote', (tester) async {
    await openDpad(tester, (context) => showSubtitleControls(context: context), overrides: await _withSettings());
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(VideoSubtitleControls));
    walk.expectAllReachable(within: find.byType(VideoSubtitleControls));
  });
}

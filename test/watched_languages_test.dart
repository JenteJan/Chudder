import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/watched_languages_provider.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/util/settings_transfer.dart';

import 'dpad/dpad_fakes.dart';
import 'dpad/dpad_walk.dart';

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
  ]);
  addTearDown(container.dispose);
  return container;
}

int _today() => DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('what is played most comes first, and it is kept', () async {
    final languages = (await _container()).read(watchedLanguagesProvider);
    languages.note({'ja': 3, 'en': 2});
    languages.note({'ja': 3, 'fr': 1});
    expect(languages.likely(), ['ja', 'en', 'fr']);

    final again = (await _container()).read(watchedLanguagesProvider);
    expect(again.likely(max: 2), ['ja', 'en']);
  });

  test('an old favourite fades behind what is played now', () async {
    SharedPreferences.setMockInitialValues({
      watchedLanguagesKey: jsonEncode({
        'de': [10, _today() - 365],
        'ja': [3, _today()],
      }),
    });
    final languages = (await _container()).read(watchedLanguagesProvider);
    expect(languages.likely(), ['ja', 'de']);
  });

  test('the tally stays small', () async {
    final languages = (await _container()).read(watchedLanguagesProvider);
    languages.note({for (var i = 0; i < 60; i++) 'l$i': i.toDouble() + 1});
    final stored = jsonDecode((await SharedPreferences.getInstance()).getString(watchedLanguagesKey)!) as Map;
    expect(stored.length, WatchedLanguages.maxLanguages);
    expect(languages.likely(max: 1), ['l59']);
  });

  test('it travels with the settings export, as do the collection queues', () {
    expect(SettingsSection.values.map((section) => section.key), contains(watchedLanguagesKey));
    expect(SettingsSection.values.map((section) => section.name), contains('collectionQueues'));
  });

  testWidgets('the language picker puts the likely languages first', (tester) async {
    SharedPreferences.setMockInitialValues({
      watchedLanguagesKey: jsonEncode({
        'ja': [5, _today()],
      }),
    });
    const cultures = [
      CultureDto(
          name: 'English', displayName: 'English', twoLetterISOLanguageName: 'en', threeLetterISOLanguageName: 'eng'),
      CultureDto(
          name: 'French', displayName: 'French', twoLetterISOLanguageName: 'fr', threeLetterISOLanguageName: 'fre'),
      CultureDto(
          name: 'Japanese', displayName: 'Japanese', twoLetterISOLanguageName: 'ja', threeLetterISOLanguageName: 'jpn'),
    ];
    await openDpad(
      tester,
      (context) => showDialog(context: context, builder: (_) => const LanguagePicker(cultures: cultures)),
      overrides: [
        ...playerFakes,
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    expect(find.text('Likely'), findsOneWidget);
    final likelyTop = tester.getTopLeft(find.text('Japanese').first).dy;
    expect(likelyTop, lessThan(tester.getTopLeft(find.text('All languages')).dy));
    expect(likelyTop, lessThan(tester.getTopLeft(find.text('English').first).dy));

    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(LanguagePicker));
  });
}

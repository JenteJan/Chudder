import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/settings_search.dart';
import 'package:fladder/screens/settings/widgets/settings_label_divider.dart';
import 'package:fladder/screens/settings/widgets/settings_list_group.dart';

void main() {
  group('settingsMatchScore', () {
    test('matches a plain substring', () {
      expect(settingsMatchScore('scaling', 'Video scaling', ''), isNotNull);
    });

    test('is case insensitive', () {
      expect(settingsMatchScore('VIDEO', 'Video scaling', ''), isNotNull);
    });

    test('matches a fuzzy subsequence', () {
      expect(settingsMatchScore('vidscal', 'Video scaling', ''), isNotNull);
      expect(settingsMatchScore('ambblur', 'Ambient blur', ''), isNotNull);
    });

    test('rejects a query with characters the row does not contain', () {
      expect(settingsMatchScore('audio', 'Video scaling', ''), isNull);
    });

    test('requires every word of a multi word query to match', () {
      expect(settingsMatchScore('video scaling', 'Video scaling', ''), isNotNull);
      expect(settingsMatchScore('video audio', 'Video scaling', ''), isNull);
    });

    test('matches against the surrounding text as well as the title', () {
      expect(settingsMatchScore('subtitle', 'Language', 'Preferred subtitle language'), isNotNull);
    });

    test('ranks a title match above a description-only match', () {
      final title = settingsMatchScore('subtitles', 'Subtitles', 'Off')!;
      final description = settingsMatchScore('subtitles', 'Language', 'Preferred subtitles language')!;
      expect(title, greaterThan(description));
    });

    test('ranks a word-start match above a mid-word match', () {
      final wordStart = settingsMatchScore('scale', 'Video scale', '')!;
      final midWord = settingsMatchScore('scale', 'Downscaled', '')!;
      expect(wordStart, greaterThan(midWord));
    });

    test('scores nothing for an empty query', () {
      expect(settingsMatchScore('   ', 'Video scaling', ''), isNull);
    });
  });

  group('settingsRowText', () {
    late BuildContext capturedContext;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        }),
      ));
    }

    testWidgets('reads the label and sub label of a tile, title first', (tester) async {
      await pump(tester);
      final texts = settingsRowText(
        capturedContext,
        const SettingsListTile(
          label: Text('Video scaling'),
          subLabel: Text('How video fills the screen'),
        ),
      );
      expect(texts, ['Video scaling', 'How video fills the screen']);
    });

    testWidgets('reads a checkbox tile', (tester) async {
      await pump(tester);
      final texts = settingsRowText(
        capturedContext,
        const SettingsListTileCheckbox(
          label: Text('Ambient blur'),
          subLabel: Text('Blur behind the video'),
          value: true,
        ),
      );
      expect(texts, ['Ambient blur', 'Blur behind the video']);
    });

    testWidgets('reads an enum tile including its current value', (tester) async {
      await pump(tester);
      final texts = settingsRowText(
        capturedContext,
        SettingsListTileEnum(
          label: const Text('Home streaming quality'),
          current: 'Original',
          itemBuilder: (context) => const [],
        ),
      );
      expect(texts, ['Home streaming quality', 'Original']);
    });

    testWidgets('unwraps the group styling the settings pages apply', (tester) async {
      await pump(tester);
      final items = settingsListGroup(
        capturedContext,
        const SettingsLabelDivider(label: 'Video'),
        const [SettingsListTile(label: Text('Video scaling'))],
      );
      // First entry is the section heading, the rest are wrapped rows.
      expect(settingsRowText(capturedContext, items.last), ['Video scaling']);
    });

    testWidgets('descends through the layout widgets rows are nested in', (tester) async {
      await pump(tester);
      final texts = settingsRowText(
        capturedContext,
        const Column(
          children: [
            Padding(
              padding: EdgeInsets.zero,
              child: SettingsListTile(label: Text('Fill screen')),
            ),
          ],
        ),
      );
      expect(texts, ['Fill screen']);
    });

    testWidgets('runs Builder rows so their labels are still found', (tester) async {
      await pump(tester);
      final texts = settingsRowText(
        capturedContext,
        Builder(builder: (context) => const SettingsListTile(label: Text('Subtitle language'))),
      );
      expect(texts, ['Subtitle language']);
    });

    testWidgets('returns nothing for a row with no readable text', (tester) async {
      await pump(tester);
      expect(settingsRowText(capturedContext, const SizedBox(height: 12)), isEmpty);
    });
  });
}

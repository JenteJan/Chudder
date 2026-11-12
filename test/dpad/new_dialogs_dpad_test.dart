// The dialogs added in the October requests round, by remote.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/playback_queue_state.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/related_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/models/boxset_model.dart';
import 'package:chudder/providers/collections_provider.dart';
import 'package:chudder/screens/collections/add_to_collection.dart';
import 'package:chudder/screens/collections/collection_add_titles.dart';
import 'package:chudder/screens/collections/open_containing_collection.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/screens/collections/collection_pick_bar.dart';
import 'package:chudder/screens/settings/client_sections/client_settings_backup.dart';
import 'package:chudder/screens/settings/language_preferences_dialog.dart';
import 'package:chudder/screens/video_player/components/remember_languages_prompt.dart';
import 'package:chudder/screens/video_player/components/video_player_queue.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/settings_transfer.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

ItemBaseModel _item(String id) => ItemBaseModel(
      name: 'Title $id',
      id: id,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDownload: null,
      canDelete: null,
      jellyType: null,
    );

class _Related extends RelatedNotifier {
  _Related(Ref ref) : super(ref: ref);

  @override
  Future<Response<List<ItemBaseModel>>> relatedContent(String itemId) async =>
      Response(http.Response('', 200), [for (var i = 0; i < 4; i++) _item('similar-$i')]);
}

BoxSetModel _boxSet(String id) => BoxSetModel(
      name: 'Collection $id',
      id: id,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDelete: null,
      canDownload: null,
    );

/// Collections as the server would answer: the items are in the first.
class _Collections extends BoxSetNotifier {
  _Collections(super.ref);

  @override
  Future<void> setItems(List<ItemBaseModel> items) async {
    state = state.copyWith(
      items: items,
      isLoading: false,
      collections: {_boxSet('in'): true, _boxSet('out'): false},
    );
  }
}

Future<List<Override>> _preferences(LanguagePreferences preferences) async {
  SharedPreferences.setMockInitialValues({languagePreferencesKey: preferences.toJson()});
  return [
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
    ...playerFakes,
  ];
}

void main() {
  testWidgets('remembering languages: both answers and the box by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(
        context: context,
        builder: (_) => RememberLanguagesDialog(
          scope: const LanguageScope(id: 'show', name: 'A show', kind: LanguageScopeKind.series),
          languages: (audio: 'ja', subtitle: 'en', subtitlesOff: false),
          onAnswer: (_, _, _) {},
        ),
      ),
      overrides: await _preferences(const LanguagePreferences()),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(RememberLanguagesDialog));
    walk.expectAllReachable(within: find.byType(RememberLanguagesDialog));
  });

  testWidgets('remembering languages: a language is changed before answering', (tester) async {
    PlayingLanguages? answered;
    await openDpad(
      tester,
      (context) => showTvDialog(
        context: context,
        builder: (_) => RememberLanguagesDialog(
          scope: const LanguageScope(id: 'show', name: 'A show', kind: LanguageScopeKind.series),
          languages: (audio: 'ja', subtitle: 'en', subtitlesOff: false),
          onAnswer: (_, _, languages) => answered = languages,
        ),
      ),
      overrides: await _preferences(const LanguagePreferences()),
    );
    // The subtitle row, by remote: select on it.
    focusNodeIn(find.ancestor(of: find.text('Subtitles'), matching: find.byType(FocusButton)).first).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(LanguagePicker), matching: find.text('Off')));
    await tester.pumpAndSettle();
    expect(find.byType(LanguagePicker), findsNothing);
    await tester.tap(find.text('Remember'));
    await tester.pumpAndSettle();
    expect(answered, (audio: 'ja', subtitle: null, subtitlesOff: true));
  });

  testWidgets('going to a collection: every collection by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(
        context: context,
        builder: (_) => const ContainingCollectionsDialog(
          collections: [(id: 'a', name: 'First'), (id: 'b', name: 'Second')],
        ),
      ),
      overrides: playerFakes,
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(ContainingCollectionsDialog));
    walk.expectAllReachable(within: find.byType(ContainingCollectionsDialog));
  });

  testWidgets('adding to a collection: right from a collection it is in reaches "go to"', (tester) async {
    await openDpad(
      tester,
      (context) => addItemToCollection(context, [_item('a'), _item('b')]),
      overrides: [...playerFakes, collectionsProvider.overrideWith((ref) => _Collections(ref))],
    );
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(AddToCollection));
    await expectPress(
      tester,
      from: find.ancestor(of: find.text('Collection in'), matching: find.byType(FocusButton)).first,
      key: LogicalKeyboardKey.arrowRight,
      to: find.byTooltip('Go to collection'),
    );
    expect(find.byTooltip('Go to collection'), findsOneWidget);
  });

  testWidgets('language preferences: every rule, choice and button by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showLanguagePreferences(context),
      overrides: await _preferences(LanguagePreferences(
        rules: const [
          LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.language, subtitleLanguage: 'en'),
          LanguageRule(language: 'fr', keepOriginalAudio: false, audioLanguage: 'en'),
        ],
        remembered: {
          'user:show': RememberedLanguages(
            userId: 'user',
            scopeId: 'show',
            name: 'A show',
            kind: LanguageScopeKind.series,
            audioLanguage: 'ja',
            savedAt: DateTime(2026),
          ),
        },
      )),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(Dialog));
    walk.expectAllReachable(within: find.byType(Dialog));

    // Select on a rule opens it, and everything in it is a press away.
    final rule = find.ancestor(of: find.text('JA'), matching: find.byType(ListTile));
    focusNodeIn(rule).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final editor = find.byType(AlertDialog);
    expect(editor, findsOneWidget);
    final inEditor = await walkDpad(tester);
    inEditor.expectStartsInside(editor);
    inEditor.expectAllReachable(within: editor);
  });

  testWidgets('importing settings: every part and both buttons by remote', (tester) async {
    final bundle = SettingsBundle(
      exportedAt: DateTime(2026, 10, 15),
      device: '1.0 (Windows)',
      sections: {
        for (final section in SettingsSection.values) section: const {'a': 1}
      },
    );
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => ImportSettingsDialog(bundle: bundle)),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(ImportSettingsDialog));
    walk.expectAllReachable(within: find.byType(ImportSettingsDialog));
  });

  testWidgets('the queue: every item, its menu and clearing "up next" by remote', (tester) async {
    final films = [for (var i = 0; i < 5; i++) _item('film-$i')];
    final PlaybackModel playing = DirectPlaybackModel(
      item: films.first,
      media: const Media(url: 'film'),
      playbackQueue: PlaybackQueueState.fromQueue(films, initialItemId: films.first.id).addToNextUp([_item('extra')]),
    );
    await openDpad(
      tester,
      (context) => showFullScreenItemQueue(context,
          items: films, currentItem: films.first, onSectionReorder: (_, _, _) async {}),
      overrides: [...playerFakes, playBackModel.overrideWith((ref) => playing)],
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(VideoPlayerQueue));
    walk.expectAllReachable(within: find.byType(VideoPlayerQueue));
  });

  testWidgets('the queue: an item is picked up, moved with up and down, and put down with OK', (tester) async {
    final films = [for (var i = 0; i < 5; i++) _item('film-$i')];
    final PlaybackModel playing = DirectPlaybackModel(
      item: films.first,
      media: const Media(url: 'film'),
      playbackQueue: PlaybackQueueState.fromQueue(films, initialItemId: films.first.id),
    );
    final moves = <String>[];
    await openDpad(
      tester,
      (context) => showFullScreenItemQueue(
        context,
        items: films,
        currentItem: films.first,
        onSectionReorder: (section, from, to) async => moves.add('${section.name} $from>$to'),
      ),
      overrides: [...playerFakes, playBackModel.overrideWith((ref) => playing)],
    );
    Finder row(String title) => find.ancestor(of: find.text(title), matching: find.byType(FocusButton)).first;

    // Held OK picks it up.
    focusNodeIn(row('Title film-1')).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Up and down to move it, OK to put it down'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    // Left and right do not drop it somewhere else.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(moves, ['existing 0>1', 'existing 1>2']);
    expect(find.text('Up and down to move it, OK to put it down'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Up and down to move it, OK to put it down'), findsNothing);
    expect(find.byType(VideoPlayerQueue), findsOneWidget, reason: 'putting it down does not play it or close');

    // A long press with a finger picks it up too, and back puts it down
    // without closing the queue.
    await tester.longPress(row('Title film-3'));
    await tester.pumpAndSettle();
    expect(find.text('Up and down to move it, OK to put it down'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Up and down to move it, OK to put it down'), findsNothing);
    expect(find.byType(VideoPlayerQueue), findsOneWidget);
  });

  testWidgets('adding titles to a collection: every suggestion and button by remote', (tester) async {
    await openDpad(
      tester,
      (context) => showAddTitlesToCollection(context, collection: _item('collection'), members: [_item('member')]),
      overrides: [...playerFakes, relatedUtilityProvider.overrideWith((ref) => _Related(ref))],
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(Dialog));
    walk.expectAllReachable(within: find.byType(Dialog));
  });

  testWidgets('picking titles in the library: the bar at its foot by remote', (tester) async {
    await pumpDpad(
      tester,
      overrides: playerFakes,
      child: Column(
        children: [
          Expanded(child: Center(child: TextButton(autofocus: true, onPressed: () {}, child: const Text('A poster')))),
          CollectionPickBar(collection: _item('collection'), selected: [_item('a')], onClear: () {}),
        ],
      ),
    );
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(CollectionPickBar));
  });
}

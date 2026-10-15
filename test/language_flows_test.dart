// Language preferences end to end: an item as the server sends it, read into
// the app, started in the player, followed by the next one, and the offer to
// remember a change made in the player - through the app's own code, with
// only the server and the native player left out.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/playback_queue_state.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/remember_languages_prompt.dart';
import 'package:chudder/util/language_preference_selection.dart';
import 'package:chudder/util/streams_selection.dart';

import 'dpad/dpad_fakes.dart';
import 'dpad/dpad_walk.dart';

// Track numbers as a typical anime release has them.
const _jpn = 1, _eng = 2, _commentary = 3, _engSub = 4, _dutSub = 5;

MediaStream _stream(MediaStreamType type, int index, String language, {String? title}) => MediaStream(
      type: type,
      index: index,
      language: language,
      title: title,
      displayTitle: title ?? language,
      codec: type == MediaStreamType.subtitle ? 'srt' : 'aac',
      isExternal: false,
      isDefault: false,
    );

/// Japanese first (the original), an English dub, an English commentary,
/// English and Dutch subtitles. The server would play the dub without
/// subtitles.
List<MediaSourceInfo> _animeSources() => [
      MediaSourceInfo(
        id: 'source',
        name: 'main',
        defaultAudioStreamIndex: _eng,
        defaultSubtitleStreamIndex: -1,
        mediaStreams: [
          _stream(MediaStreamType.audio, _jpn, 'jpn'),
          _stream(MediaStreamType.audio, _eng, 'eng'),
          _stream(MediaStreamType.audio, _commentary, 'eng', title: 'Commentary'),
          _stream(MediaStreamType.subtitle, _engSub, 'eng'),
          _stream(MediaStreamType.subtitle, _dutSub, 'dut'),
        ],
      ),
    ];

BaseItemDto _episode(String id, {String show = 'show-a'}) => BaseItemDto(
      id: id,
      name: 'Episode $id',
      type: BaseItemKind.episode,
      seriesId: show,
      seriesName: 'Show $show',
      mediaSources: _animeSources(),
    );

BaseItemDto _film(String id) => BaseItemDto(
      id: id,
      name: 'Film $id',
      type: BaseItemKind.movie,
      mediaSources: _animeSources(),
    );

const _collection = LanguageScope(id: 'collection', name: 'Ghibli', kind: LanguageScopeKind.collection);

RememberedLanguages _remember(
  String scopeId, {
  String userId = 'user',
  String? audio,
  String? subtitle,
  bool off = false,
  LanguageScopeKind kind = LanguageScopeKind.series,
}) =>
    RememberedLanguages(
      userId: userId,
      scopeId: scopeId,
      name: scopeId,
      kind: kind,
      audioLanguage: audio,
      subtitleLanguage: subtitle,
      subtitlesOff: off,
      savedAt: DateTime(2026),
    );

Future<ProviderContainer> _app([LanguagePreferences preferences = const LanguagePreferences()]) async {
  SharedPreferences.setMockInitialValues({languagePreferencesKey: preferences.toJson()});
  final container = ProviderContainer(overrides: [
    ...playerFakes,
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// An item as the app reads it from the server.
T _read<T extends ItemBaseModel>(ProviderContainer container, BaseItemDto dto) =>
    container.read(Provider((ref) => ItemBaseModel.fromBaseDto(dto, ref))) as T;

/// What the player starts [item] with: the preferences that apply at start,
/// then carry-over from [previous] the way the playback model does it.
({int? audio, int? subtitle}) _start(
  ProviderContainer container,
  ItemBaseModel item, {
  LanguageScope? origin,
  ({ItemBaseModel item, MediaStreamsModel streams})? previous,
  MediaStreamsModel? streams,
}) {
  final picked = playbackLanguages(
    streams ?? item.streamModel!,
    preferences: container.read(languagePreferencesProvider),
    userId: 'user',
    seriesId: item is EpisodeModel ? item.parentId : null,
    origin: origin,
    hadPrevious: previous != null,
    previousSeriesId: previous?.item is EpisodeModel ? (previous!.item as EpisodeModel).parentId : null,
  );
  final result = picked.streams;
  return (
    audio: selectAudioStream(
        picked.carryOver, previous?.streams.currentAudioStream, result.audioStreams, result.defaultAudioStreamIndex),
    subtitle: selectSubStream(
        picked.carryOver, previous?.streams.currentSubStream, result.subStreams, result.defaultSubStreamIndex),
  );
}

PlaybackModel _playing(ItemBaseModel item, {List<ItemBaseModel>? queue}) => DirectPlaybackModel(
      item: item,
      media: null,
      mediaStreams: item.streamModel,
      playbackQueue: PlaybackQueueState.fromQueue(queue ?? [item], initialItemId: item.id),
    );

void main() {
  setUp(forgetNotNow);

  group('reading an item', () {
    test('without preferences the server\'s own choice stands', () async {
      final container = await _app();
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(episode.streamModel?.defaultAudioStreamIndex, _eng);
      expect(episode.streamModel?.defaultSubStreamIndex, -1);
      expect(episode.streamModel?.fromPreference, isFalse);
    });

    test('a rule for Japanese: original audio with English subtitles, commentary never', () async {
      final container = await _app(const LanguagePreferences(rules: [
        LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.language, subtitleLanguage: 'en'),
      ]));
      final film = _read<MovieModel>(container, _film('f'));
      expect(film.streamModel?.defaultAudioStreamIndex, _jpn);
      expect(film.streamModel?.defaultSubStreamIndex, _engSub);
    });

    test('a rule asking for the dub takes the dub, not its commentary', () async {
      final container = await _app(const LanguagePreferences(rules: [
        LanguageRule(language: 'ja', keepOriginalAudio: false, audioLanguage: 'en', subtitles: SubtitleRuleMode.off),
      ]));
      final film = _read<MovieModel>(container, _film('f'));
      expect(film.streamModel?.defaultAudioStreamIndex, _eng);
      expect(film.streamModel?.defaultSubStreamIndex, -1);
    });

    test('a choice remembered for a show goes for every episode of it, and before a rule', () async {
      final container = await _app(LanguagePreferences(
        rules: const [LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.off)],
        remembered: {
          'user:show-a': _remember('show-a', audio: 'ja', subtitle: 'nl'),
        },
      ));
      for (final id in ['1', '2', '9']) {
        final episode = _read<EpisodeModel>(container, _episode(id));
        expect(episode.streamModel?.defaultAudioStreamIndex, _jpn, reason: 'episode $id');
        expect(episode.streamModel?.defaultSubStreamIndex, _dutSub, reason: 'episode $id');
      }
      // Another show has only the rule.
      final other = _read<EpisodeModel>(container, _episode('1', show: 'show-b'));
      expect(other.streamModel?.defaultAudioStreamIndex, _jpn);
      expect(other.streamModel?.defaultSubStreamIndex, -1);
    });

    test('what someone else on this device remembered is theirs', () async {
      final container = await _app(LanguagePreferences(remembered: {
        'someone-else:show-a': _remember('show-a', userId: 'someone-else', audio: 'ja', subtitle: 'nl'),
      }));
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(episode.streamModel?.defaultAudioStreamIndex, _eng);
    });

    test('subtitles remembered as off are off, even where the rule wants them', () async {
      final container = await _app(LanguagePreferences(
        rules: const [LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.language, subtitleLanguage: 'en')],
        remembered: {'user:show-a': _remember('show-a', audio: 'ja', off: true)},
      ));
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(episode.streamModel?.defaultSubStreamIndex, -1);
    });

    test('a remembered language the file lacks leaves that side as the server had it', () async {
      final container = await _app(LanguagePreferences(remembered: {
        'user:show-a': _remember('show-a', audio: 'fr', subtitle: 'en'),
      }));
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(episode.streamModel?.defaultAudioStreamIndex, _eng);
      expect(episode.streamModel?.defaultSubStreamIndex, _engSub);
    });
  });

  group('starting playback', () {
    final collectionChoice = LanguagePreferences(remembered: {
      'user:collection': _remember('collection', audio: 'ja', subtitle: 'en', kind: LanguageScopeKind.collection),
    });

    test('a film from its collection plays as remembered for the collection', () async {
      final container = await _app(collectionChoice);
      final film = _read<MovieModel>(container, _film('f'));
      expect(_start(container, film, origin: _collection), (audio: _jpn, subtitle: _engSub));
    });

    test('the same film on its own plays as the server has it', () async {
      final container = await _app(collectionChoice);
      final film = _read<MovieModel>(container, _film('f'));
      expect(_start(container, film), (audio: _eng, subtitle: -1));
    });

    test('tracks picked by hand on the collection page beat the collection\'s choice', () async {
      final container = await _app(collectionChoice);
      final film = _read<MovieModel>(container, _film('f'));
      // As the collection page's pickers leave them.
      final byHand =
          film.streamModel!.copyWith(defaultAudioStreamIndex: _eng, defaultSubStreamIndex: _dutSub, pickedByHand: true);
      expect(_start(container, film, origin: _collection, streams: byHand), (audio: _eng, subtitle: _dutSub));
    });

    test('a show\'s own choice beats the collection it was played from', () async {
      final container = await _app(LanguagePreferences(remembered: {
        ...collectionChoice.remembered,
        'user:show-a': _remember('show-a', audio: 'en', subtitle: 'nl'),
      }));
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(_start(container, episode, origin: _collection), (audio: _eng, subtitle: _dutSub));
    });

    test('a change made mid-show carries on to the next episode', () async {
      final container = await _app(LanguagePreferences(remembered: {
        'user:show-a': _remember('show-a', audio: 'ja', subtitle: 'en'),
      }));
      final first = _read<EpisodeModel>(container, _episode('1'));
      // Switched to the Dutch subtitles while watching.
      final changed = first.streamModel!.copyWith(defaultSubStreamIndex: _dutSub);
      final next = _read<EpisodeModel>(container, _episode('2'));
      expect(_start(container, next, previous: (item: first, streams: changed)), (audio: _jpn, subtitle: _dutSub));
    });

    test('moving to another show starts that show\'s way, not the last one\'s', () async {
      final container = await _app(LanguagePreferences(remembered: {
        'user:show-b': _remember('show-b', audio: 'ja', subtitle: 'en'),
      }));
      final first = _read<EpisodeModel>(container, _episode('1'));
      final watchedWith = first.streamModel!.copyWith(defaultAudioStreamIndex: _eng, defaultSubStreamIndex: _dutSub);
      final other = _read<EpisodeModel>(container, _episode('1', show: 'show-b'));
      expect(_start(container, other, previous: (item: first, streams: watchedWith)), (audio: _jpn, subtitle: _engSub));
    });

    test('films in one collection carry a change on from one to the next', () async {
      final container = await _app(collectionChoice);
      final first = _read<MovieModel>(container, _film('f1'));
      // Started in Japanese from the collection, then switched to Dutch subtitles.
      final changed = first.streamModel!.copyWith(defaultAudioStreamIndex: _jpn, defaultSubStreamIndex: _dutSub);
      final next = _read<MovieModel>(container, _film('f2'));
      expect(
        _start(container, next, origin: _collection, previous: (item: first, streams: changed)),
        (audio: _jpn, subtitle: _dutSub),
      );
    });
  });

  group('what a change in the player is remembered for', () {
    test('an episode: its show', () async {
      final container = await _app();
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(playbackLanguageScope(_playing(episode), _collection)?.id, 'show-a');
    });

    test('a film from a collection: the collection, while it is one of the queue', () async {
      final container = await _app();
      final film = _read<MovieModel>(container, _film('f'));
      final other = _read<MovieModel>(container, _film('g'));
      expect(playbackLanguageScope(_playing(film, queue: [film, other]), _collection)?.id, 'collection');
      expect(playbackLanguageScope(_playing(film), _collection)?.id, 'collection');
    });

    test('a film on its own: nothing', () async {
      final container = await _app();
      final film = _read<MovieModel>(container, _film('f'));
      expect(playbackLanguageScope(_playing(film), null), isNull);
    });

    test('a film that is no longer in the queue the collection started: nothing', () async {
      final container = await _app();
      final film = _read<MovieModel>(container, _film('f'));
      final others = [_read<MovieModel>(container, _film('g')), _read<MovieModel>(container, _film('h'))];
      final model = _playing(film, queue: others);
      expect(playbackLanguageScope(model, _collection), isNull);
    });
  });

  group('the offer to remember', () {
    /// Plays [item], opens the prompt's flow with a "picker" that switches to
    /// [audio] / [subtitle], and leaves whatever dialog follows open.
    Future<ProviderContainer> change(
      WidgetTester tester, {
      required ItemBaseModel Function(ProviderContainer) item,
      LanguagePreferences preferences = const LanguagePreferences(),
      LanguageScope? origin,
      int? audio,
      int? subtitle,
    }) async {
      SharedPreferences.setMockInitialValues({languagePreferencesKey: preferences.toJson()});
      late ProviderContainer container;
      await openDpad(
        tester,
        (context) {
          container = ProviderScope.containerOf(context);
          container.read(playbackOriginProvider.notifier).state = origin;
          final playing = item(container);
          container.read(playBackModel.notifier).state = _playing(playing);
          offerToRememberLanguages(context, () async {
            final model = container.read(playBackModel)!;
            container.read(playBackModel.notifier).state = (model as DirectPlaybackModel).copyWith(
              mediaStreams: () => model.mediaStreams!.copyWith(
                defaultAudioStreamIndex: audio,
                defaultSubStreamIndex: subtitle,
              ),
            );
            return null;
          });
        },
        overrides: [
          ...playerFakes,
          sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        ],
      );
      await tester.pumpAndSettle();
      return container;
    }

    ItemBaseModel Function(ProviderContainer) episode(String id, {String show = 'show-a'}) =>
        (container) => _read<EpisodeModel>(container, _episode(id, show: show));

    final prompt = find.byType(RememberLanguagesDialog);

    testWidgets('switching an episode to Japanese offers it for the show, and the next episode has it', (tester) async {
      final container = await change(tester, item: episode('1'), audio: _jpn, subtitle: _engSub);
      expect(prompt, findsOneWidget);
      expect(find.textContaining('every episode of Show show-a'), findsOneWidget);
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();

      final remembered = container.read(languagePreferencesProvider).rememberedFor('user', 'show-a');
      expect(remembered?.audioLanguage, 'ja');
      expect(remembered?.subtitleLanguage, 'en');
      final next = _read<EpisodeModel>(container, _episode('2'));
      expect(next.streamModel?.defaultAudioStreamIndex, _jpn);
      expect(next.streamModel?.defaultSubStreamIndex, _engSub);
    });

    testWidgets('turning subtitles off is remembered as off', (tester) async {
      final container = await change(
        tester,
        item: episode('1'),
        preferences: LanguagePreferences(remembered: {'user:show-a': _remember('show-a', audio: 'en', subtitle: 'en')}),
        subtitle: -1,
      );
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(container.read(languagePreferencesProvider).rememberedFor('user', 'show-a')?.subtitlesOff, isTrue);
    });

    testWidgets('a language changed in the dialog is the one remembered', (tester) async {
      final container = await change(tester, item: episode('1'), audio: _jpn, subtitle: _engSub);
      await tester.tap(find.text('Subtitles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      final remembered = container.read(languagePreferencesProvider).rememberedFor('user', 'show-a');
      expect(remembered?.audioLanguage, 'ja');
      expect(remembered?.subtitlesOff, isTrue);
    });

    testWidgets('a film from a collection is offered for the collection', (tester) async {
      final container = await change(
        tester,
        item: (container) => _read<MovieModel>(container, _film('f')),
        origin: _collection,
        audio: _jpn,
      );
      expect(find.textContaining('the collection Ghibli'), findsOneWidget);
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(container.read(languagePreferencesProvider).rememberedFor('user', 'collection')?.audioLanguage, 'ja');
    });

    testWidgets('a film on its own is not offered anything', (tester) async {
      await change(tester, item: (container) => _read<MovieModel>(container, _film('f')), audio: _jpn);
      expect(prompt, findsNothing);
    });

    testWidgets('no change, no offer', (tester) async {
      await change(tester, item: episode('1'));
      expect(prompt, findsNothing);
    });

    testWidgets('what is already remembered is not offered again', (tester) async {
      await change(
        tester,
        item: episode('1'),
        preferences: LanguagePreferences(remembered: {'user:show-a': _remember('show-a', audio: 'en', subtitle: 'en')}),
        audio: _eng,
        subtitle: _engSub,
      );
      expect(prompt, findsNothing);
    });

    testWidgets('switched off in the settings, nothing is offered', (tester) async {
      await change(
        tester,
        item: episode('1'),
        preferences: const LanguagePreferences(askToRemember: false),
        audio: _jpn,
      );
      expect(prompt, findsNothing);
    });

    testWidgets('"not now" holds for that show until the app restarts, not for others', (tester) async {
      final container = await change(tester, item: episode('1'), audio: _jpn);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(container.read(languagePreferencesProvider).rememberedFor('user', 'show-a'), isNull);

      await change(tester, item: episode('2'), audio: _jpn);
      expect(prompt, findsNothing, reason: 'same show, same session');

      await change(tester, item: episode('1', show: 'show-b'), audio: _jpn);
      expect(prompt, findsOneWidget, reason: 'another show');
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      forgetNotNow();
      await change(tester, item: episode('3'), audio: _jpn);
      expect(prompt, findsOneWidget, reason: 'after a restart');
    });

    testWidgets('"don\'t ask again" switches the offer off for good', (tester) async {
      final container = await change(tester, item: episode('1'), audio: _jpn);
      await tester.tap(find.text("Don't ask again"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(container.read(languagePreferencesProvider).askToRemember, isFalse);

      await change(
        tester,
        item: episode('1', show: 'show-c'),
        preferences: container.read(languagePreferencesProvider),
        audio: _jpn,
      );
      expect(prompt, findsNothing);
    });
  });

  group('managing what is remembered', () {
    test('forgotten, a show goes back to the rule', () async {
      final container = await _app(LanguagePreferences(
        rules: const [LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.off)],
        remembered: {'user:show-a': _remember('show-a', audio: 'en', subtitle: 'nl')},
      ));
      container.read(languagePreferencesProvider.notifier).forget('user:show-a');
      final episode = _read<EpisodeModel>(container, _episode('1'));
      expect(episode.streamModel?.defaultAudioStreamIndex, _jpn);
      expect(episode.streamModel?.defaultSubStreamIndex, -1);
    });

    test('a rule edited for the same language replaces it', () async {
      final container = await _app(const LanguagePreferences(rules: [
        LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.off),
      ]));
      container
          .read(languagePreferencesProvider.notifier)
          .setRule(const LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.language, subtitleLanguage: 'nl'));
      expect(container.read(languagePreferencesProvider).rules, hasLength(1));
      final film = _read<MovieModel>(container, _film('f'));
      expect(film.streamModel?.defaultSubStreamIndex, _dutSub);
    });

    test('kept across a restart', () async {
      final container = await _app();
      container.read(languagePreferencesProvider.notifier).remember(_remember('show-a', audio: 'ja', subtitle: 'en'));
      final stored = (await SharedPreferences.getInstance()).getString(languagePreferencesKey);
      final restarted = await _app(LanguagePreferences.fromJson(stored));
      expect(restarted.read(languagePreferencesProvider).rememberedFor('user', 'show-a')?.audioLanguage, 'ja');
    });
  });
}

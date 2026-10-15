import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/library_filter_model.dart';
import 'package:chudder/providers/language_index_provider.dart';

MediaStream _audio(String language, {bool external = false}) =>
    MediaStream(type: MediaStreamType.audio, language: language, isExternal: external);
MediaStream _sub(String language) => MediaStream(type: MediaStreamType.subtitle, language: language);

void main() {
  group('reading a title\'s languages', () {
    test('made in the first audio track\'s language, codes made comparable', () {
      final entry = LanguageEntry.fromStreams([
        const MediaStream(type: MediaStreamType.video),
        _audio('jpn'),
        _audio('eng'),
        _sub('eng'),
        _sub('dut'),
      ]);
      expect(entry.original, 'ja');
      expect(entry.audio, {'ja', 'en'});
      expect(entry.subtitles, {'en', 'nl'});
    });

    test('an external dub added later is not what it was made in', () {
      final entry = LanguageEntry.fromStreams([_audio('eng', external: true), _audio('fre')]);
      expect(entry.original, 'fr');
    });

    test('undetermined languages count as none', () {
      final entry = LanguageEntry.fromStreams([_audio('und'), _sub('mul')]);
      expect(entry.original, '');
      expect(entry.audio, isEmpty);
      expect(entry.subtitles, isEmpty);
    });
  });

  group('a show', () {
    final index = LanguageIndex(
      items: {
        'e1': const LanguageEntry(original: 'ko', audio: {'ko'}, subtitles: {'en'}),
        'e2': const LanguageEntry(original: 'ko', audio: {'ko', 'en'}, subtitles: {'nl'}),
        'e3': const LanguageEntry(original: 'en', audio: {'en'}),
        'film': const LanguageEntry(original: 'fr', audio: {'fr'}, subtitles: {'en'}),
      },
      episodes: {'e1': 'show', 'e2': 'show', 'e3': 'show'},
    );

    test('has every language its episodes have, and was made in what most were', () {
      final show = index.entryFor('show')!;
      expect(show.original, 'ko');
      expect(show.audio, {'ko', 'en'});
      expect(show.subtitles, {'en', 'nl'});
    });

    test('counts once in the filter lists, not once per episode', () {
      expect(index.counts.original, {'ko': 1, 'fr': 1});
      expect(index.counts.subtitles, {'en': 2, 'nl': 1});
    });
  });

  group('filtering', () {
    const korean = LanguageEntry(original: 'ko', audio: {'ko', 'en'}, subtitles: {'en'});

    test('nothing asked, everything kept - even what is not known', () {
      expect(const LanguageQuery().matches(null), isTrue);
    });

    test('any of the languages ticked in one filter will do', () {
      expect(const LanguageQuery(original: {'ja', 'ko'}).matches(korean), isTrue);
      expect(const LanguageQuery(original: {'ja'}).matches(korean), isFalse);
    });

    test('every filter that asks must hold', () {
      expect(const LanguageQuery(original: {'ko'}, audio: {'en'}).matches(korean), isTrue);
      expect(const LanguageQuery(original: {'ko'}, subtitles: {'nl'}).matches(korean), isFalse);
    });

    test('a title the index does not know is left out when a language is asked for', () {
      expect(const LanguageQuery(audio: {'en'}).matches(null), isFalse);
    });
  });

  test('kept on the device and read back', () {
    final index = LanguageIndex(
      items: {
        'a': const LanguageEntry(original: 'ja', audio: {'ja'}, subtitles: {'en'})
      },
      episodes: {'a': 'show'},
      builtAt: DateTime.utc(2026, 10, 15),
      complete: true,
    );
    final back = LanguageIndex.decode(index.encode());
    expect(back.complete, isTrue);
    expect(back.builtAt, DateTime.utc(2026, 10, 15));
    expect(back.entryFor('show')?.subtitles, {'en'});
    expect(LanguageIndex.decode('not json').items, isEmpty);
  });

  test('a language ticked counts as a filter, and is part of a saved filter', () {
    const filters = LibraryFilterModel(audioLanguages: {'ja': true, 'en': false});
    expect(filters.hasLanguageFilters, isTrue);
    expect(filters.hasActiveFilters, isTrue);
    expect(filters == const LibraryFilterModel(audioLanguages: {'ja': true}), isTrue);
    expect(filters == const LibraryFilterModel(audioLanguages: {'en': true}), isFalse);
    final back = LibraryFilterModel.fromJson(jsonDecode(jsonEncode(filters.toJson())));
    expect(back.audioLanguages['ja'], isTrue);
    expect(filters.clear().hasLanguageFilters, isFalse);
  });
}

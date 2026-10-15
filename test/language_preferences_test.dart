import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/util/language_preference_selection.dart';

AudioStreamModel _audio(int index, String language, {String title = ''}) => AudioStreamModel(
      displayTitle: title.isEmpty ? language : title,
      name: title,
      codec: 'aac',
      isDefault: false,
      isExternal: false,
      index: index,
      language: language,
      channelLayout: 'stereo',
      sampleRate: 48000,
      channels: 2,
      bitRate: null,
      bitDepth: null,
      profile: null,
      spatialFormat: null,
    );

SubStreamModel _sub(int index, String language) => SubStreamModel(
      name: language,
      id: '$index',
      title: language,
      displayTitle: language,
      language: language,
      codec: 'srt',
      isDefault: false,
      isExternal: false,
      index: index,
    );

/// An anime release: Japanese first, an English dub and a commentary after,
/// English and Dutch subtitles; the server picked the dub and no subtitles.
MediaStreamsModel _anime({int? audio = 2, int? sub = -1}) => MediaStreamsModel(
      defaultAudioStreamIndex: audio,
      defaultSubStreamIndex: sub,
      versionStreams: [
        VersionStreamModel(
          name: 'main',
          index: 0,
          defaultAudioStreamIndex: audio,
          defaultSubStreamIndex: sub,
          videoStreams: const [],
          audioStreams: [
            _audio(1, 'jpn'),
            _audio(2, 'eng'),
            _audio(3, 'eng', title: 'Director commentary'),
          ],
          subStreams: [_sub(4, 'eng'), _sub(5, 'dut')],
        ),
      ],
    );

RememberedLanguages _remembered({String? audio, String? subtitle, bool off = false}) => RememberedLanguages(
      userId: 'user',
      scopeId: 'show',
      name: 'Show',
      kind: LanguageScopeKind.series,
      audioLanguage: audio,
      subtitleLanguage: subtitle,
      subtitlesOff: off,
      savedAt: DateTime(2026),
    );

void main() {
  test('the original language is the first audio track', () {
    expect(originalLanguageOf(_anime()), 'ja');
  });

  group('remembered for a show', () {
    test('finds the tracks by language, whatever their number', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(),
        remembered: _remembered(audio: 'ja', subtitle: 'nl'),
      );
      expect(picked.audio, 1);
      expect(picked.subtitle, 5);
    });

    test('subtitles off is remembered as off', () {
      final picked = preferredTracks(
        _anime(sub: 4),
        preferences: const LanguagePreferences(),
        remembered: _remembered(audio: 'en', off: true),
      );
      expect(picked.audio, 2);
      expect(picked.subtitle, -1);
    });

    test('a language the file does not have leaves that side alone', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(),
        remembered: _remembered(audio: 'fr', subtitle: 'de'),
      );
      expect(picked.audio, isNull);
      expect(picked.subtitle, isNull);
    });

    test('goes before a rule for the language', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(rules: [LanguageRule(language: 'ja', keepOriginalAudio: true)]),
        remembered: _remembered(audio: 'en'),
      );
      expect(picked.audio, 2);
    });
  });

  group('rules by original language', () {
    test('keeping the original plays the Japanese over the server\'s dub', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(rules: [
          LanguageRule(language: 'ja', subtitles: SubtitleRuleMode.language, subtitleLanguage: 'en'),
        ]),
      );
      expect(picked.audio, 1);
      expect(picked.subtitle, 4);
    });

    test('a preferred dub skips the commentary in the same language', () {
      final picked = preferredTracks(
        _anime(audio: 3),
        preferences: const LanguagePreferences(rules: [
          LanguageRule(language: 'ja', keepOriginalAudio: false, audioLanguage: 'en', subtitles: SubtitleRuleMode.off),
        ]),
      );
      expect(picked.audio, 2);
      expect(picked.subtitle, -1);
    });

    test('without the dub, the original plays', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(rules: [
          LanguageRule(language: 'ja', keepOriginalAudio: false, audioLanguage: 'nl'),
        ]),
      );
      expect(picked.audio, 1);
    });

    test('"any other language" covers what has no rule of its own', () {
      final picked = preferredTracks(
        _anime(),
        preferences: const LanguagePreferences(rules: [
          LanguageRule(language: 'ko'),
          LanguageRule(language: LanguageRule.anyLanguage, subtitles: SubtitleRuleMode.off),
        ]),
      );
      expect(picked.audio, 1);
      expect(picked.subtitle, -1);
    });

    test('no rule, nothing changes', () {
      final streams = _anime();
      final result = streams.withLanguagePreferences(const LanguagePreferences(rules: [LanguageRule(language: 'ko')]));
      expect(identical(result, streams), isTrue);
      expect(result.fromPreference, isFalse);
    });
  });

  test('applied preferences are marked, and a pick by hand clears the mark', () {
    final preferred = _anime().withLanguagePreferences(
      const LanguagePreferences(rules: [LanguageRule(language: 'ja')]),
    );
    expect(preferred.defaultAudioStreamIndex, 1);
    expect(preferred.fromPreference, isTrue);
    expect(preferred.copyWith(defaultAudioStreamIndex: 2).fromPreference, isFalse);
  });

  test('preferences survive being stored and read back', () {
    final preferences = LanguagePreferences(
      askToRemember: false,
      remembered: {_remembered(audio: 'ja', off: true).key: _remembered(audio: 'ja', off: true)},
      rules: const [
        LanguageRule(language: 'fr', keepOriginalAudio: false, audioLanguage: 'en', subtitles: SubtitleRuleMode.off),
      ],
    );
    final read = LanguagePreferences.fromJson(preferences.toJson());
    expect(read.askToRemember, isFalse);
    expect(read.rememberedFor('user', 'show')?.audioLanguage, 'ja');
    expect(read.rememberedFor('user', 'show')?.subtitlesOff, isTrue);
    expect(read.ruleFor('fr')?.audioLanguage, 'en');
    expect(read.ruleFor('fr')?.subtitles, SubtitleRuleMode.off);
    expect(LanguagePreferences.fromJson('not json').rules, isEmpty);
  });
}

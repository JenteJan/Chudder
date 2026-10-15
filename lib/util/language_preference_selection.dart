import 'package:collection/collection.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

/// The language a film or episode was made in, as far as the file says: the
/// first audio track's, which is where releases put the original. Empty when
/// that track names no language.
String originalLanguageOf(MediaStreamsModel streams) {
  final first = streams.audioStreams.where((stream) => !stream.isExternal).firstOrNull ?? streams.audioStreams.firstOrNull;
  return first == null ? '' : normalizeLanguage(first.language);
}

bool _isCommentary(AudioAndSubStreamModel stream) =>
    '${stream.name} ${stream.displayTitle}'.toLowerCase().contains('commentary');

/// The track in [language], the server's own pick when that is one of them -
/// it knows about forced and hearing-impaired flags this does not - unless
/// that is a commentary; otherwise the first, leaving commentaries for last.
T? _inLanguage<T extends AudioAndSubStreamModel>(List<T> streams, String language, int? serverDefault) {
  if (language.isEmpty) return null;
  final matching = streams.where((stream) => normalizeLanguage(stream.language) == language).toList();
  if (matching.isEmpty) return null;
  return matching.firstWhereOrNull((stream) => stream.index == serverDefault && !_isCommentary(stream)) ??
      matching.firstWhereOrNull((stream) => !_isCommentary(stream)) ??
      matching.first;
}

/// The audio and subtitle tracks the preferences ask for in [streams]: what
/// was remembered for the show, collection or playlist first, a rule for the
/// original language after that. A side the preferences say nothing about,
/// or ask for a language the file does not have, is null and stays as it was.
({int? audio, int? subtitle}) preferredTracks(
  MediaStreamsModel streams, {
  required LanguagePreferences preferences,
  RememberedLanguages? remembered,
}) {
  final audioDefault = streams.defaultAudioStreamIndex;
  final subDefault = streams.defaultSubStreamIndex;
  if (remembered != null) {
    final audio = remembered.audioLanguage == null
        ? null
        : _inLanguage(streams.audioStreams, remembered.audioLanguage!, audioDefault)?.index;
    final subtitle = remembered.subtitlesOff
        ? -1
        : remembered.subtitleLanguage == null
            ? null
            : _inLanguage(streams.subStreams, remembered.subtitleLanguage!, subDefault)?.index;
    return (audio: audio, subtitle: subtitle);
  }

  final original = originalLanguageOf(streams);
  if (original.isEmpty) return (audio: null, subtitle: null);
  final rule = preferences.ruleFor(original);
  if (rule == null) return (audio: null, subtitle: null);

  final wanted = rule.keepOriginalAudio ? original : (rule.audioLanguage ?? original);
  final audio = (_inLanguage(streams.audioStreams, wanted, audioDefault) ??
          _inLanguage(streams.audioStreams, original, audioDefault))
      ?.index;
  final subtitle = switch (rule.subtitles) {
    SubtitleRuleMode.server => null,
    SubtitleRuleMode.off => -1,
    SubtitleRuleMode.language => rule.subtitleLanguage == null
        ? null
        : _inLanguage(streams.subStreams, rule.subtitleLanguage!, subDefault)?.index,
  };
  return (audio: audio, subtitle: subtitle);
}

extension LanguagePreferenceStreams on MediaStreamsModel {
  /// These streams with the tracks the preferences ask for as their
  /// defaults; see [preferredTracks]. Marked [MediaStreamsModel.fromPreference]
  /// when that changed anything.
  MediaStreamsModel withLanguagePreferences(
    LanguagePreferences preferences, {
    RememberedLanguages? remembered,
  }) {
    if (audioStreams.isEmpty) return this;
    if (remembered == null && preferences.rules.isEmpty) return this;
    final picked = preferredTracks(this, preferences: preferences, remembered: remembered);
    if (picked.audio == null && picked.subtitle == null) return this;
    return copyWith(
      defaultAudioStreamIndex: picked.audio,
      defaultSubStreamIndex: picked.subtitle,
      fromPreference: true,
    );
  }
}

/// The tracks a new item starts playing with, and whether the previous item's
/// tracks may carry on over them.
///
/// Parsing already applied what was remembered for the show, or a rule (see
/// `applyLanguagePreferences`). This adds what playback knows that parsing
/// did not: the collection or playlist [origin] it was started from - unless
/// the show has its own choice or the tracks were [MediaStreamsModel.pickedByHand].
///
/// Carry-over is off when the preferences chose something and playback moved
/// to somewhere else: a new show, or a film from no collection or playlist.
/// Within one show or one origin the last item's tracks carry on, so a change
/// made mid-show is not undone by the next episode.
({MediaStreamsModel streams, bool carryOver}) playbackLanguages(
  MediaStreamsModel streams, {
  required LanguagePreferences preferences,
  required String? userId,
  required String? seriesId,
  required LanguageScope? origin,
  required bool hadPrevious,
  String? previousSeriesId,
}) {
  var result = streams;
  if (!streams.pickedByHand && preferences.rememberedFor(userId, seriesId) == null) {
    final originChoice = preferences.rememberedFor(userId, origin?.id);
    if (originChoice != null) result = result.withLanguagePreferences(preferences, remembered: originChoice);
  }
  final sameScope = hadPrevious && previousSeriesId == seriesId && (seriesId != null || origin != null);
  return (streams: result, carryOver: !(result.fromPreference && !sameScope));
}

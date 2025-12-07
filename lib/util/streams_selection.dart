import 'package:fladder/models/items/media_streams_model.dart';

int? selectAudioStream(
  bool rememberAudioSelection,
  AudioAndSubStreamModel? previousStream,
  List<AudioAndSubStreamModel>? currentStream,
  int? defaultStream, {
  String? preferredLanguage,
}) {
  // First try preferred language if set
  if (preferredLanguage != null && currentStream != null) {
    final preferredStream = _findStreamByPreferredLanguage(currentStream, preferredLanguage);
    if (preferredStream != null) return preferredStream;
  }

  if (!rememberAudioSelection) {
    return defaultStream;
  }
  return _selectStream(previousStream, currentStream, defaultStream);
}

int? selectSubStream(
  bool rememberSubSelection,
  AudioAndSubStreamModel? previousStream,
  List<AudioAndSubStreamModel>? currentStream,
  int? defaultStream, {
  String? preferredLanguage,
}) {
  // First try preferred language if set
  if (preferredLanguage != null && currentStream != null) {
    final preferredStream = _findStreamByPreferredLanguage(
      currentStream,
      preferredLanguage,
      excludeForced: true,
    );
    if (preferredStream != null) return preferredStream;
  }

  if (!rememberSubSelection) {
    return defaultStream;
  }
  return _selectStream(previousStream, currentStream, defaultStream);
}

/// Find a stream by preferred language code or display title containing the language
int? _findStreamByPreferredLanguage(
  List<AudioAndSubStreamModel> streams,
  String preferredLanguage, {
  bool excludeForced = false,
}) {
  final lowerPref = preferredLanguage.toLowerCase();

  // Special case: "vo" for original version (look for "vo" in display title)
  if (lowerPref == 'vo') {
    final voStream = streams.firstWhereOrNull(
      (stream) => stream.displayTitle.toLowerCase().contains('vo'),
    );
    if (voStream != null) return voStream.index;
  }

  // Try exact language code match first
  for (final stream in streams) {
    if (excludeForced && stream is SubStreamModel) {
      // Skip forced subtitles
      if (stream.displayTitle.toLowerCase().contains('forced')) continue;
    }
    if (stream.language.toLowerCase() == lowerPref) {
      return stream.index;
    }
  }

  // Try matching by display title starting with the language
  for (final stream in streams) {
    if (excludeForced && stream is SubStreamModel) {
      if (stream.displayTitle.toLowerCase().contains('forced')) continue;
    }
    if (stream.displayTitle.toLowerCase().startsWith(lowerPref)) {
      return stream.index;
    }
  }

  return null;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

int? _selectStream(
  AudioAndSubStreamModel? previousStream,
  List<AudioAndSubStreamModel>? currentStream,
  int? defaultStream,
) {
  if (currentStream == null || previousStream == null) {
    return defaultStream;
  }

  int? bestStreamIndex;
  int bestStreamScore = 0;

  // Find the relative index of the previous stream
  int prevRelIndex = 0;
  for (var stream in currentStream) {
    if (stream.index == previousStream.index) break;
    prevRelIndex += 1;
  }

  int newRelIndex = 0;
  for (var stream in currentStream) {
    int score = 0;

    if (previousStream.codec == stream.codec) score += 1;
    if (prevRelIndex == newRelIndex) score += 1;
    if (previousStream.displayTitle == stream.displayTitle) {
      score += 2;
    }
    if (previousStream.language != 'und' && previousStream.language == stream.language) {
      score += 2;
    }

    if (score > bestStreamScore && score >= 3) {
      bestStreamScore = score;
      bestStreamIndex = stream.index;
    }

    newRelIndex += 1;
  }
  return bestStreamIndex ?? defaultStream;
}

import 'dart:math' as math;

import 'package:chudder/models/subtitles/subtitle_cues.dart';

/// Lining subtitles up by a line the viewer just heard: they pause, type a
/// few words of it, and pick the cue it was. The gap between when they
/// heard it and when the file shows it is the timing.
///
/// Typed words find the line; when the subtitle is a translation they will
/// not, so the lines around the paused moment are always offered as well -
/// the viewer picks the one that means what was said.

/// A cue offered for a typed line, and what picking it would set.
class SubtitleLineCandidate {
  const SubtitleLineCandidate({
    required this.cue,
    required this.score,
    required this.delay,
    this.matched = const {},
  });

  final SubtitleCue cue;

  /// How well the typed words fit the cue, 0 to 1; 0 for a line offered only
  /// because it is near.
  final double score;

  /// The subtitle delay that lines this cue up with what was heard.
  final Duration delay;

  /// The cue's words (normalised) the typing matched, for highlighting.
  final Set<String> matched;
}

/// What was typed, matched against a subtitle file.
class SubtitleLineSearch {
  const SubtitleLineSearch({
    required this.matches,
    required this.nearby,
    required this.nearest,
    this.clearBest = false,
  });

  /// Cues the typed words fit, best first. Empty while nothing is typed.
  final List<SubtitleLineCandidate> matches;

  /// The cues around the paused moment in time order - for a translation,
  /// or a line typed too loosely to find.
  final List<SubtitleLineCandidate> nearby;

  /// The index in [nearby] of the line most likely just heard: the last one
  /// to have ended by then.
  final int nearest;

  /// Whether the first match beats the rest by enough to be taken without
  /// the viewer choosing - what Enter in the search field does.
  final bool clearBest;
}

/// How long after a line ends the viewer has usually pressed the button.
/// Only the first guess: the timing itself comes from a tap on the line.
const lineMatchReaction = Duration(milliseconds: 350);

/// How far the first match has to be ahead of the second for Enter to take
/// it.
const _clearLead = 0.12;

/// Searches [cues] for [query], heard just before [heardAt] in the video
/// while the subtitles were moved by [currentDelay].
SubtitleLineSearch searchSubtitleLines(
  SubtitleCueList cues,
  String query, {
  required Duration heardAt,
  Duration currentDelay = Duration.zero,
  int maxMatches = 6,
  int nearbyBefore = 6,
  int nearbyAfter = 6,
}) {
  // Where in the file the moment falls with the timing as it is now; the
  // line heard is most likely close to it - before it when the subtitles
  // are early, after it when they are late, so both sides are offered.
  final inFile = heardAt - currentDelay;

  SubtitleLineCandidate candidate(SubtitleCue cue, double score, Set<String> matched) => SubtitleLineCandidate(
        cue: cue,
        score: score,
        delay: lineMatchDelay(heardAt, cue),
        matched: matched,
      );

  final list = cues.cues;
  // The last cue to have ended by the moment (cues are sorted by start; the
  // few overlapping ones do not change which is nearest by much).
  var nearestIndex = -1;
  for (var i = 0; i < list.length; i++) {
    if (list[i].start > inFile) break;
    if (list[i].end <= inFile + lineMatchReaction) nearestIndex = i;
  }
  if (nearestIndex == -1 && list.isNotEmpty) nearestIndex = 0;
  final from = math.max(0, nearestIndex - nearbyBefore + 1);
  final to = math.min(list.length, nearestIndex + nearbyAfter + 1);
  final nearby = [for (var i = from; i < to; i++) candidate(list[i], 0, const {})];

  final words = normaliseSubtitleText(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) {
    return SubtitleLineSearch(matches: const [], nearby: nearby, nearest: nearestIndex - from);
  }

  final index = _indexOf(cues);
  // A word found all over the file ("you", "the") says little about which
  // line it was; a rare one ("helicopter") says a lot.
  final weights = [
    for (final word in words) math.log((index.lines.length + 1) / ((index.lineCounts[word] ?? 0) + 1)) + 1,
  ];

  final scored = <(SubtitleLineCandidate, double)>[];
  for (var i = 0; i < list.length; i++) {
    final cue = list[i];
    final (score, matched) = _score(words, weights, index.lines[i]);
    if (score < 0.5) continue;
    // A line said often ("What?") is best found near the moment: a line ten
    // minutes off costs a little, so the near one wins a tie.
    final distance = (cue.end - inFile).abs().inMilliseconds / const Duration(minutes: 10).inMilliseconds;
    final ranked = score - 0.2 * math.min(distance, 1.0);
    scored.add((candidate(cue, math.min(score, 1.0), matched), ranked));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  final clearBest = scored.isNotEmpty && (scored.length == 1 || scored[0].$2 - scored[1].$2 >= _clearLead);
  return SubtitleLineSearch(
    matches: [for (final s in scored.take(maxMatches)) s.$1],
    nearby: nearby,
    nearest: nearestIndex - from,
    clearBest: clearBest,
  );
}

/// Every cue's words, normalised once per file rather than on every key,
/// and in how many lines each word is.
class _LineIndex {
  _LineIndex(this.lines, this.lineCounts);
  final List<List<String>> lines;
  final Map<String, int> lineCounts;
}

final _indexes = Expando<_LineIndex>();

_LineIndex _indexOf(SubtitleCueList cues) => _indexes[cues] ??= () {
      final lines = [
        for (final cue in cues.cues) normaliseSubtitleText(cue.text).split(' ').where((w) => w.isNotEmpty).toList(),
      ];
      final counts = <String, int>{};
      for (final line in lines) {
        for (final word in line.toSet()) {
          counts[word] = (counts[word] ?? 0) + 1;
        }
      }
      return _LineIndex(lines, counts);
    }();

/// The delay that shows [cue] as the line heard just before [heardAt].
///
/// A cue often stays up well after the words are said, so its end is a poor
/// mark for when the speaking stopped; the length of the text says roughly
/// how long it took to say, counted from the cue's start.
Duration lineMatchDelay(Duration heardAt, SubtitleCue cue) {
  final length = cue.end - cue.start;
  final spoken = Duration(milliseconds: cue.text.replaceAll(RegExp(r'\s+'), ' ').length * 70);
  final said = spoken < const Duration(milliseconds: 600)
      ? const Duration(milliseconds: 600)
      : (spoken > length ? length : spoken);
  final exact = heardAt - lineMatchReaction - (cue.start + said);
  // Finer than a twentieth of a second is more exact than the estimate is.
  return Duration(milliseconds: (exact.inMilliseconds / 50).round() * 50);
}

/// Lower case words only: no hearing-impaired notes, speaker names,
/// punctuation or accents - what a viewer types is none of those.
String normaliseSubtitleText(String text) {
  var value = text
      .replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|♪|#'), ' ')
      // A speaker is named in capitals ("JOHN:"); "Here's the thing:" is
      // part of the line.
      .replaceAll(RegExp(r"^\s*-?\s*[A-Z][A-Z .']{0,20}:\s", multiLine: true), ' ')
      .toLowerCase()
      .replaceAll(RegExp(r"['’`]"), '');
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  value = buffer.toString().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
  return value.trim();
}

const _accents = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
  'ç': 'c',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ß': 'ss',
};

/// How much of what was typed is in [words], and which of them it found.
/// Each typed word counts, by its [weights], for the best word it fits: the
/// same word, the start of one (the last word is often half typed), or one
/// a letter or two off (misheard or misspelt). The words in order score a
/// little extra, and so does a line that is mostly what was typed. Not
/// capped at 1: the extras are what tell two full matches apart.
(double, Set<String>) _score(List<String> typed, List<double> weights, List<String> words) {
  if (words.isEmpty) return (0, const {});
  var total = 0.0;
  var weightSum = 0.0;
  final matched = <String>{};
  for (var i = 0; i < typed.length; i++) {
    final word = typed[i];
    final last = i == typed.length - 1;
    var best = 0.0;
    String? bestWord;
    for (final candidate in words) {
      final fit = _wordFit(word, candidate, partial: last);
      if (fit > best) {
        best = fit;
        bestWord = candidate;
      }
      if (best == 1) break;
    }
    total += best * weights[i];
    weightSum += weights[i];
    if (bestWord != null) matched.add(bestWord);
  }
  var score = total / weightSum;
  if (typed.length > 1 && words.join(' ').contains(typed.join(' '))) score += 0.15;
  // Of two lines with every typed word, the one with little else is it.
  score += 0.1 * words.where(matched.contains).length / words.length;
  // One short common word ("i", "a") finds half the file; it needs more.
  if (typed.length == 1 && typed.first.length < 3) score *= 0.6;
  return (score, matched);
}

double _wordFit(String typed, String word, {required bool partial}) {
  if (typed == word) return 1;
  if (partial && typed.length >= 2 && word.startsWith(typed)) return 0.85;
  if (typed.length < 4 || word.length < 3) return 0;
  final distance = _levenshtein(typed, word, limit: 2);
  if (distance == 1) return 0.75;
  if (distance == 2 && typed.length >= 7) return 0.55;
  return 0;
}

int _levenshtein(String a, String b, {required int limit}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      current[j] = math.min(math.min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
      rowMin = math.min(rowMin, current[j]);
    }
    if (rowMin > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}

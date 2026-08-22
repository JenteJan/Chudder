import 'dart:math' as math;

/// How close a name is to what was typed, for names the server's own search
/// would not have returned at all.
///
/// Jellyfin's search is a substring filter: "inglorious" finds nothing, because
/// the film is spelled "Inglourious". So the misses have to be caught here,
/// against names the app already holds.
///
/// Returns 0 for anything not close enough to be worth showing. That gate
/// matters more than the ranking: a search list puts what you have above what
/// you do not, so a weak local guess would sit above an exact match from
/// somewhere else. Better to admit the library has nothing.
double fuzzyScore(String name, String query) {
  final target = name.trim().toLowerCase();
  final term = query.trim().toLowerCase();
  if (target.isEmpty || term.length < 3) return 0;

  // A substring match is the server's job, not this one, but scoring it highest
  // keeps callers from having to special-case it.
  if (target.contains(term)) return 1;

  final direct = _closeness(target, term);
  // Against the whole title "alien" scores badly on "Alien: Resurrection"
  // simply for being shorter than it, so each word gets its own chance.
  final byWord = target
      .split(_wordBreak)
      .where((word) => word.length > 2)
      .map((word) => _closeness(word, term))
      .fold(0.0, math.max);

  final best = math.max(direct, byWord);
  return best >= _threshold ? best : 0;
}

/// Below this, the two words are different words. Around 0.8 a ten-letter title
/// may be two edits out — a doubled letter and a swap, which is what a typo
/// looks like — while genuinely unrelated names fall well short.
const _threshold = 0.8;

final _wordBreak = RegExp(r"[\s\-:_/\()\[\]{}.,!?'’–—]+");

/// 1 for identical, falling towards 0 as the edits pile up.
double _closeness(String target, String term) {
  final longest = math.max(target.length, term.length);
  if (longest == 0) return 0;
  // Nothing within the threshold can need more edits than this, and the check
  // is far cheaper than the matrix.
  if ((target.length - term.length).abs() / longest > 1 - _threshold) return 0;
  return 1 - _editDistance(target, term) / longest;
}

/// Damerau-Levenshtein, restricted to adjacent transpositions — "teh" for
/// "the" is one mistake, not two.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var twoBack = List<int>.filled(b.length + 1, 0);
  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitution = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var best = math.min(
        current[j - 1] + 1,
        math.min(previous[j] + 1, previous[j - 1] + substitution),
      );
      if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
        best = math.min(best, twoBack[j - 2] + 1);
      }
      current[j] = best;
    }
    final rotated = twoBack;
    twoBack = previous;
    previous = current;
    current = rotated;
  }

  return previous[b.length];
}

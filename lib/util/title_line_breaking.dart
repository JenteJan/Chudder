/// Keeps a title from breaking in the middle of a word.
///
/// Flutter breaks lines where Unicode says it may, and Unicode allows a break
/// directly before a colon or a similar separator. In a title that puts one
/// against the end of a word — "Caminandes: Llamigos" — a narrow column breaks
/// between the word and its colon, and the second line opens with a stray
/// ": Llamigos". Reading it, the colon looks like it belongs to nothing.
///
/// A word joiner in front of the punctuation says the two characters are one
/// run, so the break moves to the space where a break belongs. It is invisible
/// and has no width; the only cost is that copying the text carries it along.
extension TitleLineBreaking on String {
  static final _beforePunctuation = RegExp(r'(?<=\S)(?=[:;,.!?–—])');

  /// This string with word joiners in front of any punctuation that sits
  /// against the end of a word.
  String get keepPunctuationWithWord => replaceAll(_beforePunctuation, '⁠');
}

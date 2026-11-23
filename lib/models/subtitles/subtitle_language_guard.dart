/// Whether a subtitle is in the language that was searched for, as far as
/// its stated language and its name can tell.
///
/// Providers take the language from the uploader, and a file sent in as
/// English is not always English. A release name that says "German" or
/// "Türkçe" in an English search is one that says so out loud; those are
/// left out. A name that also says the language searched for (a release with
/// both tracks) is kept.
library;

/// Language codes, two and three letters in both ISO 639-2 forms, and the
/// names, to one name per language. For codes a provider states; release
/// names go through [_nameWords] instead.
const Map<String, String> _codes = {
  // English
  'english': 'english', 'eng': 'english', 'en': 'english',
  // German
  'german': 'german', 'deutsch': 'german', 'ger': 'german', 'deu': 'german', 'de': 'german',
  // Dutch
  'dutch': 'dutch', 'nederlands': 'dutch', 'dut': 'dutch', 'nld': 'dutch', 'nl': 'dutch', 'flemish': 'dutch',
  // French
  'french': 'french', 'francais': 'french', 'français': 'french', 'fre': 'french', 'fra': 'french', 'fr': 'french',
  'vostfr': 'french', 'vff': 'french', 'truefrench': 'french',
  // Spanish
  'spanish': 'spanish', 'espanol': 'spanish', 'español': 'spanish', 'castellano': 'spanish', 'latino': 'spanish',
  'spa': 'spanish', 'es': 'spanish',
  // Italian
  'italian': 'italian', 'italiano': 'italian', 'ita': 'italian',
  // Portuguese
  'portuguese': 'portuguese', 'portugues': 'portuguese', 'português': 'portuguese', 'brazilian': 'portuguese',
  'por': 'portuguese', 'pt': 'portuguese', 'ptbr': 'portuguese',
  // Turkish
  'turkish': 'turkish', 'turkce': 'turkish', 'türkçe': 'turkish', 'tur': 'turkish', 'tr': 'turkish',
  // Polish
  'polish': 'polish', 'polski': 'polish', 'pol': 'polish', 'pl': 'polish',
  // Russian
  'russian': 'russian', 'rus': 'russian', 'ru': 'russian',
  // Swedish, Danish, Norwegian, Finnish
  'swedish': 'swedish', 'svenska': 'swedish', 'swe': 'swedish', 'sv': 'swedish',
  'danish': 'danish', 'dansk': 'danish', 'dan': 'danish', 'da': 'danish',
  'norwegian': 'norwegian', 'norsk': 'norwegian', 'nor': 'norwegian', 'nob': 'norwegian',
  'finnish': 'finnish', 'suomi': 'finnish', 'fin': 'finnish', 'fi': 'finnish',
  // Central and Eastern Europe
  'czech': 'czech', 'cze': 'czech', 'ces': 'czech', 'cs': 'czech',
  'hungarian': 'hungarian', 'magyar': 'hungarian', 'hun': 'hungarian', 'hu': 'hungarian',
  'romanian': 'romanian', 'rum': 'romanian', 'ron': 'romanian', 'ro': 'romanian',
  'greek': 'greek', 'gre': 'greek', 'ell': 'greek', 'el': 'greek',
  'croatian': 'croatian', 'hrvatski': 'croatian', 'hrv': 'croatian', 'hr': 'croatian',
  'serbian': 'serbian', 'srpski': 'serbian', 'srp': 'serbian', 'sr': 'serbian',
  'bulgarian': 'bulgarian', 'bul': 'bulgarian', 'bg': 'bulgarian',
  'slovenian': 'slovenian', 'slv': 'slovenian', 'sl': 'slovenian',
  'slovak': 'slovak', 'slo': 'slovak', 'slk': 'slovak', 'sk': 'slovak',
  'ukrainian': 'ukrainian', 'ukr': 'ukrainian', 'uk': 'ukrainian',
  // Elsewhere
  'arabic': 'arabic', 'ara': 'arabic', 'ar': 'arabic',
  'hebrew': 'hebrew', 'heb': 'hebrew', 'he': 'hebrew',
  'persian': 'persian', 'farsi': 'persian', 'per': 'persian', 'fas': 'persian', 'fa': 'persian',
  'chinese': 'chinese', 'chi': 'chinese', 'zho': 'chinese', 'chs': 'chinese', 'cht': 'chinese', 'zh': 'chinese',
  'japanese': 'japanese', 'jpn': 'japanese', 'ja': 'japanese',
  'korean': 'korean', 'kor': 'korean', 'ko': 'korean',
  'vietnamese': 'vietnamese', 'vie': 'vietnamese', 'vi': 'vietnamese',
  'indonesian': 'indonesian', 'ind': 'indonesian', 'id': 'indonesian',
  'thai': 'thai', 'tha': 'thai', 'th': 'thai',
};

/// The language [code] (two or three letters, either ISO 639-2 form) names,
/// or null when it is not one of the known ones.
String? languageOfCode(String? code) {
  if (code == null) return null;
  final head = code.toLowerCase().split(RegExp('[-_:]')).first;
  return _codes[head];
}

/// What in a release name says a language: the names, and the tags that are
/// not also ordinary words in a title. Two-letter codes and short codes like
/// "dan", "rum", "por" or "per" are words too ("La Cite de la peur", "Es",
/// "Dan in Real Life", "The Rum Diary"); a code only counts right before the
/// file's extension, below.
const Set<String> _nameWords = {
  'english', 'german', 'deutsch', 'ger', 'dutch', 'nederlands', 'flemish', 'french', 'francais', 'français',
  'vostfr', 'vff', 'truefrench', 'spanish', 'espanol', 'español', 'castellano', 'latino', 'italian', 'italiano',
  'ita', 'portuguese', 'portugues', 'português', 'brazilian', 'ptbr', 'turkish', 'turkce', 'türkçe', 'polish',
  'polski', 'russian', 'rus', 'swedish', 'svenska', 'swe', 'danish', 'dansk', 'norwegian', 'norsk', 'finnish',
  'suomi', 'czech', 'cze', 'hungarian', 'magyar', 'romanian', 'greek', 'croatian', 'hrvatski', 'serbian', 'srpski',
  'bulgarian', 'slovenian', 'slovak', 'ukrainian', 'ukr', 'arabic', 'hebrew', 'heb', 'persian', 'farsi', 'chinese',
  'japanese', 'jpn', 'korean', 'kor', 'vietnamese', 'indonesian', 'thai',
};

/// A language code right before a subtitle file's extension, after any
/// forced or hearing-impaired mark: "Film.2008.de.srt", "Film.tur.forced.srt".
final RegExp _codeBeforeExtension =
    RegExp(r'[._ ]([a-z]{2,3}(?:-[a-z]{2})?)(?:[._ ](?:forced|sdh|hi|cc))*\.(?:srt|ass|ssa|sub|vtt|smi)$');

/// The other language a release name speaks of, when searching for
/// [wantedCode]: null when it names none, names the one wanted too, or the
/// wanted language is not one this knows.
String? otherLanguageNamed(Iterable<String?> names, String wantedCode) {
  final wanted = languageOfCode(wantedCode);
  if (wanted == null) return null;
  final named = <String>{};
  for (final name in names) {
    if (name == null || name.isEmpty) continue;
    final lower = name.toLowerCase();
    for (final word in lower.split(RegExp(r"[\s._\-\[\]()+,]+"))) {
      if (_nameWords.contains(word)) named.add(_codes[word]!);
    }
    final code = _codeBeforeExtension.firstMatch(lower)?.group(1);
    final ofCode = languageOfCode(code);
    if (ofCode != null) named.add(ofCode);
  }
  if (named.isEmpty || named.contains(wanted)) return null;
  return named.first;
}

/// Whether a result stated to be in [statedCode] can be in [wantedCode]: an
/// unknown or missing stated language is given the benefit of the doubt.
bool statedLanguageFits(String? statedCode, String wantedCode) {
  final stated = languageOfCode(statedCode);
  final wanted = languageOfCode(wantedCode);
  return stated == null || wanted == null || stated == wanted;
}

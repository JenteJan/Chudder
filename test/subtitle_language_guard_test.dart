// What an English search keeps and leaves out by name and stated language.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/subtitle_language_guard.dart';

void main() {
  test('names that say another language are caught', () {
    expect(otherLanguageNamed(['Step.Brothers.2008.German.DL.1080p.BluRay.x264-DETAiLS'], 'eng'), 'german');
    expect(otherLanguageNamed(['Step Brothers (2008) Türkçe Altyazı'], 'eng'), 'turkish');
    expect(otherLanguageNamed(['Step.Brothers.2008.VOSTFR.720p'], 'eng'), 'french');
    expect(otherLanguageNamed(['Step.Brothers.2008.1080p.BluRay.de.srt'], 'eng'), 'german');
    expect(otherLanguageNamed(['Step.Brothers.2008.tur.forced.srt'], 'eng'), 'turkish');
    expect(otherLanguageNamed(['Step.Brothers.2008.en.srt'], 'eng'), isNull);
    expect(otherLanguageNamed(['Stiefbrüder 2008 [GER]'], 'en'), 'german');
  });

  test('names that say nothing, or also the wanted language, are kept', () {
    expect(otherLanguageNamed(['Step.Brothers.2008.1080p.BluRay.x264-SPARKS'], 'eng'), isNull);
    expect(otherLanguageNamed(['Step.Brothers.2008.German.English.DL.1080p'], 'eng'), isNull);
    expect(otherLanguageNamed(['Step.Brothers.2008.UNRATED.720p.BluRay.x264-Felony'], 'eng'), isNull);
    expect(otherLanguageNamed([null, ''], 'eng'), isNull);
    // Words that only look like codes stay words in a title.
    expect(otherLanguageNamed(['Is.It.Love.No.Way.2008.720p'], 'eng'), isNull);
    expect(otherLanguageNamed(['La.Cite.de.la.Peur.1994.1080p'], 'eng'), isNull);
    expect(otherLanguageNamed(['Dan.in.Real.Life.2007.720p'], 'eng'), isNull);
    expect(otherLanguageNamed(['The.Rum.Diary.2011.1080p'], 'eng'), isNull);
    expect(otherLanguageNamed(['Es.2017.German.DL'], 'ger'), isNull);
    expect(otherLanguageNamed(['Step.Brothers.UK.Edition.2008'], 'eng'), isNull);
  });

  test('searching German, a German name is what was asked for', () {
    expect(otherLanguageNamed(['Step.Brothers.2008.German.DL.1080p'], 'ger'), isNull);
    expect(otherLanguageNamed(['Step.Brothers.2008.German.DL.1080p'], 'deu'), isNull);
    expect(otherLanguageNamed(['Step.Brothers.2008.English.1080p'], 'ger'), 'english');
  });

  test('stated languages are compared across both ISO forms', () {
    expect(statedLanguageFits('eng', 'eng'), isTrue);
    expect(statedLanguageFits('en', 'eng'), isTrue);
    expect(statedLanguageFits('ger', 'deu'), isTrue);
    expect(statedLanguageFits('tur', 'eng'), isFalse);
    expect(statedLanguageFits(null, 'eng'), isTrue);
    expect(statedLanguageFits('xyz', 'eng'), isTrue);
  });
}

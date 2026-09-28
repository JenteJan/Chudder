import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/subtitle_match.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';

void main() {
  test('shift_offset carries the sign on every part, as Bazarr parses it', () {
    expect(BazarrClient.shiftAction(const Duration(milliseconds: -1250)), 'shift_offset(h=0,m=0,s=-1,ms=-250)');
    expect(BazarrClient.shiftAction(const Duration(minutes: 1, seconds: 2, milliseconds: 5)),
        'shift_offset(h=0,m=1,s=2,ms=5)');
  });

  test('change_FPS writes whole rates without decimals', () {
    expect(BazarrClient.frameRateAction(25, 23.976), 'change_FPS(from=25,to=23.976)');
  });

  test('a manual search result reads Bazarr\'s string booleans and field names', () {
    final result = BazarrResult.fromJson({
      'score': 94,
      'orig_score': 170,
      'language': 'en',
      'forced': 'False',
      'hearing_impaired': 'True',
      'provider': 'opensubtitlescom',
      'subtitle': 'abc-token',
      'original_format': null,
      'matches': ['title', 'year', 'source', 'release_group', 'hearing_impaired'],
      'dont_matches': ['edition', 'audio_codec'],
      'release_info': ['Movie.2019.1080p.BluRay.x264-GRP', ''],
      'uploader': 'someone',
    });
    expect(result.hearingImpaired, isTrue);
    expect(result.forced, isFalse);
    expect(result.originalFormat, isFalse);
    expect(result.score, 94);
    expect(result.releases, ['Movie.2019.1080p.BluRay.x264-GRP']);
    expect(BazarrResult.fields(result.matches),
        {MatchField.year, MatchField.source, MatchField.releaseGroup, MatchField.hearingImpaired});
    expect(BazarrResult.fields(result.dontMatches), {MatchField.edition, MatchField.audioCodec});
  });

  test('a subtitle file Bazarr lists is found by its file name', () {
    final movie = BazarrMovie.fromJson({
      'radarrId': 7,
      'subtitles': [
        {'code2': 'en', 'path': '/data/movies/X/X.en.srt', 'forced': false, 'hi': false},
        {'code2': 'nl', 'path': null},
      ],
    });
    expect(movie.fileNamed('X.en.srt')?.code2, 'en');
    expect(movie.fileNamed('X.nl.srt'), isNull);
  });
}

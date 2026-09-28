import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/release_info.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';

SubtitleCandidate _sub(String? release, {double? fps, bool hash = false, int downloads = 0, bool machine = false}) =>
    SubtitleCandidate(
      key: release ?? 'none',
      source: SubtitleSourceKind.jellyfin,
      provider: 'OpenSubtitles',
      language: 'eng',
      payload: release ?? '',
      releaseName: release,
      frameRate: fps,
      hashMatch: hash,
      downloads: downloads,
      machineTranslated: machine,
    );

void main() {
  group('ReleaseInfo.parse', () {
    test('reads a scene episode release', () {
      final info = ReleaseInfo.parse('The.Bear.S02E03.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb');
      expect(info.season, 2);
      expect(info.episodes, [3]);
      expect(info.resolution, '1080p');
      expect(info.source, ReleaseSource.web);
      expect(info.streamingService, 'Disney+');
      expect(info.audioCodec, 'Dolby Digital Plus');
      expect(info.videoCodec, 'H.264');
      expect(info.releaseGroup, 'NTb');
    });

    test('reads a movie release with a year and a bracketed site tag', () {
      final info = ReleaseInfo.parse('Blade.Runner.1982.Final.Cut.1080p.BluRay.x264.DTS-HD.MA.5.1-FGT[rarbg]');
      expect(info.year, 1982);
      expect(info.source, ReleaseSource.bluRay);
      expect(info.videoCodec, 'H.264');
      expect(info.audioCodec, 'DTS');
      expect(info.edition, 'Final Cut');
      expect(info.releaseGroup, 'FGT');
      expect(info.streamingService, isNull, reason: 'DTS-HD.MA is not Movies Anywhere');
    });

    test('takes the file name from a path and drops the extension', () {
      final info = ReleaseInfo.parse('/media/tv/Show/Season 1/Show.S01E02.720p.HDTV.x265-MiNX.mkv');
      expect(info.season, 1);
      expect(info.episodes, [2]);
      expect(info.source, ReleaseSource.hdtv);
      expect(info.videoCodec, 'H.265');
      expect(info.releaseGroup, 'MiNX');
    });

    test('a renamed library file says little, and nothing wrong', () {
      final info = ReleaseInfo.parse('/media/movies/Sintel (2010)/Sintel (2010).mp4');
      expect(info.year, 2010);
      expect(info.releaseGroup, isNull);
      expect(info.source, isNull);
      expect(info.describesRelease, isFalse);
    });

    test('WEB-DL is a source, not a group', () {
      expect(ReleaseInfo.parse('Movie.2020.1080p.WEB-DL').releaseGroup, isNull);
      expect(ReleaseInfo.parse('Movie.2020.1080p.WEB-DL').source, ReleaseSource.web);
    });

    test('episode ranges, 1x02 and season packs', () {
      expect(ReleaseInfo.parse('Show.S01E01-E03.720p').episodes, [1, 2, 3]);
      expect(ReleaseInfo.parse('Show.S01E01E02.720p').episodes, [1, 2]);
      final cross = ReleaseInfo.parse('Show 3x07 HDTV');
      expect(cross.season, 3);
      expect(cross.episodes, [7]);
      final pack = ReleaseInfo.parse('Show.S04.COMPLETE.1080p.BluRay');
      expect(pack.season, 4);
      expect(pack.episodes, isEmpty);
    });

    test('hearing impaired marks', () {
      expect(ReleaseInfo.parse('Movie.2019.1080p.BluRay.x264-GRP.HI').hearingImpaired, isTrue);
      expect(ReleaseInfo.parse('Movie.2019.SDH.eng').hearingImpaired, isTrue);
      expect(ReleaseInfo.parse('Movie.2019.1080p').hearingImpaired, isFalse);
    });

    test('the last year wins', () {
      expect(ReleaseInfo.parse('2001.A.Space.Odyssey.1968.1080p.BluRay').year, 1968);
    });
  });

  group('scoreSubtitle', () {
    final episodeTarget = SubtitleTarget(
      isEpisode: true,
      season: 2,
      episode: 3,
      year: 2023,
      release: ReleaseInfo.parse('The.Bear.S02E03.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb.mkv'),
      nameDescribesRelease: true,
      frameRate: 23.976,
    );

    test('the same release is a release match near the top of the scale', () {
      final match = scoreSubtitle(_sub('The.Bear.S02E03.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb'), episodeTarget);
      expect(match.verdict, MatchVerdict.release);
      expect(match.matched, containsAll([MatchField.releaseGroup, MatchField.source, MatchField.resolution]));
      expect(match.percent, greaterThan(99));
      expect(match.mismatched, isEmpty);
    });

    test('another episode will not fit whatever else matches', () {
      final match = scoreSubtitle(_sub('The.Bear.S02E04.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb'), episodeTarget);
      expect(match.verdict, MatchVerdict.unlikely);
      expect(match.mismatched[MatchField.episode], ('S02E04', 'S02E03'));
    });

    test('a different frame rate will not fit', () {
      final match = scoreSubtitle(_sub('The.Bear.S02E03.720p.HDTV.x264-GRP', fps: 25), episodeTarget);
      expect(match.verdict, MatchVerdict.unlikely);
      expect(match.mismatched[MatchField.frameRate], ('25', '23.976'));
      final close = scoreSubtitle(_sub('The.Bear.S02E03.1080p.WEB-DL', fps: 24), episodeTarget);
      expect(close.verdict, isNot(MatchVerdict.unlikely));
    });

    test('a hash match wins even without a release name', () {
      final match = scoreSubtitle(_sub(null, hash: true), episodeTarget);
      expect(match.verdict, MatchVerdict.exact);
      expect(match.percent, 100);
    });

    test('a movie from another year is another film', () {
      const target = SubtitleTarget(isEpisode: false, year: 2019);
      final match = scoreSubtitle(_sub('Little.Women.1994.DVDRip.XviD'), target);
      expect(match.verdict, MatchVerdict.unlikely);
      expect(scoreSubtitle(_sub('Little.Women.2020.1080p.WEB'), target).verdict, isNot(MatchVerdict.unlikely),
          reason: 'one year of slack for release years');
    });

    test('an Extended subtitle does not fit a theatrical file', () {
      final target = SubtitleTarget(
          isEpisode: false, year: 2001, release: ReleaseInfo.parse('LOTR.2001.Theatrical.1080p.BluRay.x264-GRP'));
      expect(scoreSubtitle(_sub('LOTR.2001.Extended.1080p.BluRay.x264-GRP'), target).verdict, MatchVerdict.unlikely);
    });

    test('ordering: fits first, then score, then downloads', () {
      final matches = [
        scoreSubtitle(_sub('The.Bear.S02E04.1080p.WEB-DL-NTb', downloads: 90000), episodeTarget),
        scoreSubtitle(_sub('The.Bear.S02E03.720p.HDTV.x264-GRP', downloads: 50), episodeTarget),
        scoreSubtitle(_sub('The.Bear.S02E03.1080p.WEB-DL.H.264-NTb', downloads: 10), episodeTarget),
        scoreSubtitle(_sub('The.Bear.S02E03.720p.HDTV.x264-OTHER', downloads: 500), episodeTarget),
      ]..sort(compareMatches);
      expect(matches.map((m) => m.candidate.downloads), [10, 500, 50, 90000]);
    });

    test('machine translations sort below an equal human one', () {
      final matches = [
        scoreSubtitle(_sub('The.Bear.S02E03.1080p.WEB-DL-NTb', machine: true, downloads: 900), episodeTarget),
        scoreSubtitle(_sub('The.Bear.S02E03.1080p.WEB-DL-NTb', downloads: 3), episodeTarget),
      ]..sort(compareMatches);
      expect(matches.first.candidate.machineTranslated, isFalse);
    });

    test('no fit number when the file says nothing to compare against', () {
      const target = SubtitleTarget(isEpisode: false, year: 2010);
      expect(scoreSubtitle(_sub('Sintel.2010.1080p.BluRay.x264-GRP'), target).percent, isNull);
    });

    test('the fit counts only what the file states, and what the subtitle leaves out counts against it', () {
      final bare = scoreSubtitle(_sub('The Bear'), episodeTarget);
      final sameSource = scoreSubtitle(_sub('The.Bear.S02E03.1080p.WEB.h264-ETHEL'), episodeTarget);
      expect(bare.percent, 0);
      expect(sameSource.percent, greaterThan(bare.percent!));
      expect(sameSource.percent, lessThan(100));
    });

    test('a deal-breaker never shows a high fit', () {
      final wrong = scoreSubtitle(_sub('The.Bear.S02E04.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb'), episodeTarget);
      expect(wrong.percent, lessThanOrEqualTo(SubtitleFitWeights.unlikelyCeiling));
    });

    test('best of the releases the uploader says it fits', () {
      const candidate = SubtitleCandidate(
        key: 'k',
        source: SubtitleSourceKind.jellyfin,
        provider: 'p',
        language: 'eng',
        payload: '',
        releaseName: 'The.Bear.S02E03.720p.HDTV.x264-GRP',
        otherReleases: ['The.Bear.S02E03.1080p.DSNP.WEB-DL.DDP5.1.H.264-NTb'],
      );
      final match = scoreSubtitle(candidate, episodeTarget);
      expect(match.verdict, MatchVerdict.release);
      expect(match.scoredRelease, contains('NTb'));
    });
  });
}

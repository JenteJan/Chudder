import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

SubStreamModel _sub(
  int index, {
  bool isExternal = false,
  String? url,
  String codec = 'subrip',
  String language = 'eng',
  String title = '',
}) =>
    SubStreamModel(
      name: 'Subtitle $index',
      id: 'id-$index',
      title: title,
      displayTitle: 'Subtitle $index',
      language: language,
      url: url,
      codec: codec,
      isDefault: false,
      isExternal: isExternal,
      index: index,
    );

/// The list the pickers hand to the players: the 'Off' entry, then the
/// server's streams with its subtitle files last.
List<SubStreamModel> _list(List<SubStreamModel> streams) => [SubStreamModel.no(), ...streams];

void main() {
  group('resolveSubtitlePick', () {
    test('picks a track by its position among the container\'s own streams', () {
      final streams = _list([_sub(2), _sub(3), _sub(4)]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[3], playerTrackCount: 3),
        const SubtitlePick.track(2),
      );
    });

    test('subtitle files do not take up a track position', () {
      // The server lists its files after the container's streams, but a file
      // ahead of a track in the list used to push that track's position up.
      final streams = _list([
        _sub(2, isExternal: true, url: 'http://server/2.srt'),
        _sub(3),
        _sub(4),
      ]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[3], playerTrackCount: 2),
        const SubtitlePick.track(1),
      );
    });

    test('a subtitle file is loaded from the server, never counted as a track', () {
      final streams = _list([_sub(2), _sub(3), _sub(4, isExternal: true, url: 'http://server/4.srt')]);
      // Two container tracks plus the file loaded a moment ago: the stale
      // position used to find that loaded file and select the wrong subtitle.
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[3], playerTrackCount: 3),
        const SubtitlePick.file(),
      );
    });

    test('falls back to the server file when the stream holds fewer tracks than the server listed', () {
      // A transcode drops subtitle tracks; counting positions in what is left
      // lands on the wrong one, so the subtitle is fetched instead.
      final streams = _list([
        _sub(2, url: 'http://server/2.srt'),
        _sub(3, url: 'http://server/3.srt'),
        _sub(4, url: 'http://server/4.srt'),
      ]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[3], playerTrackCount: 0),
        const SubtitlePick.file(),
      );
    });

    test('guesses at the position when the counts disagree and there is no file to load', () {
      final streams = _list([_sub(2), _sub(3), _sub(4)]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[1], playerTrackCount: 2),
        const SubtitlePick.track(0),
      );
    });

    test('gives up when the track is not in the stream and there is no file', () {
      final streams = _list([_sub(2), _sub(3), _sub(4)]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: streams[3], playerTrackCount: 0),
        const SubtitlePick.none(),
      );
    });

    test('a stream that was listed again is still found', () {
      // A re-listing rebuilds the models, so the pick has to survive the
      // identity of the objects changing.
      final streams = _list([_sub(2), _sub(3), _sub(4)]);
      expect(
        resolveSubtitlePick(streams: streams, wanted: _sub(4), playerTrackCount: 3),
        const SubtitlePick.track(2),
      );
    });

    test('every stream in a long mixed list maps to its own track or file', () {
      final container = List.generate(8, (i) => _sub(2 + i));
      final files = List.generate(4, (i) => _sub(10 + i, isExternal: true, url: 'http://server/${10 + i}.srt'));
      final streams = _list([...container, ...files]);

      for (var i = 0; i < container.length; i++) {
        expect(
          resolveSubtitlePick(streams: streams, wanted: container[i], playerTrackCount: container.length),
          SubtitlePick.track(i),
          reason: 'container stream ${container[i].index}',
        );
      }
      for (final file in files) {
        expect(
          resolveSubtitlePick(streams: streams, wanted: file, playerTrackCount: container.length),
          const SubtitlePick.file(),
          reason: 'subtitle file ${file.index}',
        );
      }
    });
  });

  group('matchSubtitleTrack', () {
    PlayerSubtitleTrack track(String language, [String title = '']) =>
        PlayerSubtitleTrack(language: language, title: title);

    test('finds the track wherever the player put it in its own list', () {
      final container = [
        _sub(4, language: 'eng', title: 'SDH'),
        _sub(5, language: 'swe'),
        _sub(6, language: 'spa'),
      ];
      // The player lists the same three the other way round.
      final tracks = [track('spa'), track('swe'), track('eng', 'SDH')];
      expect(matchSubtitleTrack(container: container, wanted: container[0], tracks: tracks), 2);
      expect(matchSubtitleTrack(container: container, wanted: container[2], tracks: tracks), 0);
    });

    test('agrees with counting when the two lists are in the same order', () {
      final container = [_sub(4, language: 'eng'), _sub(5, language: 'swe'), _sub(6, language: 'spa')];
      final tracks = [track('eng'), track('swe'), track('spa')];
      for (var i = 0; i < container.length; i++) {
        expect(matchSubtitleTrack(container: container, wanted: container[i], tracks: tracks), i);
      }
    });

    test('tells tracks that share a language and title apart by their order', () {
      final container = [
        _sub(4, language: 'eng'),
        _sub(5, language: 'eng'),
        _sub(6, language: 'eng'),
      ];
      final tracks = [track('eng'), track('eng'), track('eng')];
      expect(matchSubtitleTrack(container: container, wanted: container[1], tracks: tracks), 1);
      expect(matchSubtitleTrack(container: container, wanted: container[2], tracks: tracks), 2);
    });

    test('a title separates two tracks of one language', () {
      final container = [
        _sub(4, language: 'eng', title: 'SDH'),
        _sub(5, language: 'eng', title: 'Forced'),
      ];
      final tracks = [track('eng', 'Forced'), track('eng', 'SDH')];
      expect(matchSubtitleTrack(container: container, wanted: container[0], tracks: tracks), 1);
      expect(matchSubtitleTrack(container: container, wanted: container[1], tracks: tracks), 0);
    });

    test('gives up when the stream says nothing to match on', () {
      final container = [_sub(4, language: 'und'), _sub(5, language: 'und')];
      expect(matchSubtitleTrack(container: container, wanted: container[0], tracks: [track('eng')]), isNull);
    });

    test('gives up when the player has nothing that matches', () {
      final container = [_sub(4, language: 'eng')];
      expect(matchSubtitleTrack(container: container, wanted: container[0], tracks: [track('swe')]), isNull);
    });
  });

  group('the list a player really hands back', () {
    // Obsession, as the server lists it and as mpv listed it: eighteen tracks
    // in the file, and the English subtitle file the server marks as default
    // sitting at the FRONT of mpv's list, because it is loaded while mpv is
    // still opening the stream.
    const serverList = [
      ['eng', 'SDH / Positional / PGS'],
      ['eng', ''],
      ['eng', 'SDH'],
      ['dan', ''],
      ['nld', ''],
      ['fin', ''],
      ['fra', 'Canadian'],
      ['fra', 'Canadian / PGS'],
      ['fra', 'Metropolitan'],
      ['deu', ''],
      ['hin', ''],
      ['ita', ''],
      ['nor', ''],
      ['pol', ''],
      ['por', 'Brazilian'],
      ['spa', 'Latin American'],
      ['spa', 'Latin American / PGS'],
      ['swe', ''],
    ];
    const playerList = [
      ['en-US', 'SDH / Positional / PGS'],
      ['en-US', null],
      ['en-US', 'SDH'],
      ['da', null],
      ['nl', null],
      ['fi', null],
      ['fr-CA', 'Canadian'],
      ['fr-CA', 'Canadian / PGS'],
      ['fr-FR', 'Metropolitan'],
      ['de', null],
      ['hi', null],
      ['it', null],
      ['no', null],
      ['pl', null],
      ['pt-BR', 'Brazilian'],
      ['es-419', 'Latin American'],
      ['es-419', 'Latin American / PGS'],
      ['sv', null],
    ];

    List<SubStreamModel> serverStreams() => [
          for (var i = 0; i < serverList.length; i++)
            _sub(4 + i, language: serverList[i][0], title: serverList[i][1]),
        ];

    /// mpv's list: its two pseudo tracks, then the loaded file, then the
    /// media file's own tracks.
    List<(String, String?)> mpvTracks() => [
          ('auto', null),
          ('no', null),
          ('auto', '${loadedSubtitlePrefix}0'),
          for (final track in playerList) (track[0]!, track[1]),
        ];

    test('a loaded subtitle file at the front does not displace the file\'s own tracks', () {
      final tracks = withoutLoadedSubtitles(mpvTracks().sublist(2), (track) => track.$2);
      expect(tracks.length, serverList.length);
      // The last one used to fall off the end of the list entirely.
      expect(tracks.last.$1, 'sv');
    });

    test('every entry lands on its own track', () {
      final container = serverStreams();
      final tracks = withoutLoadedSubtitles(mpvTracks().sublist(2), (track) => track.$2)
          .map((track) => PlayerSubtitleTrack(language: track.$1, title: track.$2 ?? ''))
          .toList();

      for (var i = 0; i < container.length; i++) {
        expect(
          matchSubtitleTrack(container: container, wanted: container[i], tracks: tracks),
          i,
          reason: '${container[i].language} "${container[i].title}"',
        );
      }
    });

    test('Danish is Danish and Swedish is Swedish', () {
      final container = serverStreams();
      final tracks = withoutLoadedSubtitles(mpvTracks().sublist(2), (track) => track.$2)
          .map((track) => PlayerSubtitleTrack(language: track.$1, title: track.$2 ?? ''))
          .toList();
      // Danish used to play the English SDH track one place above it, and
      // Swedish nothing at all.
      final danish = container.firstWhere((stream) => stream.language == 'dan');
      final swedish = container.firstWhere((stream) => stream.language == 'swe');
      expect(tracks[matchSubtitleTrack(container: container, wanted: danish, tracks: tracks)!].language, 'da');
      expect(tracks[matchSubtitleTrack(container: container, wanted: swedish, tracks: tracks)!].language, 'sv');
    });
  });

  group('language names', () {
    test('the server\'s three letters and the player\'s tag are the same language', () {
      const pairs = {'eng': 'en-US', 'swe': 'sv', 'spa': 'es-419', 'nld': 'nl', 'por': 'pt-BR', 'deu': 'de'};
      for (final pair in pairs.entries) {
        final container = [_sub(4, language: pair.key)];
        expect(
          matchSubtitleTrack(
            container: container,
            wanted: container.first,
            tracks: [PlayerSubtitleTrack(language: pair.value)],
          ),
          0,
          reason: '${pair.key} / ${pair.value}',
        );
      }
    });

    test('two different languages are not confused', () {
      final container = [_sub(4, language: 'swe')];
      expect(
        matchSubtitleTrack(
          container: container,
          wanted: container.first,
          tracks: [const PlayerSubtitleTrack(language: 'sw')],
        ),
        isNull,
      );
    });
  });

  group('containerSubtitleStreams', () {
    test('leaves out the Off entry and the server\'s files', () {
      final streams = _list([_sub(2), _sub(3, isExternal: true, url: 'http://server/3.srt')]);
      expect(containerSubtitleStreams(streams).map((e) => e.index), [2]);
    });

    test('is empty for a null list', () {
      expect(containerSubtitleStreams(null), isEmpty);
    });
  });
}

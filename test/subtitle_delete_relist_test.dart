import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';

SubStreamModel _sub({
  required int index,
  required String language,
  String? path,
  bool isExternal = true,
  String codec = 'subrip',
}) =>
    SubStreamModel(
      name: '',
      id: 'sub$index',
      title: '',
      displayTitle: '${language.toUpperCase()} - SUBRIP - External',
      language: language,
      path: path,
      codec: codec,
      isDefault: false,
      isExternal: isExternal,
      index: index,
    );

MediaStreamsModel _streams(List<SubStreamModel> subStreams, {int? selected}) => MediaStreamsModel(
      defaultAudioStreamIndex: 1,
      defaultSubStreamIndex: selected,
      versionStreams: [
        VersionStreamModel(
          name: 'main',
          index: 0,
          id: 'source',
          defaultAudioStreamIndex: 1,
          defaultSubStreamIndex: selected,
          videoStreams: const [],
          audioStreams: const [],
          subStreams: subStreams,
        ),
      ],
    );

DirectPlaybackModel _model(MediaStreamsModel streams) => DirectPlaybackModel(
      item: MovieModel(
        originalTitle: 'Spoorloos',
        premiereDate: DateTime(1988),
        sortName: 'Spoorloos',
        status: '',
        name: 'Spoorloos',
        id: 'movie',
        overview: const OverviewModel(),
        userData: const UserData(),
        parentId: null,
        playlistId: null,
        images: null,
        childCount: null,
        primaryRatio: null,
        parentImages: null,
        mediaStreams: streams,
        canDownload: null,
        canDelete: null,
      ),
      media: const Media(url: 'stream'),
      mediaStreams: streams,
    );

void main() {
  group('fileName', () {
    test('is the file itself, from either kind of path', () {
      expect(_sub(index: 3, language: 'eng', path: r'\\media\Movies\Spoorloos\Spoorloos.eng.srt').fileName,
          'Spoorloos.eng.srt');
      expect(_sub(index: 3, language: 'eng', path: '/media/Movies/Spoorloos/Spoorloos.eng.2.srt').fileName,
          'Spoorloos.eng.2.srt');
    });

    test('is empty for a track inside the container', () {
      expect(_sub(index: 2, language: 'eng', isExternal: false).fileName, '');
    });
  });

  group('replaceSubtitles after a delete', () {
    // Three downloads of one language: the same display title three times,
    // which is why the file name is what a row is found by.
    final before = [
      _sub(index: 3, language: 'eng', path: '/media/Spoorloos.eng.srt'),
      _sub(index: 4, language: 'eng', path: '/media/Spoorloos.eng.2.srt'),
      _sub(index: 5, language: 'eng', path: '/media/Spoorloos.eng.3.srt'),
    ];
    // The server renumbers what is left when its refresh lands.
    final after = [
      _sub(index: 3, language: 'eng', path: '/media/Spoorloos.eng.2.srt'),
      _sub(index: 4, language: 'eng', path: '/media/Spoorloos.eng.3.srt'),
    ];

    test('the playing file keeps playing under its new number', () {
      final model = _model(_streams(before, selected: 5));
      expect(model.mediaStreams?.currentSubStream?.fileName, 'Spoorloos.eng.3.srt');

      final relisted = model.replaceSubtitles(after, selectedIndex: 4);

      expect(relisted.mediaStreams?.defaultSubStreamIndex, 4);
      expect(relisted.mediaStreams?.currentSubStream?.fileName, 'Spoorloos.eng.3.srt');
    });

    test('without a new number the selection is left alone', () {
      final model = _model(_streams(before, selected: 3));

      final relisted = model.replaceSubtitles(after);

      expect(relisted.mediaStreams?.defaultSubStreamIndex, 3);
      // The model's own list carries an "off" entry ahead of the files.
      expect(relisted.mediaStreams?.subStreams.length, 2);
      expect(relisted.subStreams?.length, 3);
    });

    test('the deleted file is gone from the list', () {
      final relisted = _model(_streams(before, selected: 5)).replaceSubtitles(after, selectedIndex: 4);

      expect(relisted.subStreams?.map((sub) => sub.fileName), isNot(contains('Spoorloos.eng.srt')));
    });
  });
}

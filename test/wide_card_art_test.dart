import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';

ImageData _image(String key, {String hash = ''}) => ImageData(path: 'http://server/$key', key: key, hash: hash);

EpisodeModel _episode({
  ImagesData? images,
  ImagesData? showImages,
}) =>
    EpisodeModel(
      seriesName: 'Show',
      season: 1,
      episode: 2,
      episodeEnd: null,
      name: 'Episode',
      id: 'episode',
      overview: const OverviewModel(),
      parentId: 'show',
      playlistId: null,
      images: images,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: showImages,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

MovieModel _movie({
  ImagesData? images,
}) =>
    MovieModel(
      originalTitle: 'Film',
      premiereDate: DateTime(2000),
      sortName: 'Film',
      status: '',
      name: 'Film',
      id: 'film',
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: images,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: images,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

void main() {
  final showImages = ImagesData(
    primary: _image('show-poster'),
    backDrop: [_image('show-backdrop')],
    thumb: _image('show-thumb'),
  );

  group('WideCardArt.of, for cards in a row', () {
    test("an episode shows its show's landscape art before its own still", () {
      final art = WideCardArt.of(_episode(images: ImagesData(primary: _image('still')), showImages: showImages));
      expect(art.still?.key, 'show-thumb');
      expect(art.poster?.key, 'show-poster');
    });

    test('an episode without landscape art shows its still, then the show backdrop', () {
      final noThumb = ImagesData(primary: _image('show-poster'), backDrop: [_image('show-backdrop')]);
      expect(WideCardArt.of(_episode(images: ImagesData(primary: _image('still')), showImages: noThumb)).still?.key,
          'still');
      expect(WideCardArt.of(_episode(showImages: noThumb)).still?.key, 'show-backdrop');
    });

    test('a film shows its landscape art, then its backdrop, then its poster whole', () {
      expect(WideCardArt.of(_movie(images: showImages)).still?.key, 'show-thumb');
      expect(
        WideCardArt.of(_movie(images: ImagesData(primary: _image('poster'), backDrop: [_image('backdrop')])))
            .still
            ?.key,
        'backdrop',
      );
      final bare = WideCardArt.of(_movie(images: ImagesData(primary: _image('poster'))));
      expect(bare.still, isNull);
      expect(bare.poster?.key, 'poster');
    });
  });

  group('WideCardArt.large, for banners with the title written over them', () {
    test('takes the backdrop before any art with a title of its own', () {
      expect(WideCardArt.large(_movie(images: showImages)).still?.key, 'show-backdrop');
      expect(
        WideCardArt.large(_episode(images: ImagesData(primary: _image('still')), showImages: showImages)).still?.key,
        'show-backdrop',
      );
    });

    test('an episode without backdrops shows its still', () {
      expect(
        WideCardArt.large(
          _episode(images: ImagesData(primary: _image('still')), showImages: ImagesData(thumb: _image('show-thumb'))),
        ).still?.key,
        'still',
      );
    });
  });
}

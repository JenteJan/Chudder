import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/recommended_model.dart';
import 'package:chudder/util/continue_row.dart';

EpisodeModel _episode(String id, String show, {DateTime? lastPlayed}) => EpisodeModel(
      seriesName: show,
      season: 1,
      episode: 1,
      episodeEnd: null,
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: show,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: UserData(lastPlayed: lastPlayed),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

MovieModel _movie(String id, {DateTime? lastPlayed}) => MovieModel(
      originalTitle: id,
      premiereDate: DateTime(2000),
      sortName: id,
      status: '',
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: UserData(lastPlayed: lastPlayed),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

List<String> _ids(List<ItemBaseModel> items) => items.map((item) => item.id).toList();

void main() {
  // Next up asked with enableResumable: the episode you are in the middle of,
  // and the one after the one you finished.
  final midway = _episode('show-a-e2', 'show-a', lastPlayed: DateTime(2026, 9, 10));
  final following = _episode('show-b-e5', 'show-b');
  final film = _movie('film', lastPlayed: DateTime(2026, 9, 12));
  final nextUp = <ItemBaseModel>[midway, following];
  final resume = <ItemBaseModel>[film, midway];

  group('libraryContinueRows', () {
    final rows = [
      RecommendedModel(name: const Continue(), posters: resume),
      RecommendedModel(name: const NextUp(), posters: nextUp),
      RecommendedModel(name: const Latest(), posters: [_movie('new')]),
    ];

    test('combined, one row in the place of both, films and episodes together', () {
      final result = libraryContinueRows(rows, combine: true);
      expect(result.map((row) => row.name.runtimeType), [Continue, Latest]);
      expect(_ids(result.first.posters), ['film', 'show-a-e2', 'show-b-e5']);
    });

    test('split, Next up leaves out what Continue already has', () {
      final result = libraryContinueRows(rows, combine: false);
      expect(result.map((row) => row.name.runtimeType), [Continue, NextUp, Latest]);
      expect(_ids(result[0].posters), ['film', 'show-a-e2']);
      expect(_ids(result[1].posters), ['show-b-e5']);
    });

    test('combined without anything to resume is still the one row', () {
      final result = libraryContinueRows([
        RecommendedModel(name: const NextUp(), posters: [following]),
      ], combine: true);
      expect(result.single.name, isA<Continue>());
      expect(_ids(result.single.posters), ['show-b-e5']);
    });
  });
}

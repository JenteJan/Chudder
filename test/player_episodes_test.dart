import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/video_player/components/video_player_episodes.dart';

MediaStreamsModel _streams() => MediaStreamsModel(versionStreams: const []);

EpisodeModel _episode(String show, int season, int episode) => EpisodeModel(
      seriesName: show,
      season: season,
      episode: episode,
      episodeEnd: null,
      name: '$show S${season}E$episode',
      id: '$show-$season-$episode',
      overview: const OverviewModel(),
      parentId: show,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: _streams(),
      canDownload: null,
      canDelete: null,
    );

MovieModel _movie(String name) => MovieModel(
      originalTitle: name,
      premiereDate: DateTime(2000),
      sortName: name,
      status: '',
      name: name,
      id: name,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: _streams(),
      canDownload: null,
      canDelete: null,
    );

void main() {
  final show = [
    _episode('Show', 1, 1),
    _episode('Show', 1, 2),
    _episode('Show', 2, 1),
  ];

  test('a film has no episodes to browse', () {
    expect(browsableEpisodes(_movie('Film'), [_movie('Film'), ...show]), isEmpty);
  });

  test('an episode browses its whole queue in queue order', () {
    expect(browsableEpisodes(show[1], show).map((e) => e.id), show.map((e) => e.id));
  });

  test('a playlist of several shows only offers the one that is playing', () {
    final other = [_episode('Other', 1, 1), _episode('Other', 1, 2)];
    final queue = [other[0], show[0], _movie('Film'), other[1], show[1]];
    expect(browsableEpisodes(show[0], queue).map((e) => e.id), [show[0].id, show[1].id]);
    expect(browsableEpisodes(other[1], queue).map((e) => e.id), [other[0].id, other[1].id]);
  });

  test('a show of one episode is nowhere to go', () {
    expect(canBrowseEpisodes(null), isFalse);
    expect(browsableEpisodes(show[0], [show[0]]).length, 1);
  });
}

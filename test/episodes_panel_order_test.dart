// The player's episodes panel lists a show in its own order, however the
// queue plays it.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/video_player/components/video_player_episodes.dart';

EpisodeModel _episode(int season, int episode) => EpisodeModel(
      seriesName: 'Show',
      season: season,
      episode: episode,
      episodeEnd: null,
      name: 'S${season}E$episode',
      id: 's${season}e$episode',
      overview: const OverviewModel(),
      parentId: 'show',
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

void main() {
  test('a shuffled queue is listed by season and episode, specials last', () {
    final queue = [_episode(2, 3), _episode(0, 1), _episode(1, 2), _episode(2, 1), _episode(1, 1)];
    final listed = browsableEpisodes(queue.first, queue);
    expect(listed.map((e) => e.name), ['S1E1', 'S1E2', 'S2E1', 'S2E3', 'S0E1']);
  });
}

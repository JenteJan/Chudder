import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/playback_queue_state.dart';
import 'package:chudder/wrappers/players/cast/cast_queue.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';

EpisodeModel _episode(int number) => EpisodeModel(
      seriesName: 'Show',
      season: 1,
      episode: number,
      episodeEnd: null,
      name: 'Episode $number',
      id: 'ep-$number',
      overview: const OverviewModel(),
      parentId: 'season-1',
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

PlaybackModel _playing(int number, List<EpisodeModel> queue) => DirectPlaybackModel(
      item: queue.firstWhere((episode) => episode.episode == number),
      media: const Media(url: 'http://server/stream'),
      queue: queue,
    );

void main() {
  final season = [for (var number = 1; number <= 8; number++) _episode(number)];

  test('the rest of the season follows the episode, in order', () {
    final stubs = upcomingItemStubs(_playing(3, season), serverId: 'server');

    expect(stubs.map((stub) => stub['Id']), ['ep-4', 'ep-5', 'ep-6', 'ep-7', 'ep-8']);
    expect(stubs.first, containsPair('ServerId', 'server'));
    expect(stubs.first, containsPair('MediaType', 'Video'));
    expect(stubs.first, containsPair('IsFolder', false));
  });

  test('the last episode has nothing behind it', () {
    expect(upcomingItemStubs(_playing(8, season), serverId: 'server'), isEmpty);
  });

  test('a long queue is cut to what one message carries', () {
    final long = [for (var number = 1; number <= 200; number++) _episode(number)];

    expect(upcomingItemStubs(_playing(1, long), serverId: 'server'), hasLength(castQueueLimit));
  });

  test('what the user queued to play next comes before the rest', () {
    final model = _playing(3, season).updatePlaybackQueue(
      PlaybackQueueState.fromQueue(season, initialItemId: 'ep-3').addToNextUp([season[7]]),
    );

    expect(upcomingItemStubs(model, serverId: 'server').map((stub) => stub['Id']).take(3), ['ep-8', 'ep-4', 'ep-5']);
  });

  test('the whole queue for a season fits a Cast message with room to spare', () {
    final options = buildPlayNowOptions(
      itemStub: jellyfinItemStub(season.first, serverId: 'server'),
      startPosition: const Duration(minutes: 20),
      upcoming: upcomingItemStubs(_playing(1, [for (var n = 1; n <= 200; n++) _episode(n)]), serverId: 'server'),
      mediaSourceId: 'source',
    );

    expect(options['items'], hasLength(castQueueLimit + 1));
    expect(options.toString().length, lessThan(20 * 1024));
  });
}

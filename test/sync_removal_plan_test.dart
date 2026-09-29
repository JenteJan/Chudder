// What happens to shared music when a download is removed, and what a metadata
// refresh may and may not touch.

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/providers/sync/sync_refresh.dart';
import 'package:chudder/providers/sync/sync_removal_plan.dart';

void main() {
  group('removing a playlist', () {
    // Abbey Road holds a1..a3, the playlist lists a1, a2 and a lone track z1
    // that came down with nothing else of its album.
    final tracks = {'a1', 'a2', 'z1'};
    final albumOf = {'a1': 'abbey', 'a2': 'abbey', 'z1': 'single'};
    final tracksOfAlbum = {
      'abbey': {'a1', 'a2', 'a3'},
      'single': {'z1'},
    };

    MusicRemovalPlan plan(MusicRemovalMode mode, {Map<String, Set<String>> playlists = const {}}) => planMusicRemoval(
          scope: MusicRemovalScope.playlist,
          mode: mode,
          tracks: tracks,
          playlists: {'mine': tracks, ...playlists},
          removedPlaylistId: 'mine',
          albumOf: albumOf,
          tracksOfAlbum: tracksOfAlbum,
        );

    test('keeping the tracks removes none', () {
      final result = plan(MusicRemovalMode.keepAll);
      expect(result.remove, isEmpty);
      expect(result.keep, tracks);
    });

    test('a track of an album that holds more than the playlist lists stays', () {
      final result = plan(MusicRemovalMode.keepShared);
      expect(result.keep, {'a1', 'a2'});
      expect(result.remove, {'z1'});
    });

    test('a track another playlist lists stays', () {
      final result = plan(MusicRemovalMode.keepShared, playlists: {
        'other': {'z1'},
      });
      expect(result.remove, isEmpty);
      expect(result.affectedPlaylists, {'other'});
    });

    test('the playlist being removed never counts as another playlist', () {
      final result = plan(MusicRemovalMode.keepShared);
      expect(result.affectedPlaylists, isEmpty);
    });

    test('removing everything takes every track, shared or not', () {
      final result = plan(MusicRemovalMode.everything);
      expect(result.remove, tracks);
    });
  });

  group('removing an album or artist', () {
    MusicRemovalPlan plan(MusicRemovalMode mode) => planMusicRemoval(
          scope: MusicRemovalScope.library,
          mode: mode,
          tracks: {'a1', 'a2', 'a3'},
          playlists: {
            'road trip': {'a2', 'x9'},
          },
        );

    test('tracks a playlist lists stay when asked to keep what is used', () {
      final result = plan(MusicRemovalMode.keepShared);
      expect(result.keep, {'a2'});
      expect(result.remove, {'a1', 'a3'});
      expect(result.affectedPlaylists, {'road trip'});
    });

    test('everything takes the playlist tracks too, and says who loses them', () {
      final result = plan(MusicRemovalMode.everything);
      expect(result.remove, {'a1', 'a2', 'a3'});
      expect(result.affectedPlaylists, {'road trip'});
    });

    test('an album no playlist touches has nobody affected', () {
      final result = planMusicRemoval(
        scope: MusicRemovalScope.library,
        mode: MusicRemovalMode.keepShared,
        tracks: {'a1'},
        playlists: {
          'other': {'b1'},
        },
      );
      expect(result.remove, {'a1'});
      expect(result.affectedPlaylists, isEmpty);
    });
  });

  group('refreshing metadata', () {
    test('subtitles, trick play, file name and transcode survive', () {
      final current = SyncedItem(
        id: 'e1',
        userId: 'u',
        videoFileName: 'e1.mkv',
        subtitles: [SubStreamModel.no()],
        sortName: 'old',
      );
      final fresh = SyncedItem(id: 'e1', userId: 'u', sortName: 'new');

      final merged = mergeRefreshed(current, fresh);

      expect(merged.sortName, 'new');
      expect(merged.videoFileName, 'e1.mkv');
      expect(merged.subtitles, hasLength(1));
      expect(merged.syncing, isFalse);
    });

    test('the later watched of the two wins, and neither being known is fine', () {
      final earlier = UserData(lastPlayed: DateTime(2026, 1, 1), played: false);
      final later = UserData(lastPlayed: DateTime(2026, 6, 1), played: true);

      final offline = SyncedItem(id: 'e1', userId: 'u', userData: later);
      final server = SyncedItem(id: 'e1', userId: 'u', userData: earlier);
      expect(mergeRefreshed(offline, server).userData?.played, isTrue);

      final none = SyncedItem(id: 'e2', userId: 'u');
      expect(mergeRefreshed(none, none).userData, isNull);
    });
  });

  group('retrying', () {
    test('failed and gone-missing both count, nothing else does', () {
      expect(DownloadStream(id: 'x', status: TaskStatus.failed).needsRetry, isTrue);
      expect(DownloadStream(id: 'x', status: TaskStatus.notFound).needsRetry, isTrue);
      for (final status in [TaskStatus.enqueued, TaskStatus.running, TaskStatus.paused, TaskStatus.complete]) {
        expect(DownloadStream(id: 'x', status: status).needsRetry, isFalse, reason: '$status');
      }
    });
  });
}

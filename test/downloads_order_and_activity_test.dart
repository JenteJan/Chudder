// The order files are listed in on the Downloads tab, and the one-thing-at-a-
// time rule for what is done to a download as a whole.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/providers/sync/downloads_overview_provider.dart';
import 'package:chudder/providers/sync/item_activity_provider.dart';

SyncedItem episode(String id, int season, int number) => SyncedItem(
      id: id,
      userId: 'u',
      itemModel: EpisodeModel(
        seriesName: 'Show',
        season: season,
        episode: number,
        episodeEnd: null,
        name: id,
        id: id,
        overview: const OverviewModel(),
        parentId: null,
        playlistId: null,
        images: null,
        childCount: null,
        primaryRatio: null,
        userData: const UserData(),
        parentImages: null,
        mediaStreams: MediaStreamsModel(versionStreams: const []),
      ),
    );

SyncedItem track(String id, {String? album, int? disc, int? number, int? year}) => SyncedItem(
      id: id,
      userId: 'u',
      itemModel: AudioModel(
        album: album,
        discNumber: disc,
        trackNumber: number,
        name: id,
        id: id,
        overview: OverviewModel(yearAired: year),
        parentId: null,
        playlistId: null,
        images: null,
        childCount: null,
        primaryRatio: null,
        userData: const UserData(),
        parentImages: null,
        mediaStreams: MediaStreamsModel(versionStreams: const []),
      ),
    );

List<String> ids(List<SyncedItem> items) => items.map((item) => item.id).toList();

void main() {
  group('listing order', () {
    test('episodes run by season and episode, with the specials last', () {
      final files = [episode('s0e1', 0, 1), episode('s2e1', 2, 1), episode('s1e2', 1, 2), episode('s1e1', 1, 1)];
      sortForPlaying(files);
      expect(ids(files), ['s1e1', 's1e2', 's2e1', 's0e1']);
    });

    test('tracks run by album year, album, disc and track number', () {
      final files = [
        track('b-2-1', album: 'B', disc: 2, number: 1, year: 2001),
        track('b-1-2', album: 'B', disc: 1, number: 2, year: 2001),
        track('a-1-1', album: 'A', disc: 1, number: 1, year: 2005),
        track('b-1-1', album: 'B', disc: 1, number: 1, year: 2001),
      ];
      sortForPlaying(files);
      expect(ids(files), ['b-1-1', 'b-1-2', 'b-2-1', 'a-1-1']);
    });

    test('a track with no disc counts as disc one', () {
      final files = [track('d2', album: 'A', disc: 2, number: 1), track('nodisc', album: 'A', number: 1)];
      sortForPlaying(files);
      expect(ids(files), ['nodisc', 'd2']);
    });

    test('a playlist keeps the order it was made in', () {
      final files = [track('z', album: 'Z', number: 9), track('a', album: 'A', number: 1)];
      sortForPlaying(files, keepOrder: true);
      expect(ids(files), ['z', 'a']);
    });

    test('what has no order of its own stays where it was', () {
      final files = [episode('x', 1, 1), track('t1'), track('t2')];
      sortForPlaying(files);
      expect(ids(files).where((id) => id.startsWith('t')), ['t1', 't2']);
    });
  });

  group('activity on a download', () {
    test('a second start while one is running is refused', () async {
      final activity = ItemActivityNotifier();
      final release = Future<void>.delayed(const Duration(milliseconds: 20));

      final first = activity.run('show', ItemActivityKind.refreshing, () => release);
      expect(activity.isBusy('show'), isTrue);
      final second = await activity.run('show', ItemActivityKind.deleting, () async => 'ran');
      expect(second, isNull);

      await first;
      expect(activity.isBusy('show'), isFalse);
    });

    test('the marker is cleared when the operation throws', () async {
      final activity = ItemActivityNotifier();
      await expectLater(
        activity.run<void>('show', ItemActivityKind.searching, () async => throw StateError('offline')),
        throwsStateError,
      );
      expect(activity.isBusy('show'), isFalse);
    });

    test('different downloads are busy independently', () async {
      final activity = ItemActivityNotifier();
      expect(activity.begin('a', ItemActivityKind.refreshing), isTrue);
      expect(activity.begin('b', ItemActivityKind.deleting), isTrue);
      expect(activity.begin('a', ItemActivityKind.deleting), isFalse);
      activity.end('a');
      expect(activity.isBusy('b'), isTrue);
    });

    test('progress is a fraction once the total is known', () {
      final activity = ItemActivityNotifier();
      activity.begin('a', ItemActivityKind.refreshing);
      expect(activity.state['a']!.fraction, isNull);
      activity.progress('a', done: 3, total: 12);
      expect(activity.state['a']!.fraction, 0.25);
    });
  });
}

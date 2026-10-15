// The group's queue as the server sends it, and what an edit to it names.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/handlers/syncplay_message_handler.dart';
import 'package:chudder/providers/syncplay/syncplay_group_queue.dart';

Map<String, dynamic> _playQueue(List<String> items, {int playing = 0, String reason = 'NewPlaylist'}) => {
      'Type': 'PlayQueue',
      'Data': <String, dynamic>{
        'Reason': reason,
        'PlayingItemIndex': playing,
        'StartPositionTicks': 0,
        'IsPlaying': true,
        'Playlist': [
          for (var i = 0; i < items.length; i++) {'ItemId': items[i], 'PlaylistItemId': 'p$i-${items[i]}'},
        ],
      },
    };

void main() {
  group('a place in the group\'s queue', () {
    // A shuffled collection with one film twice: the second b is after what plays.
    const queue = GroupQueue(
      itemIds: ['a', 'b', 'c', 'd', 'b'],
      placeIds: ['pa', 'pb1', 'pc', 'pd', 'pb2'],
      index: 2,
    );

    test('an item there twice means the place after what plays, as the lists show it', () {
      expect(queue.positionOf('b'), 4);
      expect(queue.placeOf('b'), 'pb2');
    });

    test('an item only before what plays is found there', () {
      expect(queue.positionOf('a'), 0);
      expect(queue.placeOf('a'), 'pa');
    });

    test('an item not in the queue has no place', () {
      expect(queue.positionOf('z'), -1);
      expect(queue.placeOf('z'), isNull);
    });

    test('to play next, an item from further on goes straight after what plays', () {
      expect(queue.nextIndexFor('d'), 3);
      expect(queue.nextIndexFor('b'), 3);
    });

    test('to play next, an item from before what plays lands one earlier: what plays moves up', () {
      const two = GroupQueue(itemIds: ['a', 'b', 'c', 'd'], placeIds: ['1', '2', '3', '4'], index: 2);
      // a out: b, c, d with c at 1 - a back in at 2 is straight after c.
      expect(two.nextIndexFor('a'), 2);
    });
  });

  group('the player following the group', () {
    test('what it knows, in the group\'s order, each place once', () {
      const queue = GroupQueue(itemIds: ['c', 'a', 'b', 'a'], index: 0);
      expect(queue.ordered({'a': 'A', 'b': 'B', 'c': 'C'}), ['C', 'A', 'B', 'A']);
    });

    test('what it does not know is left out until fetched, and named for fetching', () {
      const queue = GroupQueue(itemIds: ['a', 'x', 'b', 'y'], index: 0);
      expect(queue.ordered({'a': 1, 'b': 2}), [1, 2]);
      expect(queue.missingFrom(['a', 'b']), {'x', 'y'});
      expect(queue.missingFrom(['a', 'b', 'x', 'y']), isEmpty);
    });
  });

  group('the server\'s queue updates', () {
    late List<String> started;
    late int changed;
    late SyncPlayMessageHandler handler;

    setUp(() {
      started = [];
      changed = 0;
      handler = SyncPlayMessageHandler(
        onStateUpdate: (_) {},
        reportReady: ({bool isPlaying = true}) async {},
        startPlayback: (id, ticks) async => started.add(id),
        isBuffering: () => false,
        getContext: () => null,
        onGroupJoined: () {},
        onGroupJoinFailed: () {},
        onQueueChanged: () => changed++,
      );
    });

    test('keep the server\'s id for each place', () {
      handler.handleGroupUpdate(_playQueue(['a', 'b', 'c'], playing: 1), SyncPlayState(isInGroup: true));
      final queue = handler.groupQueue;
      expect(queue.itemIds, ['a', 'b', 'c']);
      expect(queue.placeIds, ['p0-a', 'p1-b', 'p2-c']);
      expect(queue.index, 1);
      expect(started, ['b']);
      expect(changed, 0);
    });

    test('an edit around what plays changes the queue without loading anything', () {
      final state = SyncPlayState(isInGroup: true, playingItemId: 'a');
      for (final reason in ['Queue', 'QueueNext', 'MoveItem', 'RemoveItems']) {
        handler.handleGroupUpdate(_playQueue(['a', 'c', 'b'], reason: reason), state);
      }
      expect(started, isEmpty);
      expect(changed, 4);
      expect(handler.groupQueue.itemIds, ['a', 'c', 'b']);
    });
  });
}

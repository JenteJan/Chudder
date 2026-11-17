import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/playback_queue_state.dart';

ItemBaseModel _item(String id) => ItemBaseModel(
      name: id,
      id: id,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      canDownload: null,
      canDelete: null,
      jellyType: null,
    );

List<String> _ids(List<ItemBaseModel> items) => items.map((e) => e.id).toList();

void main() {
  final films = ['a', 'b', 'c', 'd', 'e'].map(_item).toList();

  group('a video queue is one list', () {
    test('a film on its own becomes the first of the queue, added ones after it', () {
      final film = _item('f');
      final state = const PlaybackQueueState().addToEnd([_item('x'), _item('y')], film);
      expect(_ids(state.queue), ['f', 'x', 'y']);
      expect(state.nextUpQueue, isEmpty);
      final first = state.nextTransition('f')!;
      expect(first.item.id, 'x');
      expect(first.state.nextTransition('x')?.item.id, 'y');
    });

    test('added goes after the rest of the season', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'b').addToEnd([_item('x')], films[1]);
      expect(_ids(state.queue), ['a', 'b', 'c', 'd', 'e', 'x']);
      expect(state.nextItem('b')?.id, 'c');
    });

    test('play next goes straight after what plays, also on its own', () {
      final film = _item('f');
      final state = const PlaybackQueueState().addToEnd([_item('x')], film).insertAfterCurrent([_item('y')], film);
      expect(_ids(state.queue), ['f', 'y', 'x']);
      expect(state.nextItem('f')?.id, 'y');
    });

    test('play next on something further on moves it up instead of doubling it', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'b').insertAfterCurrent([films[3]], films[1]);
      expect(_ids(state.queue), ['a', 'b', 'd', 'c', 'e']);
      expect(_ids(state.originalQueue), ['a', 'b', 'd', 'c', 'e']);
    });

    test('adding what is already queued changes nothing', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'b').addToEnd([films[3]], films[1]);
      expect(_ids(state.queue), ['a', 'b', 'c', 'd', 'e']);
    });

    test('the list shows it in play order, from what plays', () {
      final film = _item('f');
      final state = const PlaybackQueueState().addToEnd([_item('x'), _item('y')], film);
      expect(_ids(state.queueForDisplay('f', wrapAround: false)), ['f', 'x', 'y']);
      expect(state.nextUpCountInDisplay('f'), isNull);
    });
  });

  group('play next', () {
    test('goes in front of what was added before', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'a').addToNextUp([_item('x')]);
      final next = state.playNext([_item('y')]);
      expect(_ids(next.nextUpQueue), ['y', 'x']);
      expect(next.nextItem('a')?.id, 'y');
    });

    test('playing from "up next", it goes after the one playing', () {
      final state =
          PlaybackQueueState.fromQueue(films, initialItemId: 'a').addToNextUp([_item('x'), _item('z')]).jumpToItem('x');
      final next = state.playNext([_item('y')]);
      expect(_ids(next.nextUpQueue), ['x', 'y', 'z']);
      expect(next.nextItem('x')?.id, 'y');
    });
  });

  group('reordering what is still to come', () {
    test('moves within the rest of the queue, counted from what plays', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'b');
      // Still to come: c d e. Move e to the front of them.
      final moved = state.reorderUpcoming('b', 2, 0, wrapAround: false);
      expect(_ids(moved.queue), ['a', 'b', 'e', 'c', 'd']);
      expect(moved.nextItem('b')?.id, 'e');
      expect(_ids(moved.originalQueue), ['a', 'b', 'e', 'c', 'd']);
    });

    test('with repeat on, the start of the queue comes after its end', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'c', repeatMode: AudioRepeatMode.all);
      // Still to come: d e a b. Move a to the front of them.
      final moved = state.reorderUpcoming('c', 2, 0, wrapAround: true);
      expect(_ids(moved.queue), ['c', 'a', 'd', 'e', 'b']);
      expect(moved.nextItem('c')?.id, 'a');
    });

    test('shuffled, the order to go back to is left alone', () {
      final state = PlaybackQueueState(
        queue: films,
        originalQueue: films,
        shuffleEnabled: true,
        mainQueueCurrentId: 'a',
      );
      final moved = state.reorderUpcoming('a', 0, 3, wrapAround: false);
      expect(_ids(moved.queue), ['a', 'c', 'd', 'e', 'b']);
      expect(_ids(moved.originalQueue), _ids(films));
    });

    test('an index out of range changes nothing', () {
      final state = PlaybackQueueState.fromQueue(films, initialItemId: 'a');
      expect(identical(state.reorderUpcoming('a', 9, 0, wrapAround: false), state), isTrue);
    });
  });
}

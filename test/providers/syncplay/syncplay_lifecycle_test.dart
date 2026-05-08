import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:flutter_test/flutter_test.dart';

// We deliberately avoid spinning up the full SyncPlayController here:
// it depends on a Riverpod Ref + Chopper + WebSocket. Instead we cover the
// state-flag invariants that downstream tests rely on.
//
// Lifecycle reset is verified through the controller via integration tests
// gated behind a manual test plan (see docs/syncplay-implementation.md
// "Regression scenarios"). The unit-level coverage here proves that
// SyncPlayState resets cleanly via copyWith — the controller's leaveGroup
// path uses the same pattern.

void main() {
  group('SyncPlayState lifecycle reset', () {
    test('copyWith clears all in-flight playback flags', () {
      final mid = SyncPlayState(
        isInGroup: true,
        groupId: 'g1',
        groupName: 'movie night',
        groupState: SyncPlayGroupState.playing,
        playingItemId: 'item-1',
        playlistItemId: 'plist-1',
        positionTicks: 1234,
        startPlaybackInProgress: true,
        startingPlaylistItemId: 'plist-1',
        isProcessingCommand: true,
        processingCommandType: SyncPlayCommand.unpause,
      );

      final cleared = mid.copyWith(
        isInGroup: false,
        groupId: null,
        groupName: null,
        groupState: SyncPlayGroupState.idle,
        participants: const [],
        isProcessingCommand: false,
        processingCommandType: null,
        positionTicks: 0,
        playingItemId: null,
        playlistItemId: null,
        startPlaybackInProgress: false,
        startingPlaylistItemId: null,
      );

      expect(cleared.isInGroup, isFalse);
      expect(cleared.groupId, isNull);
      expect(cleared.startPlaybackInProgress, isFalse);
      expect(cleared.startingPlaylistItemId, isNull);
      expect(cleared.processingCommandType, isNull);
      expect(cleared.playingItemId, isNull);
    });
  });
}

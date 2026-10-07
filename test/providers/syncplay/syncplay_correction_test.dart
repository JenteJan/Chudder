import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/handlers/syncplay_command_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectSyncCorrectionStrategy', () {
    test('selects SpeedToSync in medium drift window', () {
      final strategy = selectSyncCorrectionStrategy(
        config: const SyncCorrectionConfig(),
        state: const SyncCorrectionState(
          syncEnabled: true,
          activeStrategy: SyncCorrectionStrategy.none,
        ),
        diffMillis: 500,
        hasPlaybackRate: true,
      );

      expect(strategy, SyncCorrectionStrategy.speedToSync);
    });

    test('falls back to SkipToSync when playback rate unsupported', () {
      final strategy = selectSyncCorrectionStrategy(
        config: const SyncCorrectionConfig(),
        state: const SyncCorrectionState(
          syncEnabled: true,
          activeStrategy: SyncCorrectionStrategy.none,
        ),
        diffMillis: 500,
        hasPlaybackRate: false,
      );

      expect(strategy, SyncCorrectionStrategy.skipToSync);
    });

    test('selects SkipToSync for very large drift', () {
      final strategy = selectSyncCorrectionStrategy(
        config: const SyncCorrectionConfig(),
        state: const SyncCorrectionState(
          syncEnabled: true,
          activeStrategy: SyncCorrectionStrategy.none,
        ),
        diffMillis: 3500,
        hasPlaybackRate: true,
      );

      expect(strategy, SyncCorrectionStrategy.skipToSync);
    });
  });

  group('adaptiveCorrectionConfig', () {
    const base = SyncCorrectionConfig();

    test('returns base config unchanged on a LAN (no ping/jitter)', () {
      final config = adaptiveCorrectionConfig(base: base, pingMs: 0, jitterMs: 0);
      expect(config.minDelaySpeedToSyncMs, base.minDelaySpeedToSyncMs);
      expect(config.maxDelaySpeedToSyncMs, base.maxDelaySpeedToSyncMs);
      expect(config.minDelaySkipToSyncMs, base.minDelaySkipToSyncMs);
    });

    test('widens tolerance band with ping + jitter on a WAN', () {
      // slack = 300 + 100 = 400ms
      final config = adaptiveCorrectionConfig(base: base, pingMs: 300, jitterMs: 100);
      expect(config.minDelaySpeedToSyncMs, 400); // ignore drift within noise
      expect(config.minDelaySkipToSyncMs, 800); // seek only when far off
      expect(config.maxDelaySpeedToSyncMs, 3000 + 2 * 400); // 3800: speed covers more
    });

    test('extraSlackMultiplier widens the band further (chronic lag)', () {
      final config = adaptiveCorrectionConfig(
        base: base,
        pingMs: 200,
        jitterMs: 0,
        extraSlackMultiplier: 2.0,
      );
      expect(config.minDelaySpeedToSyncMs, 400); // 200 * 2
      expect(config.minDelaySkipToSyncMs, 800); // 2 * (200 * 2)
    });

    test('caps maxDelaySpeedToSyncMs so catch-up never becomes absurd', () {
      final config = adaptiveCorrectionConfig(base: base, pingMs: 4000, jitterMs: 0);
      expect(config.maxDelaySpeedToSyncMs, 6000);
    });
  });

  group('computeSpeedToSync', () {
    test('small positive gap uses a gentle rate within the base window', () {
      final plan = computeSpeedToSync(diffMillis: 500, baseDurationMs: 1000);
      expect(plan.rate, closeTo(1.5, 0.001));
      expect(plan.durationMs, closeTo(1000, 0.001));
    });

    test('large positive gap caps the rate and stretches the window', () {
      final plan = computeSpeedToSync(diffMillis: 3000, baseDurationMs: 1000);
      // Without a cap this would be 4.0x; capped to 1.5x over a 6 s window.
      expect(plan.rate, closeTo(1.5, 0.001));
      expect(plan.durationMs, closeTo(6000, 0.001));
    });

    test('a player that is ahead is slowed gently, over a longer window', () {
      final plan = computeSpeedToSync(diffMillis: -1000, baseDurationMs: 1000);
      // 0.8x gives back 200 ms a second, so a second ahead takes five.
      expect(plan.rate, closeTo(0.8, 0.001));
      expect(plan.durationMs, closeTo(5000, 0.001));
    });

    test('a small lead is closed within the base window', () {
      final plan = computeSpeedToSync(diffMillis: -100, baseDurationMs: 1000);
      expect(plan.rate, closeTo(0.9, 0.001));
      expect(plan.durationMs, closeTo(1000, 0.001));
    });
  });

  group('SyncPlayState helpers', () {
    test('hasActivePlayback false when no playing item', () {
      final state = SyncPlayState(isInGroup: true);
      expect(state.hasActivePlayback, isFalse);
    });

    test('hasActivePlayback true with playing item and non-idle state', () {
      final state = SyncPlayState(
        isInGroup: true,
        playingItemId: 'item-1',
        groupState: SyncPlayGroupState.playing,
      );
      expect(state.hasActivePlayback, isTrue);
    });

    test('hasActivePlayback false when group state is idle', () {
      final state = SyncPlayState(
        isInGroup: true,
        playingItemId: 'item-1',
      );
      expect(state.hasActivePlayback, isFalse);
    });

    test('isInLocalOnlyMode mirrors localOnlyOperationCount', () {
      expect(SyncPlayState().isInLocalOnlyMode, isFalse);
      expect(
        SyncPlayState(localOnlyOperationCount: 1).isInLocalOnlyMode,
        isTrue,
      );
      expect(
        SyncPlayState(localOnlyOperationCount: 3).isInLocalOnlyMode,
        isTrue,
      );
    });
  });

  group('SyncPlayCommandHandler', () {
    test('ignores duplicate command', () async {
      var pauseCalls = 0;
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onPause = () async {
          pauseCalls++;
        }
        ..getPositionTicks = () => 0;

      final now = DateTime.now().toUtc().toIso8601String();
      final commandData = <String, dynamic>{
        'Command': 'Pause',
        'When': now,
        'PositionTicks': 0,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());
      handler.handleCommand(commandData, SyncPlayState());

      expect(pauseCalls, 1);
    });

    test('executes Unpause as seek then play', () async {
      final order = <String>[];
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onSeek = (ticks) async {
          order.add('seek');
        }
        ..onPlay = () async {
          order.add('play');
        }
        ..getPositionTicks = () => 0;

      final commandData = <String, dynamic>{
        'Command': 'Unpause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': ticksPerSecond * 2,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(order, ['seek', 'play']);
    });

    test('Unpause is not deduped when player is paused', () async {
      var playCalls = 0;
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onPlay = () async {
          playCalls++;
        }
        ..onSeek = ((_) async {})
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => false);

      final commandData = <String, dynamic>{
        'Command': 'Unpause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': 0,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      handler.handleCommand(commandData, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(playCalls, 2);
    });

    test('an Unpause that lands mid-load is held and carried out afterwards', () async {
      var playCalls = 0;
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onPlay = () async {
          playCalls++;
        }
        ..onSeek = ((_) async {})
        ..getPositionTicks = (() => 0)
        // Reads as playing, as a player does whose last word predates the
        // load: the server's repeat of the command is then a duplicate.
        ..isPlaying = (() => true);

      final commandData = <String, dynamic>{
        'Command': 'Unpause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': 0,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState(startPlaybackInProgress: true));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(playCalls, 0);
      expect(handler.hasHeldUnpause, isTrue);

      handler.handleCommand(commandData, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(playCalls, 0, reason: 'the repeat is dropped as a duplicate');

      expect(handler.resumeFromLastCommand(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(playCalls, 1);
      expect(handler.hasHeldUnpause, isFalse);
    });

    test('there is nothing to resume from after a Pause', () async {
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onPause = () async {}
        ..getPositionTicks = (() => 0);

      handler.handleCommand({
        'Command': 'Pause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': 0,
        'PlaylistItemId': 'playlist-item-1',
      }, SyncPlayState());

      expect(handler.resumeFromLastCommand(), isFalse);
    });

    test('Seek reports ready only when not buffering', () async {
      var readyCalls = 0;
      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (_) {},
      )
        ..onPause = () async {}
        ..onSeek = (ticks) async {}
        ..onReportReady = (_) async {
          readyCalls++;
        }
        ..isBuffering = () => false;

      final commandData = <String, dynamic>{
        'Command': 'Seek',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': ticksPerSecond,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());
      // Not at once: the player is given a moment to start on the seek and
      // say that it is buffering before its silence is taken for readiness.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(readyCalls, 0);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(readyCalls, 1);

      handler.isBuffering = () => true;
      handler.handleCommand(
        {
          ...commandData,
          'When': DateTime.now().toUtc().toIso8601String(),
        },
        SyncPlayState(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(readyCalls, 1);
    });

    test('Unpause defers final state-clear until player stops buffering', () async {
      var buffering = true;
      var stateClearFired = false;

      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (updater) {
          // The finally block in _executeCommand calls
          //   state.copyWith(isProcessingCommand: false, processingCommandType: null)
          // — apply the updater to a sentinel and detect that transition.
          final after = updater(SyncPlayState(isProcessingCommand: true));
          if (after.isProcessingCommand == false) {
            stateClearFired = true;
          }
        },
      )
        ..onSeek = (_) async {}
        ..onPlay = () async {}
        ..getPositionTicks = (() => 0)
        ..isBuffering = (() => buffering);

      final commandData = <String, dynamic>{
        'Command': 'Unpause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': ticksPerSecond * 2,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());

      // While player is buffering the finally must not have fired.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        stateClearFired,
        isFalse,
        reason: 'should not clear isProcessingCommand while player is still buffering',
      );

      // Player finishes buffering; the wait loop polls every 100 ms and
      // the finally block should fire shortly after.
      buffering = false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        stateClearFired,
        isTrue,
        reason: 'should clear isProcessingCommand once buffering ends',
      );
    });

    test('Pause-with-seek defers final state-clear until player stops buffering', () async {
      var buffering = true;
      var stateClearFired = false;

      final handler = SyncPlayCommandHandler(
        timeSync: () => null,
        onStateUpdate: (updater) {
          final after = updater(SyncPlayState(isProcessingCommand: true));
          if (after.isProcessingCommand == false) {
            stateClearFired = true;
          }
        },
      )
        ..onPause = () async {}
        ..onSeek = (_) async {}
        // Force a position correction by pretending the local player is far
        // from the requested Pause position — handler will call onSeek.
        ..getPositionTicks = (() => 0)
        ..isBuffering = (() => buffering);

      final commandData = <String, dynamic>{
        'Command': 'Pause',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': ticksPerSecond * 5,
        'PlaylistItemId': 'playlist-item-1',
      };

      handler.handleCommand(commandData, SyncPlayState());

      // While player is buffering after the correction seek, the finally
      // block must not have fired.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        stateClearFired,
        isFalse,
        reason: 'should not clear isProcessingCommand while seek-induced buffering is active',
      );

      buffering = false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(
        stateClearFired,
        isTrue,
        reason: 'should clear isProcessingCommand once buffering ends',
      );
    });
  });
}

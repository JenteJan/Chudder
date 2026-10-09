import 'package:chudder/providers/syncplay/time_sync_service.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
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
    test('a gap a viewer would not see is closed at a rate they do not see either', () {
      // The phone that joined 352 ms behind was sent to 1.35x for a second.
      final plan = computeSpeedToSync(diffMillis: 352, baseDurationMs: 1000);
      expect(plan.rate, closeTo(1.06, 0.001));
      // 80% of the gap at 60 ms a second.
      expect(plan.durationMs, closeTo(352 * 0.8 / 0.06, 0.001));
    });

    test('a small lead is given back as gently', () {
      final plan = computeSpeedToSync(diffMillis: -335, baseDurationMs: 1000);
      expect(plan.rate, closeTo(0.94, 0.001));
      expect(plan.durationMs, closeTo(335 * 0.8 / 0.06, 0.001));
    });

    test('a gap too small to need the limit is closed within the base window', () {
      final plan = computeSpeedToSync(diffMillis: 50, baseDurationMs: 1000);
      expect(plan.rate, closeTo(1.04, 0.001));
      expect(plan.durationMs, closeTo(1000, 0.001));
    });

    test('the limit widens with the gap', () {
      final near = computeSpeedToSync(diffMillis: 400, baseDurationMs: 1000);
      final further = computeSpeedToSync(diffMillis: 1200, baseDurationMs: 1000);
      expect(near.rate, closeTo(1.06, 0.001));
      // Halfway between 400 ms and 2 s: halfway between 0.06 and 0.5.
      expect(further.rate, closeTo(1.28, 0.001));
    });

    test('large positive gap gets the full rate and a stretched window', () {
      final plan = computeSpeedToSync(diffMillis: 3000, baseDurationMs: 1000);
      expect(plan.rate, closeTo(1.5, 0.001));
      expect(plan.durationMs, closeTo(3000 * 0.8 / 0.5, 0.001));
    });

    test('a player far ahead is slowed to the floor and no further', () {
      final plan = computeSpeedToSync(diffMillis: -2500, baseDurationMs: 1000);
      expect(plan.rate, closeTo(0.8, 0.001));
      expect(plan.durationMs, closeTo(2500 * 0.8 / 0.2, 0.001));
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

    test('the same Seek again is a refused Ready, and is answered with another', () async {
      // The server answers a Ready more than 500 ms off the group's position
      // with the group's Seek once more - same When, same position - and
      // keeps everyone waiting for a Ready at the right place.
      final seeks = <int>[];
      final readies = <int>[];
      var position = 0;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..onSeek = (ticks) async {
          seeks.add(ticks);
          position = ticks;
        }
        ..onReportReady = (ticks) async {
          readies.add(ticks);
        }
        ..getPositionTicks = (() => position)
        ..isBuffering = () => false;

      final seek = <String, dynamic>{
        'Command': 'Seek',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': 1200 * ticksPerSecond,
        'PlaylistItemId': 'playlist-item-1',
      };
      handler.handleCommand(seek, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seeks, [1200 * ticksPerSecond]);
      expect(readies, [1200 * ticksPerSecond]);

      // Already where the seek put it: a Ready is all that is owed.
      handler.handleCommand(seek, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seeks.length, 1);
      expect(readies, [1200 * ticksPerSecond, 1200 * ticksPerSecond]);

      // Somewhere else by now: back to the seek's position first.
      position = 30 * ticksPerSecond;
      handler.handleCommand(seek, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(seeks.length, 2);
      expect(readies.length, 3);
    });

    test('a repeat of the Seek still being carried out is let go', () async {
      var readies = 0;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..onSeek = (_) async {}
        ..onReportReady = (_) async {
          readies++;
        }
        ..isBuffering = () => false;

      final seek = <String, dynamic>{
        'Command': 'Seek',
        'When': DateTime.now().toUtc().toIso8601String(),
        'PositionTicks': ticksPerSecond,
        'PlaylistItemId': 'playlist-item-1',
      };
      handler.handleCommand(seek, SyncPlayState());
      handler.handleCommand(seek, SyncPlayState(isProcessingCommand: true));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(readies, 1);
    });

    group('a resume on a player that stands still', () {
      // The local clock as the server's: no measurements, no offset.
      final clock = TimeSyncService(JellyfinOpenApi.create(baseUrl: Uri.parse('http://localhost')));

      ({SyncPlayCommandHandler handler, List<int> seeks, List<int> playedAfterMs}) resumeOn({
        required int Function() position,
        void Function(int ticks)? onSeek,
      }) {
        final seeks = <int>[];
        final played = <int>[];
        final started = Stopwatch()..start();
        final handler = SyncPlayCommandHandler(timeSync: () => clock, onStateUpdate: (_) {})
          ..onPlay = () async {
            played.add(started.elapsedMilliseconds);
          }
          ..onSeek = (ticks) async {
            seeks.add(ticks);
            onSeek?.call(ticks);
          }
          ..getPositionTicks = position
          ..getStartLatencyMs = (() => 100)
          ..isPlaying = (() => false)
          ..isBuffering = () => false;
        return (handler: handler, seeks: seeks, playedAfterMs: played);
      }

      Map<String, dynamic> unpause(int positionTicks, Duration fromNow) => {
            'Command': 'Unpause',
            'When': DateTime.now().toUtc().add(fromNow).toIso8601String(),
            'PositionTicks': positionTicks,
            'PlaylistItemId': 'playlist-item-1',
          };

      test('paused where the group paused, it starts on the group\'s time and is not moved', () async {
        const at = 600 * ticksPerSecond;
        final run = resumeOn(position: () => at);
        run.handler.handleCommand(unpause(at, const Duration(milliseconds: 300)), SyncPlayState());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(run.seeks, isEmpty);
        // 300 ms away, less the 100 ms it takes to get going.
        expect(run.playedAfterMs.single, inInclusiveRange(150, 320));
      });

      test('having run on a little past the pause, it starts that much later instead of seeking back', () async {
        const at = 600 * ticksPerSecond;
        final run = resumeOn(position: () => at + millisecondsToTicks(250));
        run.handler.handleCommand(unpause(at, const Duration(milliseconds: 300)), SyncPlayState());
        await Future<void>.delayed(const Duration(milliseconds: 750));
        expect(run.seeks, isEmpty);
        expect(run.playedAfterMs.single, inInclusiveRange(400, 580));
      });

      test('loaded ahead of a group that is already playing, it waits for the group to arrive', () async {
        const at = 600 * ticksPerSecond;
        // The group resumed a second ago; this player was loaded 1.4 s on.
        final run = resumeOn(position: () => at + millisecondsToTicks(1400));
        run.handler.handleCommand(unpause(at, const Duration(seconds: -1)), SyncPlayState());
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(run.seeks, isEmpty);
        expect(run.playedAfterMs.single, inInclusiveRange(250, 430));
      });

      test('far behind a group that is playing, it seeks to where the group will be, not where it is', () async {
        const at = 600 * ticksPerSecond;
        var position = at;
        final run = resumeOn(position: () => position, onSeek: (ticks) => position = ticks);
        // The group resumed ten seconds ago.
        run.handler.handleCommand(unpause(at, const Duration(seconds: -10)), SyncPlayState());
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        // Ten seconds on, plus the second a seek is given and the start.
        final ahead = ticksToMilliseconds(run.seeks.single - at);
        expect(ahead, inInclusiveRange(11000, 11300));
        // And played when the group got there, not the moment the seek was done.
        expect(run.playedAfterMs.single, inInclusiveRange(900, 1250));
      });

      test('a pause that overtakes it calls the resume off', () async {
        const at = 600 * ticksPerSecond;
        final run = resumeOn(position: () => at);
        run.handler.onPause = () async {};
        run.handler.handleCommand(unpause(at, const Duration(milliseconds: 300)), SyncPlayState());
        run.handler.handleCommand({
          'Command': 'Pause',
          'When': DateTime.now().toUtc().toIso8601String(),
          'PositionTicks': at,
          'PlaylistItemId': 'playlist-item-1',
        }, SyncPlayState());
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(run.playedAfterMs, isEmpty);
      });
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

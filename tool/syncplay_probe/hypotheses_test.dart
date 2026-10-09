// Hypotheses about the app's own half of SyncPlay, as tests.
//
// Not part of the suite - it lives outside test/ on purpose. Each test states
// a suspected inconsistency and asserts that the code does behave that way
// today: a pass means the hypothesis is confirmed, a failure that the
// behaviour has changed (and the test wants turning into a regression test
// under test/). Run with:
//
//   flutter test tool/syncplay_probe/hypotheses_test.dart
//
// The server's half is probed by sp.py / experiments.py next to this file.
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/handlers/syncplay_command_handler.dart';

Map<String, dynamic> _command(String command, DateTime when, int ticks) => {
      'Command': command,
      'When': when.toUtc().toIso8601String(),
      'PositionTicks': ticks,
      'PlaylistItemId': 'playlist-item-1',
    };

void main() {
  group('Command handler', () {
    test('C2: a re-sent Unpause is dropped when the player merely reads as playing', () async {
      var plays = 0;
      var reportsPlaying = false;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPlay = () async {
          plays++;
        }
        ..onSeek = ((_) async {})
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => reportsPlaying);

      final unpause = _command('Unpause', DateTime.now(), 0);
      handler.handleCommand(unpause, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(plays, 1);

      // Something paused the player locally - a media key, the notification -
      // without the flag following, or the flag was never right to begin with.
      reportsPlaying = true;
      handler.handleCommand(unpause, SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(plays, 1, reason: 'the only thing that could restart it is thrown away');
    });

  });

  group('Drift correction', () {
    test('S1: a player a second ahead is no longer slowed to a crawl', () {
      final plan = computeSpeedToSync(diffMillis: -1000, baseDurationMs: 1000);
      expect(plan.rate, greaterThanOrEqualTo(0.8));
    });

    test('S2: the server accepts a Ready within 500 ms, the client only corrects from 60 ms', () {
      // Both numbers matter together: a member the chronic-lag backoff lets
      // sit more than half a second behind has every Ready rejected.
      const config = SyncCorrectionConfig();
      final widened = adaptiveCorrectionConfig(base: config, pingMs: 300, jitterMs: 100, extraSlackMultiplier: 4);
      expect(config.minDelaySpeedToSyncMs, 60);
      expect(widened.minDelaySpeedToSyncMs, greaterThan(500),
          reason: 'on a slow link the tolerated drift exceeds what the server will take a Ready at');
    });
  });
}

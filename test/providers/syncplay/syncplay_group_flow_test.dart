import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/handlers/syncplay_command_handler.dart';
import 'package:chudder/providers/syncplay/syncplay_controller.dart';
import 'package:chudder/providers/syncplay/syncplay_group_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _command(String command, DateTime when, int ticks, {String item = 'place-1'}) => {
      'Command': command,
      'When': when.toUtc().toIso8601String(),
      'PositionTicks': ticks,
      'PlaylistItemId': item,
    };

void main() {
  group('groupQueueWindow', () {
    test('leaves a queue the web client can read alone', () {
      final ids = List.generate(300, (i) => '$i');
      final window = groupQueueWindow(ids, 120);
      expect(window.itemIds, ids);
      expect(window.position, 120);
    });

    test('cuts a longer one around what plays, which stays where it is meant', () {
      final ids = List.generate(1000, (i) => '$i');
      final window = groupQueueWindow(ids, 500);
      expect(window.itemIds.length, maxGroupQueueLength);
      expect(window.itemIds[window.position], '500');
      expect(window.position, 20, reason: 'what comes next is what the window is for');
    });

    test('holds at either end of the queue', () {
      final ids = List.generate(1000, (i) => '$i');
      final first = groupQueueWindow(ids, 3);
      expect(first.itemIds[first.position], '3');
      final last = groupQueueWindow(ids, 999);
      expect(last.itemIds[last.position], '999');
      expect(last.itemIds.length, maxGroupQueueLength);
    });
  });

  group('readyClaimsRunning', () {
    const hour = 3600 * ticksPerSecond;

    test('a paused player says it is paused', () {
      // Claiming to run left the last member in with no Unpause of its own.
      expect(
        readyClaimsRunning(playerRunning: false, hasPlayer: true, positionTicks: hour ~/ 2, durationTicks: hour),
        isFalse,
      );
    });

    test('a running player says it runs', () {
      expect(
        readyClaimsRunning(playerRunning: true, hasPlayer: true, positionTicks: hour ~/ 2, durationTicks: hour),
        isTrue,
      );
    });

    test('nothing loaded does not hold the group', () {
      expect(readyClaimsRunning(playerRunning: false, hasPlayer: false, positionTicks: 0, durationTicks: 0), isTrue);
    });

    // The server clamps a Ready to its own runtime and not the group's
    // position, so a paused one here would be refused until the wait ran out.
    test('past the length the server has, a paused player is still let through', () {
      expect(
        readyClaimsRunning(playerRunning: false, hasPlayer: true, positionTicks: hour + 100, durationTicks: hour),
        isTrue,
      );
    });
  });

  group('Commands for what the group is on', () {
    late List<int> seeks;
    late int pauses;
    late SyncPlayCommandHandler handler;

    setUp(() {
      seeks = [];
      pauses = 0;
      handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {
          pauses++;
        }
        ..onSeek = ((ticks) async => seeks.add(ticks))
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => false);
    });

    test('a Pause for the item the group left does nothing', () async {
      // 22:31 on 2026-10-30: a Pause at 22 minutes, meant for the end of an
      // episode, was seconds from firing on the next one.
      handler.handleCommand(
        _command('Pause', DateTime.now(), 13242797361, item: 'old-place'),
        SyncPlayState(playlistItemId: 'new-place', playingItemId: 'new'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(pauses, 0);
      expect(seeks, isEmpty);
      expect(handler.lastCommand, isNull);
    });

    test('a Pause for the current item is carried out', () async {
      handler.handleCommand(
        _command('Pause', DateTime.now(), 5 * ticksPerSecond),
        SyncPlayState(playlistItemId: 'place-1', playingItemId: 'item'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(pauses, 1);
    });

    test('a command before the queue has arrived is carried out', () async {
      handler.handleCommand(_command('Pause', DateTime.now(), 0), SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(pauses, 1);
    });

    test('Stop from a group with nothing playing leaves the player alone', () async {
      // An idle group answers a join with Stop, which rewound what was on.
      handler.handleCommand(_command('Stop', DateTime.now(), 0), SyncPlayState());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(pauses, 0);
      expect(seeks, isEmpty);
    });
  });

  group('Seeks in a run', () {
    test('only the last says Ready', () async {
      final readies = <int>[];
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..onSeek = ((_) async {})
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => false)
        ..waitUntilPlayable = (() => Future<void>.delayed(const Duration(milliseconds: 20)))
        ..onReportReady = (ticks) async => readies.add(ticks);

      final state = SyncPlayState(playlistItemId: 'place-1', playingItemId: 'item');
      final when = DateTime.now().subtract(const Duration(milliseconds: 50));
      handler.handleCommand(_command('Seek', when, 100), state);
      handler.handleCommand(_command('Seek', when, 200), state);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(readies, [200]);
    });

    test('one lost in a load is carried out when the load ends', () async {
      final seeks = <int>[];
      final readies = <int>[];
      var position = 0;
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..onSeek = ((ticks) async => seeks.add(ticks))
        ..getPositionTicks = (() => position)
        ..isPlaying = (() => false)
        ..waitUntilPlayable = (() async {})
        ..onReportReady = (ticks) async => readies.add(ticks);

      final state = SyncPlayState(playlistItemId: 'place-1', playingItemId: 'item');
      final target = 200 * ticksPerSecond;
      handler.handleCommand(_command('Seek', DateTime.now().subtract(const Duration(milliseconds: 50)), target), state);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      seeks.clear();
      readies.clear();

      handler.catchUpSeekAfterLoad();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seeks, [target]);
      expect(readies, [target]);

      position = target;
      seeks.clear();
      handler.catchUpSeekAfterLoad();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seeks, isEmpty, reason: 'a player that got there has nothing to catch up on');
    });
  });

  group('A running member after its own stall', () {
    test('is measured from where it said Ready, not from the resume before the wait', () {
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPlay = () async {}
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => true);
      final old = DateTime.utc(2026, 10, 30, 21);
      handler.handleCommand(_command('Unpause', old, 100), SyncPlayState());

      final ready = old.add(const Duration(minutes: 5));
      handler.rebaseResume(999, ready);

      expect(handler.lastCommand?.positionTicks, 999);
      expect(DateTime.parse(handler.lastCommand!.when), ready);
      expect(handler.lastCommand?.command, SyncPlayCommand.unpause);
    });

    test('a pause stays a pause', () {
      final handler = SyncPlayCommandHandler(timeSync: () => null, onStateUpdate: (_) {})
        ..onPause = () async {}
        ..getPositionTicks = (() => 0)
        ..isPlaying = (() => false);
      handler.handleCommand(_command('Pause', DateTime.utc(2026), 100), SyncPlayState());
      handler.rebaseResume(999, DateTime.utc(2027));
      expect(handler.lastCommand?.positionTicks, 100);
    });
  });

  group('The buffering flag outside a group', () {
    final controllerProvider = Provider<SyncPlayController>((ref) => SyncPlayController(ref));

    // Every load sets it. Set outside a group nothing cleared it, and a film
    // playing when the group was made read as buffering: no Ready, so the
    // group waited out the server's half minute on its own creator.
    test('a solo load leaves no trace', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(controllerProvider);

      controller.setPlayerBufferingState(true);

      expect(controller.state.correctionState.playerIsBuffering, isFalse);
    });
  });
}

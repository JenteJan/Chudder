// How a remote walks the player's scrubber: a tap nudges, a hold ramps, and
// the ground covered depends on how long the key is held, not on how often
// the remote repeats it.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/screens/video_player/components/scrub_ramp.dart';

const _film = Duration(hours: 2);
const _episode = Duration(minutes: 22);

/// Holds a direction for [held], the remote repeating every [every], and
/// returns how far the scrubber travelled.
Duration _hold(ScrubRamp ramp, {required Duration total, required Duration held, required Duration every}) {
  var now = const Duration(seconds: 10);
  var travelled = ramp.step(forward: true, repeat: false, now: now, total: total);
  final end = now + held;
  while (now + every <= end) {
    now += every;
    travelled += ramp.step(forward: true, repeat: true, now: now, total: total);
  }
  return travelled;
}

void main() {
  group('a tap', () {
    test('nudges by a fixed few seconds either way', () {
      final ramp = ScrubRamp();
      expect(ramp.step(forward: true, repeat: false, now: Duration.zero, total: _film), ScrubRamp.tap);
      expect(ramp.step(forward: false, repeat: false, now: const Duration(seconds: 1), total: _film), -ScrubRamp.tap);
    });

    test('is the same on a film and an episode', () {
      expect(
        ScrubRamp().step(forward: true, repeat: false, now: Duration.zero, total: _episode),
        ScrubRamp().step(forward: true, repeat: false, now: Duration.zero, total: _film),
      );
    });
  });

  group('a hold', () {
    test('starts near the tap\'s pace and speeds up', () {
      final ramp = ScrubRamp();
      var now = Duration.zero;
      ramp.step(forward: true, repeat: false, now: now, total: _film);
      final steps = <Duration>[];
      for (var i = 0; i < 100; i++) {
        now += const Duration(milliseconds: 50);
        steps.add(ramp.step(forward: true, repeat: true, now: now, total: _film));
      }
      // Every step at least as far as the one before.
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i] >= steps[i - 1], isTrue, reason: 'step $i shrank: ${steps[i - 1]} -> ${steps[i]}');
      }
      // The first repeat is a fraction of a tap; the last, five seconds in
      // and past the ramp, is a good deal more than one.
      expect(steps.first < ScrubRamp.tap, isTrue, reason: 'first repeat was ${steps.first}');
      expect(steps.last > ScrubRamp.tap * 5, isTrue, reason: 'last repeat was ${steps.last}');
    });

    test('covers the same ground however often the remote repeats', () {
      final fast = _hold(ScrubRamp(), total: _film, held: const Duration(seconds: 4), every: const Duration(milliseconds: 33));
      final slow = _hold(ScrubRamp(), total: _film, held: const Duration(seconds: 4), every: const Duration(milliseconds: 100));
      final ratio = fast.inMilliseconds / slow.inMilliseconds;
      expect(ratio, closeTo(1, 0.08), reason: 'fast $fast, slow $slow');
    });

    test('crosses a film in a hold of some seconds', () {
      final travelled = _hold(ScrubRamp(), total: _film, held: const Duration(seconds: 6), every: const Duration(milliseconds: 50));
      expect(travelled > const Duration(minutes: 45), isTrue, reason: 'travelled $travelled');
      expect(travelled < _film, isTrue, reason: 'travelled $travelled');
    });

    test('does not crawl on an episode', () {
      final travelled = _hold(ScrubRamp(), total: _episode, held: const Duration(seconds: 3), every: const Duration(milliseconds: 50));
      // At least the floors: fifteen seconds a second at the start, more later.
      expect(travelled > const Duration(seconds: 45), isTrue, reason: 'travelled $travelled');
    });

    test('still moves on a platform whose key events carry no time', () {
      final ramp = ScrubRamp();
      ramp.step(forward: true, repeat: false, now: Duration.zero, total: _film);
      final step = ramp.step(forward: true, repeat: true, now: Duration.zero, total: _film);
      expect(step > Duration.zero, isTrue);
    });
  });

  group('a hold ends', () {
    test('when the direction changes: the first press back is a tap', () {
      final ramp = ScrubRamp();
      var now = Duration.zero;
      ramp.step(forward: true, repeat: false, now: now, total: _film);
      for (var i = 0; i < 60; i++) {
        now += const Duration(milliseconds: 50);
        ramp.step(forward: true, repeat: true, now: now, total: _film);
      }
      now += const Duration(milliseconds: 50);
      expect(ramp.step(forward: false, repeat: true, now: now, total: _film), -ScrubRamp.tap);
    });

    test('when a repeat arrives long after the last press', () {
      final ramp = ScrubRamp();
      var now = Duration.zero;
      ramp.step(forward: true, repeat: false, now: now, total: _film);
      for (var i = 0; i < 60; i++) {
        now += const Duration(milliseconds: 50);
        ramp.step(forward: true, repeat: true, now: now, total: _film);
      }
      now += const Duration(seconds: 2);
      expect(ramp.step(forward: true, repeat: true, now: now, total: _film), ScrubRamp.tap);
    });

    test('when reset: the next press is a tap and the ramp starts over', () {
      final ramp = ScrubRamp();
      var now = Duration.zero;
      ramp.step(forward: true, repeat: false, now: now, total: _film);
      for (var i = 0; i < 60; i++) {
        now += const Duration(milliseconds: 50);
        ramp.step(forward: true, repeat: true, now: now, total: _film);
      }
      ramp.reset();
      expect(ramp.holding, isFalse);
      now += const Duration(milliseconds: 50);
      expect(ramp.step(forward: true, repeat: false, now: now, total: _film), ScrubRamp.tap);
      now += const Duration(milliseconds: 50);
      final first = ramp.step(forward: true, repeat: true, now: now, total: _film);
      expect(first < ScrubRamp.tap, isTrue, reason: 'the ramp did not start over: $first');
    });
  });
}

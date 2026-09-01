import 'package:fladder/providers/websocket/jellyfin_websocket.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reconnectDelay', () {
    test('doubles per attempt from the base delay', () {
      expect(reconnectDelay(0), kBaseReconnectDelay);
      expect(reconnectDelay(1), const Duration(seconds: 4));
      expect(reconnectDelay(2), const Duration(seconds: 8));
      expect(reconnectDelay(3), const Duration(seconds: 16));
    });

    test('holds at the ceiling instead of running away', () {
      expect(reconnectDelay(4), kMaxReconnectDelay);
      expect(reconnectDelay(5), kMaxReconnectDelay);
      expect(reconnectDelay(50), kMaxReconnectDelay);
    });

    // The regression this whole change exists for: the ladder used to stop
    // after five attempts (~62s), which left the socket down for the rest of
    // the process after any outage longer than a minute - and with it every
    // SyncPlay join, which bails on `!isConnected` without contacting the
    // server at all. A very late attempt must still produce a finite,
    // sensible delay rather than a signal to give up.
    test('never gives up, however many attempts have failed', () {
      for (final attempt in [6, 20, 100, 10000]) {
        final delay = reconnectDelay(attempt);
        expect(delay, kMaxReconnectDelay, reason: 'attempt $attempt should still retry');
        expect(delay.isNegative, isFalse);
      }
    });

    test('a huge attempt count does not overflow into a negative delay', () {
      // Guards the `1 << attempt` shift: past 63 this wraps to zero or
      // negative on a 64-bit int, which would busy-loop the reconnect timer.
      expect(reconnectDelay(64), kMaxReconnectDelay);
      expect(reconnectDelay(1 << 20), kMaxReconnectDelay);
    });

    test('honours custom base and ceiling', () {
      expect(
        reconnectDelay(0, base: const Duration(seconds: 1), max: const Duration(seconds: 5)),
        const Duration(seconds: 1),
      );
      expect(
        reconnectDelay(9, base: const Duration(seconds: 1), max: const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
    });
  });
}

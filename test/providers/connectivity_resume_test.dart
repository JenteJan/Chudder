import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/screens/home_screen.dart';

/// The reachability verdicts around the moments that used to put a working
/// phone offline: coming back from the background, changing network, and a
/// request dying on a stale socket. A real outage still has to be admitted
/// within a few seconds.
void main() {
  late bool serverAnswers;
  late List<ConnectivityResult> osReading;
  late StreamController<List<ConnectivityResult>> osEvents;
  late int recycles;
  late int probes;

  setUp(() {
    serverAnswers = true;
    osReading = [ConnectivityResult.mobile];
    osEvents = StreamController<List<ConnectivityResult>>.broadcast();
    recycles = 0;
    probes = 0;
    ConnectivityStatus.readOsConnectivity = () async => osReading;
    ConnectivityStatus.osConnectivityEvents = () => osEvents.stream;
    ConnectivityStatus.probeServer = (_) async {
      probes++;
      return serverAnswers;
    };
    ConnectivityStatus.recycleConnections = () => recycles++;
  });

  tearDown(() => osEvents.close());

  ProviderContainer start() {
    final container = ProviderContainer(overrides: [
      serverUrlProvider.overrideWith((ref) => 'https://jellyfin.example'),
    ]);
    // Keeps the provider alive and its listeners running, as the app does.
    container.listen(connectivityStatusProvider, (_, __) {});
    return container;
  }

  /// Lets the launch probe confirm the server and the launch grace run out.
  Future<void> settleOnline(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  }

  bool offline(ProviderContainer container) => container.read(connectivityStatusProvider) == ConnectionState.offline;

  testWidgets('a resume whose first probes fail stays online through the grace window', (tester) async {
    final container = start();
    await settleOnline(tester);
    expect(offline(container), isFalse);

    final notifier = container.read(connectivityStatusProvider.notifier);
    notifier.onBackgrounded();
    serverAnswers = false;
    osReading = [ConnectivityResult.none];
    notifier.onResumed();
    expect(recycles, 1, reason: 'the pool from before the background is thrown away first');

    await tester.pump();
    // The radio comes back two seconds in.
    await tester.pump(const Duration(seconds: 1));
    expect(offline(container), isFalse);
    serverAnswers = true;
    osReading = [ConnectivityResult.mobile];
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(offline(container), isFalse);

    await finish(tester, container);
  });

  testWidgets('a real outage at resume is admitted within a few seconds', (tester) async {
    final container = start();
    await settleOnline(tester);

    final notifier = container.read(connectivityStatusProvider.notifier);
    notifier.onBackgrounded();
    serverAnswers = false;
    notifier.onResumed();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(offline(container), isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(offline(container), isTrue);

    await finish(tester, container);
  });

  testWidgets('failures while in the background are not held against the server', (tester) async {
    final container = start();
    await settleOnline(tester);

    final notifier = container.read(connectivityStatusProvider.notifier);
    notifier.onBackgrounded();
    serverAnswers = false;
    for (var i = 0; i < 8; i++) {
      notifier.reportConnectionFailure();
      await tester.pump(const Duration(seconds: 15));
    }
    expect(offline(container), isFalse);

    await finish(tester, container);
  });

  testWidgets('a failed request asks for a probe instead of going offline', (tester) async {
    final container = start();
    await settleOnline(tester);
    final before = probes;

    final notifier = container.read(connectivityStatusProvider.notifier);
    notifier.reportConnectionFailure();
    await tester.pump();
    expect(probes, before + 1);
    expect(offline(container), isFalse, reason: 'the server answered the probe');

    // A dead server takes two strikes, the second three seconds later.
    serverAnswers = false;
    notifier.reportConnectionFailure();
    await tester.pump();
    expect(offline(container), isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(offline(container), isTrue);

    await finish(tester, container);
  });

  testWidgets('a change of network recycles the pool and gets the grace window', (tester) async {
    final container = start();
    await settleOnline(tester);
    osEvents.add([ConnectivityResult.mobile]);
    await tester.pump();
    final recyclesBefore = recycles;

    serverAnswers = false;
    osReading = [ConnectivityResult.wifi];
    osEvents.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(recycles, recyclesBefore + 1);
    await tester.pump(const Duration(seconds: 2));
    expect(offline(container), isFalse);

    // The same network announced again is not a change.
    osEvents.add([ConnectivityResult.wifi]);
    await tester.pump();
    expect(recycles, recyclesBefore + 1);

    serverAnswers = true;
    await tester.pump(const Duration(seconds: 3));
    expect(offline(container), isFalse);

    await finish(tester, container);
  });

  testWidgets('a launch without a route to the server goes offline once the launch grace ends', (tester) async {
    serverAnswers = false;
    final container = start();
    await tester.pump();
    expect(offline(container), isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 1));
    expect(offline(container), isTrue);
    expect(container.read(connectivityStatusProvider.notifier).everConfirmed, isFalse);

    await finish(tester, container);
  });

  test('only a launch that never reached the server, with downloads, opens them', () {
    expect(shouldOpenDownloadsOnOfflineLaunch(serverEverAnswered: false, hasSyncedItems: true), isTrue);
    expect(shouldOpenDownloadsOnOfflineLaunch(serverEverAnswered: true, hasSyncedItems: true), isFalse,
        reason: 'going offline while the app is in use moves nobody');
    expect(shouldOpenDownloadsOnOfflineLaunch(serverEverAnswered: false, hasSyncedItems: false), isFalse);
  });
}

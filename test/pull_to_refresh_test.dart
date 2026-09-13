// A page's first load through [PullToRefresh]: started at once, run once, and
// the spinner only for a load that is still going after a moment.

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/scheduler.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/widgets/shared/pull_to_refresh.dart';

class _Online extends ConnectivityStatus {
  @override
  ConnectionState build() => ConnectionState.wifi;
}

/// Pumps frame after frame: an animation only counts from its first frame.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 10);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}

Finder get _spinner => find.byType(RefreshProgressIndicator);

void main() {
  late int runs;
  late Duration loadTime;
  late GlobalKey<RefreshIndicatorState> key;

  late SchedulerPhase startedIn;
  late ValueNotifier<bool> visible;

  Future<void> pumpPage(WidgetTester tester, {bool refreshOnStart = true, bool loadWhileBuilding = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [connectivityStatusProvider.overrideWith(_Online.new)],
        child: MaterialApp(
          home: Scaffold(
            // Stands in for a page pushed over this one, or its tab left.
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, visible, _) => TickerMode(
                enabled: visible,
                child: PullToRefresh(
                  refreshKey: key,
                  refreshOnStart: refreshOnStart,
                  onRefresh: () async {
                    runs++;
                    startedIn = SchedulerBinding.instance.schedulerPhase;
                    await Future<void>.delayed(loadTime);
                  },
                  child: (context) => Builder(builder: (context) {
                    // What library search does from didUpdateWidget on web.
                    if (loadWhileBuilding) key.load();
                    return ListView(children: const [SizedBox(height: 40)]);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    runs = 0;
    loadTime = const Duration(milliseconds: 50);
    key = GlobalKey<RefreshIndicatorState>();
    visible = ValueNotifier(true);
  });

  testWidgets('the first load starts at once, runs once and shows no spinner when it is quick', (tester) async {
    await pumpPage(tester);
    // Not after the indicator's 150ms snap: on the frame the page was built.
    expect(runs, 1);

    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      expect(_spinner, findsNothing);
    }
    expect(runs, 1);
  });

  testWidgets('a slow first load brings the spinner down late and still runs once', (tester) async {
    loadTime = const Duration(seconds: 1);
    await pumpPage(tester);
    expect(runs, 1);

    await _pumpFor(tester, kRefreshIndicatorDelay - const Duration(milliseconds: 20));
    expect(_spinner, findsNothing);

    await _pumpFor(tester, const Duration(milliseconds: 300));
    expect(_spinner, findsOneWidget);
    expect(runs, 1, reason: 'the indicator joins the load already running');

    await _pumpFor(tester, const Duration(seconds: 2));
    expect(_spinner, findsNothing);
    expect(runs, 1);
  });

  testWidgets('a load that ends while the spinner is still coming down is not run again', (tester) async {
    // Ends inside the indicator's snap, which starts at the delay.
    loadTime = kRefreshIndicatorDelay + const Duration(milliseconds: 60);
    await pumpPage(tester);

    await _pumpFor(tester, const Duration(seconds: 2));
    expect(runs, 1);
    expect(_spinner, findsNothing);
  });

  testWidgets('a show() during the first load joins it', (tester) async {
    loadTime = const Duration(milliseconds: 500);
    await pumpPage(tester);
    await _pumpFor(tester, const Duration(milliseconds: 50));

    unawaited(key.currentState!.show());
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(runs, 1);
  });

  testWidgets('a refresh asked for after the first load runs again', (tester) async {
    await pumpPage(tester);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(runs, 1);

    unawaited(key.currentState!.show());
    await _pumpFor(tester, const Duration(milliseconds: 120));
    expect(runs, 1, reason: 'a refresh somebody asked for still waits for the snap');
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(runs, 2);
  });

  testWidgets('without refreshOnStart nothing loads until asked, and load() starts one', (tester) async {
    await pumpPage(tester, refreshOnStart: false);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(runs, 0);

    final loaded = key.load();
    expect(runs, 1);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    await loaded;
    expect(_spinner, findsNothing);

    // And a second load() asked for while one runs joins it.
    loadTime = const Duration(milliseconds: 200);
    final second = key.load();
    final third = key.load();
    expect(identical(second, third), isTrue);
    await _pumpFor(tester, const Duration(milliseconds: 500));
    expect(runs, 2);
  });

  testWidgets('a load() asked for while the tree builds starts once the frame is done', (tester) async {
    await pumpPage(tester, refreshOnStart: false);
    await pumpPage(tester, refreshOnStart: false, loadWhileBuilding: true);
    expect(runs, 1);
    expect(startedIn, isNot(SchedulerPhase.persistentCallbacks));
    await _pumpFor(tester, const Duration(milliseconds: 500));
  });

  testWidgets('a page covered while its spinner comes down does not hand a later refresh the old load',
      (tester) async {
    loadTime = const Duration(milliseconds: 400);
    await pumpPage(tester);
    // The indicator starts coming down at the delay; the page is covered in
    // the middle of that, and its animation stands still.
    await _pumpFor(tester, kRefreshIndicatorDelay + const Duration(milliseconds: 50));
    visible.value = false;
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(runs, 1);

    // Asked for while covered - a player closing, say - and then shown again.
    unawaited(key.currentState!.show());
    await tester.pump();
    visible.value = true;
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(runs, 2);
    expect(_spinner, findsNothing);
  });

  testWidgets('a slow load on a page out of sight brings no spinner down', (tester) async {
    loadTime = const Duration(seconds: 1);
    visible.value = false;
    await pumpPage(tester);
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(runs, 1);

    visible.value = true;
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(runs, 1);
    expect(_spinner, findsNothing);
  });
}

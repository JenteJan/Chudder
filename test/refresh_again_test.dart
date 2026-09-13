import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/util/refresh_again.dart';

/// Pumps frame after frame for [total]: an animation only starts counting on
/// its first frame, so one long pump does not finish it.
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var elapsed = Duration.zero; elapsed < total; elapsed += step) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('a refresh asked for during another runs after it', (tester) async {
    final key = GlobalKey<RefreshIndicatorState>();
    final again = RefreshAgain();
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            key: key,
            onRefresh: () async {
              again.started();
              runs++;
              await Future<void>.delayed(const Duration(seconds: 2));
            },
            child: ListView(children: const [SizedBox(height: 40)]),
          ),
        ),
      ),
    );

    Future<void> ask() => again.show(() => key.currentState, mounted: () => true);

    final first = ask();
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(runs, 1);

    // Two more while the first is going: one more run, not two.
    final second = ask();
    final third = ask();
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(runs, 1, reason: 'the indicator drops a show() while it is up');

    // The first run ends, the indicator goes, and the next run starts.
    await pumpFor(tester, const Duration(milliseconds: 2800));
    expect(runs, 2);

    await pumpFor(tester, const Duration(milliseconds: 3500));
    await first;
    await second;
    await third;
    expect(runs, 2);
  });

  testWidgets('one asked for while idle runs at once', (tester) async {
    final key = GlobalKey<RefreshIndicatorState>();
    final again = RefreshAgain();
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            key: key,
            onRefresh: () async {
              again.started();
              runs++;
            },
            child: ListView(children: const [SizedBox(height: 40)]),
          ),
        ),
      ),
    );

    final done = again.show(() => key.currentState, mounted: () => true);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(runs, 1);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await done;
  });
}

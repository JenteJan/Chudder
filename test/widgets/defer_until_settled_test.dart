import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/widgets/shared/defer_until_settled.dart';

/// The rows under a detail page's header wait for the page's transition: their
/// images used to land while the poster was still flying in, and handling
/// them stalled its last frames.
void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('held back until the page has finished opening (${platform.name})', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        theme: ThemeData(platform: platform),
        home: const SizedBox(),
      ));

      navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (context) => const Column(children: [
          Text('header'),
          DeferUntilSettled(child: Text('rows')),
        ]),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('header'), findsOneWidget);
      expect(find.text('rows'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('rows'), findsOneWidget);
    });
  }

  testWidgets('a page with no transition to wait for builds everything at once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DeferUntilSettled(child: Text('rows'))));
    expect(find.text('rows'), findsOneWidget);
  });

  testWidgets('rows come in one a frame from the top once the page has opened', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (context) => const Column(children: [
        DeferUntilSettled(child: Text('first')),
        DeferUntilSettled(order: 1, child: Text('second')),
        DeferUntilSettled(order: 2, child: Text('third')),
      ]),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('first'), findsNothing);

    // The frame the transition ends on.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(find.text('third'), findsNothing);
    await tester.pump();
    expect(find.text('third'), findsOneWidget);
  });
}

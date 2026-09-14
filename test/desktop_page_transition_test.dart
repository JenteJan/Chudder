import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart' hide AutoRouter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/routes/auto_router.dart' as app;

/// The app's own router - its page transition - with two plain pages and no
/// sign-in guard.
class _TestRouter extends app.AutoRouter {
  _TestRouter({required super.ref});

  @override
  List<AutoRouteGuard> get guards => const [];

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: PageInfo('TestHome', builder: (_) => const Text('home')), path: '/', initial: true),
        AutoRoute(page: PageInfo('TestDetails', builder: (_) => const Text('details')), path: '/details'),
      ];
}

/// Whether any snapshot between [finder] and the root is drawing a picture
/// instead of the page.
bool _drawnFromSnapshot(WidgetTester tester, Finder finder) => tester
    .widgetList<SnapshotWidget>(find.ancestor(of: finder, matching: find.byType(SnapshotWidget)))
    .any((widget) => widget.controller.allowSnapshotting);

void main() {
  Future<_TestRouter> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    _TestRouter? router;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            router ??= _TestRouter(ref: ref);
            return MaterialApp.router(routerConfig: router!.config());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router!;
  }

  Future<void> midPush(WidgetTester tester, _TestRouter router) async {
    router.push(const PageRouteInfo<void>('TestDetails'));
    // The push resolves its route asynchronously before the page is built.
    for (var i = 0; i < 10 && find.text('details').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('details'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  }

  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets('on ${platform.name} the page coming in is drawn live during the zoom', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final router = await pumpApp(tester);
      await midPush(tester, router);

      expect(_drawnFromSnapshot(tester, find.text('details')), isFalse);
      // The page going away still zooms as a picture.
      expect(_drawnFromSnapshot(tester, find.text('home')), isTrue);

      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('on ${platform.name} going back stays on pictures, both ways', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final router = await pumpApp(tester);
      router.push(const PageRouteInfo<void>('TestDetails'));
      await tester.pumpAndSettle();

      router.maybePop();
      // Like the push, the pop gets under way a few frames later.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('details'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);

      // The page closing and the page it uncovers - already loaded - both zoom
      // as pictures, as they always did.
      expect(_drawnFromSnapshot(tester, find.text('details')), isTrue);
      expect(_drawnFromSnapshot(tester, find.text('home')), isTrue);

      await tester.pumpAndSettle();
      expect(find.text('details'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('Android keeps the platform transition', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final router = await pumpApp(tester);
    await midPush(tester, router);
    // Predictive back's fade has no zoom snapshot of the page coming in either
    // way; what matters is that it is not the desktop builder.
    expect(find.byType(SnapshotWidget), findsNothing);
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}

// Does a library grid stay put when a page opened from it is popped?
//
// Drives the real app on Windows: opens the first film or show library as a
// grid, walks the pad onto a card, opens it, comes back, and samples the page's
// scroll offset and the selected card every 100ms for three seconds after the
// pop. The samples are the finding: whatever moves, and when, is printed.
//
// Run: flutter test integration_test/dpad_grid_return_test.dart -d windows
//
// Needs Chudder closed and an account signed in - it boots the app as it is.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/main.dart' as app;
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/shared/grid_focus_traveler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a library grid keeps its place when a page opened from it pops', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 4));

    // Straight into a library grid, the way the Library tab's own button
    // would: onto the tab's stack, over the dashboard.
    final context = tester.element(find.byType(NavigationBody).first);
    final container = ProviderScope.containerOf(context);
    final views = container.read(viewsProvider).views;
    final view = views.firstWhere(
      (v) => v.collectionType == CollectionType.movies || v.collectionType == CollectionType.tvshows,
      orElse: () => views.first,
    );
    debugPrint('[grid-return] opening library ${view.name} (${view.collectionType})');
    context.router.push(LibrarySearchRoute(parentId: [view.id]));
    await _pumpUntil(tester, () => find.byType(GridFocusTraveler).evaluate().isNotEmpty, const Duration(seconds: 30));
    await _settle(tester, const Duration(seconds: 4));

    // Onto the grid and along it. The first press only puts the app in pad
    // mode; then down into the cards and right, so the card is not the first.
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 2; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    await _settle(tester, const Duration(seconds: 2));

    final opened = _selectedItemId();
    final placeBefore = _selectedRect();
    final offsetBefore = _pageOffset();
    debugPrint('[grid-return] before: card=$opened at $placeBefore page=${offsetBefore?.toStringAsFixed(1)}');
    expect(opened, isNotNull, reason: 'the pad never reached a grid card; nothing to test');

    await _press(tester, LogicalKeyboardKey.enter);
    await _settle(tester, const Duration(seconds: 6));
    debugPrint('[grid-return] opened, now on: ${_routeName(tester)}');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    // Every 100ms for three seconds: which card is selected, where it is, and
    // where the page is. A page that moves shows up as a changing offset.
    double? maxDrift = 0;
    for (var t = 0; t < 30; t++) {
      await _settle(tester, const Duration(milliseconds: 100));
      final offset = _pageOffset();
      final drift = offset == null || offsetBefore == null ? null : (offset - offsetBefore).abs();
      if (drift != null && drift > (maxDrift ?? 0)) maxDrift = drift;
      debugPrint('[grid-return] +${(t + 1) * 100}ms card=${_selectedItemId()} '
          'page=${offset?.toStringAsFixed(1)} rect=${_selectedRect()} route=${_routeName(tester)}');
    }

    final afterReturn = _selectedItemId();
    final placeAfter = _selectedRect();
    debugPrint('[grid-return] after: card=$afterReturn at $placeAfter page=${_pageOffset()?.toStringAsFixed(1)} '
        'max drift ${maxDrift?.toStringAsFixed(1)}');
    expect(afterReturn, opened, reason: 'came back to a different card than the one that was opened');
    expect(placeAfter, _closeTo(placeBefore!), reason: 'the card came back in a different place than it was left');
    expect(maxDrift, lessThan(1), reason: 'the page moved on the way back');
  });
}

String? _selectedItemId() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  return context.findAncestorWidgetOfExactType<PosterWidget>()?.poster.id;
}

Rect? _selectedRect() {
  final context = FocusManager.instance.primaryFocus?.context;
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The page the selected card is on: the nearest vertical scrollable above it.
double? _pageOffset() {
  var context = FocusManager.instance.primaryFocus?.context;
  while (context != null) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return null;
    if (scrollable.axisDirection == AxisDirection.down || scrollable.axisDirection == AxisDirection.up) {
      return scrollable.position.pixels;
    }
    context = scrollable.context;
    // Out of this scrollable, to the one above it.
    context = context.findAncestorStateOfType<ScrollableState>()?.context;
  }
  return null;
}

String _routeName(WidgetTester tester) {
  final context = tester.element(find.byType(NavigationBody).first);
  return ModalRoute.of(context)?.settings.name ?? 'unknown';
}

Matcher _closeTo(Rect expected) => predicate<Rect?>(
      (actual) =>
          actual != null &&
          (actual.left - expected.left).abs() < 1 &&
          (actual.top - expected.top).abs() < 1 &&
          (actual.width - expected.width).abs() < 1 &&
          (actual.height - expected.height).abs() < 1,
      'within a pixel of $expected',
    );

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, const Duration(milliseconds: 700));
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (done()) return;
  }
  fail('timed out waiting');
}

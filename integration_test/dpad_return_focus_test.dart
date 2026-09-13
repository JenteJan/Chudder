// Does the selection come back to the card it was left on?
//
// Drives the real app on Windows: walks the pad onto a poster, remembers which
// film it is, opens it, comes back, and asks what is selected now. The answer
// used to be a card to the left or right, or one in the row above or below,
// depending on where the rows happened to be scrolled.
//
// Run: flutter test integration_test/dpad_return_focus_test.dart -d windows
//
// Needs Chudder closed and an account signed in - it boots the app as it is.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chudder/main.dart' as app;
import 'package:chudder/screens/shared/media/poster_widget.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the selection comes back to the card it was opened from', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 4));

    // Onto the rows, then along one, so the selection is not on the first card
    // of the first row - which is where a page lands by accident anyway and so
    // proves nothing.
    for (var i = 0; i < 2; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    await _settle(tester, const Duration(seconds: 2));

    final opened = _selectedItemId();
    final placeBefore = _selectedRect();
    debugPrint('[return-focus] selected before opening: $opened at $placeBefore');
    expect(opened, isNotNull, reason: 'the pad never reached a poster; nothing to test');

    await _press(tester, LogicalKeyboardKey.enter);
    await _settle(tester, const Duration(seconds: 6));
    debugPrint('[return-focus] opened, now on: ${_routeName(tester)}');

    await _press(tester, LogicalKeyboardKey.escape);
    await _settle(tester, const Duration(seconds: 6));

    final afterReturn = _selectedItemId();
    final placeAfter = _selectedRect();
    debugPrint('[return-focus] selected after coming back: $afterReturn at $placeAfter');
    expect(
      afterReturn,
      opened,
      reason: 'came back to a different card than the one that was opened',
    );
    // And on the very same spot of the screen: neither the page nor the row
    // has moved under it.
    expect(
      placeAfter,
      _closeTo(placeBefore!),
      reason: 'the card came back in a different place than it was left',
    );
  });

  testWidgets('the selection walks across the row before the row scrolls', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 4));

    for (var i = 0; i < 2; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _settle(tester, const Duration(seconds: 2));
    expect(_selectedItemId(), isNotNull, reason: 'the pad never reached a poster; nothing to test');

    final row = Scrollable.of(FocusManager.instance.primaryFocus!.context!);
    final rowBox = row.context.findRenderObject()! as RenderBox;
    final rowRight = rowBox.localToGlobal(Offset(rowBox.size.width, 0)).dx;
    final startOffset = row.position.pixels;

    // Right, one card at a time. Until the selection reaches the last card
    // fully on screen the row must not move at all; after that it moves, and
    // the selected card is still wholly on screen.
    var scrolled = false;
    for (var i = 0; i < 12; i++) {
      final before = _selectedRect()!;
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _settle(tester, const Duration(milliseconds: 500));
      final after = _selectedRect()!;
      final offset = row.position.pixels;
      debugPrint('[row-walk] press $i: card $after, row offset ${offset.toStringAsFixed(1)}');
      if (row.position.pixels >= row.position.maxScrollExtent - 1) break;
      final nextFitsOnScreen = before.right + before.width + 8 <= rowRight;
      if (!scrolled && nextFitsOnScreen) {
        expect(offset, closeTo(startOffset, 0.5), reason: 'the row scrolled while the next card was already on screen');
      } else {
        scrolled = true;
        expect(offset, greaterThan(startOffset + 0.5), reason: 'the row did not scroll to reveal the next card');
        expect(after.right, lessThanOrEqualTo(rowRight + 0.5), reason: 'the selected card is cut off at the end');
      }
    }
    expect(scrolled, isTrue, reason: 'the walk never reached the end of the screen; the row is too short to test');
  });
}

/// Where the selected control is on screen, if one is.
Rect? _selectedRect() {
  final context = FocusManager.instance.primaryFocus?.context;
  final box = context?.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
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

/// The film whose card currently holds the selection, if one does.
String? _selectedItemId() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  return context.findAncestorWidgetOfExactType<PosterWidget>()?.poster.id;
}

String _routeName(WidgetTester tester) {
  final context = tester.element(find.byType(NavigationBody).first);
  return ModalRoute.of(context)?.settings.name ?? 'unknown';
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, const Duration(milliseconds: 700));
}

/// Pumps for a while. Not pumpAndSettle: the app always has something animating
/// - shimmer, a marquee - so settling never arrives.
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
  fail('timed out waiting for the app to come up');
}

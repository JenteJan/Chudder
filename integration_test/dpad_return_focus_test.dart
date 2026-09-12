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

import 'package:fladder/main.dart' as app;
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';

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
    debugPrint('[return-focus] selected before opening: $opened');
    expect(opened, isNotNull, reason: 'the pad never reached a poster; nothing to test');

    await _press(tester, LogicalKeyboardKey.enter);
    await _settle(tester, const Duration(seconds: 6));
    debugPrint('[return-focus] opened, now on: ${_routeName(tester)}');

    await _press(tester, LogicalKeyboardKey.escape);
    await _settle(tester, const Duration(seconds: 6));

    final afterReturn = _selectedItemId();
    debugPrint('[return-focus] selected after coming back: $afterReturn');
    expect(
      afterReturn,
      opened,
      reason: 'came back to a different card than the one that was opened',
    );
  });
}

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

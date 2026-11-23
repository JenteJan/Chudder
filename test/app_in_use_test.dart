// What moves by itself waits while the app is not the one in use.

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/app_in_use.dart';

void main() {
  testWidgets('follows the window: in use only while focused and shown', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(appInUse.value, isTrue);

    // Another window in front, a game for one.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(appInUse.value, isFalse);

    // Minimised.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(appInUse.value, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(appInUse.value, isTrue);
  });

  testWidgets('a moving pointer over an unfocused window uses it, for a while', (tester) async {
    await tester.pumpWidget(const SizedBox.expand());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(appInUse.value, isFalse);

    // The window on the second screen, used by mouse without a click.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(50, 50));
    expect(appInUse.value, isTrue);

    // The pointer comes to rest, and a game takes over.
    await tester.pump(kPointerInUse + const Duration(milliseconds: 100));
    expect(appInUse.value, isFalse);

    await mouse.removePointer();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}

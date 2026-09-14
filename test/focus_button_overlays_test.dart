import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/focus_provider.dart';

void main() {
  Future<void> pumpButton(WidgetTester tester, {bool forceFocusOutline = false, VoidCallback? onPlay}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: FocusButton(
                forceFocusOutline: forceFocusOutline,
                onTap: () {},
                focusedOverlays: [
                  Center(child: IconButton(onPressed: onPlay ?? () {}, icon: const Icon(Icons.play_arrow))),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('hover controls are not built until the button is hovered', (tester) async {
    await pumpButton(tester);
    expect(find.byType(IconButton), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(FocusButton)));
    await tester.pump();
    expect(find.byType(IconButton), findsOneWidget);

    // Fading in, then fully there.
    await tester.pump(const Duration(milliseconds: 100));
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.byType(IconButton), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fade.opacity.value, 1);

    // Leaving: still there while it fades, gone once it has.
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(IconButton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('a hovered control can be pressed', (tester) async {
    var played = 0;
    await pumpButton(tester, onPlay: () => played++);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(FocusButton)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IconButton), kind: PointerDeviceKind.mouse);
    expect(played, 1);
  });

  testWidgets('a button that always shows its outline builds its controls at once', (tester) async {
    await pumpButton(tester, forceFocusOutline: true);
    expect(find.byType(IconButton), findsOneWidget);
  });
}

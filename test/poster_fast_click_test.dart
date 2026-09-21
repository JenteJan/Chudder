import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/focus_provider.dart';

/// A card shaped like a poster: the press that opens it, and the controls that
/// fade in under the pointer while it is hovered.
void main() {
  late int opened;
  late int played;

  Future<void> pumpCard(WidgetTester tester) async {
    opened = 0;
    played = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: FocusButton(
                onTap: () => opened++,
                focusedOverlays: [
                  Center(child: IconButton(onPressed: () => played++, icon: const Icon(Icons.play_arrow))),
                ],
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Somewhere on the card that is not the middle, where the play button sits.
  Offset cornerOf(WidgetTester tester) {
    final rect = tester.getRect(find.byType(FocusButton));
    return Offset(rect.left + 20, rect.top + 20);
  }

  testWidgets('pressed the instant the pointer lands, before any hover frame', (tester) async {
    await pumpCard(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    final target = cornerOf(tester);
    await mouse.moveTo(target);
    await mouse.down(target);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(opened, 1, reason: 'a press on arrival opens the card');
    expect(played, 0);
  });

  testWidgets('pressed while the hover controls are fading in', (tester) async {
    await pumpCard(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    final target = cornerOf(tester);
    await mouse.moveTo(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    await mouse.down(target);
    await tester.pump(const Duration(milliseconds: 16));
    await mouse.up();
    await tester.pump();

    expect(opened, 1, reason: 'a press during the fade opens the card');
    expect(played, 0);
  });

  testWidgets('pressed in the middle while the play button is still invisible', (tester) async {
    await pumpCard(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    final centre = tester.getCenter(find.byType(FocusButton));
    await mouse.moveTo(centre);
    await tester.pump();

    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.byType(IconButton), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 0, reason: 'the controls have not faded in yet');

    await mouse.down(centre);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect([opened, played], [1, 0], reason: 'the invisible play button must not take the press');
  });

  testWidgets('pressed after the hover animation has settled', (tester) async {
    await pumpCard(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    final target = cornerOf(tester);
    await mouse.moveTo(target);
    await tester.pumpAndSettle();

    await mouse.down(target);
    await tester.pump();
    await mouse.up();
    await tester.pump();

    expect(opened, 1);
  });
}

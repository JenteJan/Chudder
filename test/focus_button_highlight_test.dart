import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/focus_provider.dart';

/// The mark a button wears while it is hovered or selected, and what it costs
/// the buttons that never are.
void main() {
  Future<void> pumpButton(WidgetTester tester, {bool autoFocus = false, bool forced = false}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: FocusButton(
                  autoFocus: autoFocus,
                  forceFocusOutline: forced,
                  onTap: () {},
                  focusedOverlays: [
                    Center(child: IconButton(onPressed: () {}, icon: const Icon(Icons.play_arrow))),
                  ],
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );

  /// What is painted over the button: nothing, until there is a mark to show.
  CustomPainter? mark(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.descendant(of: find.byType(FocusButton), matching: find.byType(CustomPaint)))
      .first
      .foregroundPainter;

  testWidgets('a button nobody is on paints no mark and runs no animation', (tester) async {
    await pumpButton(tester);
    await tester.pump();
    expect(mark(tester), isNull);
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('the pointer arriving fades the mark and the controls in, and leaving fades them out', (tester) async {
    await pumpButton(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    await mouse.moveTo(tester.getCenter(find.byType(FocusButton)));
    await tester.pump();
    expect(mark(tester), isNotNull);
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'fading in');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'fading out');
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('a selected button wears the mark', (tester) async {
    await pumpButton(tester, autoFocus: true);
    await tester.pumpAndSettle();
    expect(mark(tester), isNotNull);
  });

  testWidgets('a button told to show the mark has it from the first frame, without a fade', (tester) async {
    await pumpButton(tester, forced: true);
    expect(mark(tester), isNotNull);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('the selection stays on the button: nothing inside it can take it', (tester) async {
    await pumpButton(tester, autoFocus: true);
    await tester.pumpAndSettle();
    final button = tester.state<FocusButtonState>(find.byType(FocusButton)).focusNode;
    expect(button.hasPrimaryFocus, isTrue);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    final inner = Focus.of(tester.element(find.byIcon(Icons.play_arrow)));
    expect(inner, isNot(button));
    expect(inner.canRequestFocus, isFalse);

    FocusManager.instance.primaryFocus!.nextFocus();
    await tester.pump();
    expect(button.hasPrimaryFocus, isTrue, reason: 'there is nowhere else on the page for it to go');
  });
}

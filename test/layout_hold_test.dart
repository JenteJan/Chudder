import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/layout_hold.dart';

void main() {
  BoxConstraints screen(double width) => BoxConstraints.tight(Size(width, 600));

  testWidgets('takes the first size at once, then holds it while the layout keeps changing', (tester) async {
    final settled = <double>[];
    final hold = LayoutHold(onSettled: settled.add);
    addTearDown(hold.dispose);

    expect(hold.resolve(screen(1000), 400), 400);
    expect(hold.moving, isFalse);

    // A drag: a new width every frame.
    for (var width = 990.0; width >= 800; width -= 10) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(hold.resolve(screen(width), width * 0.4), 400);
      expect(hold.moving, isTrue);
    }
    // The same frame again, still mid-drag: still held.
    expect(hold.resolve(screen(800), 320), 400);
    expect(settled, isEmpty);

    // The layout holds still: the hold lets go, and the next build takes the new size.
    await tester.pump(const Duration(milliseconds: 300));
    expect(settled, [320]);
    expect(hold.moving, isFalse);
    expect(hold.resolve(screen(800), 320), 320);
  });

  testWidgets('a layout that settles back where it started still says so', (tester) async {
    final settled = <double>[];
    final hold = LayoutHold(onSettled: settled.add);
    addTearDown(hold.dispose);

    expect(hold.resolve(screen(1000), 400), 400);
    await tester.pump(const Duration(milliseconds: 16));
    expect(hold.resolve(screen(900), 360), 400);
    await tester.pump(const Duration(milliseconds: 16));
    expect(hold.resolve(screen(1000), 400), 400);
    await tester.pump(const Duration(milliseconds: 300));
    expect(settled, [400]);
    expect(hold.moving, isFalse);
    expect(hold.resolve(screen(1000), 400), 400);
  });

  testWidgets('a change in what is wanted without a layout change goes through at once', (tester) async {
    final hold = LayoutHold(onSettled: (_) {});
    addTearDown(hold.dispose);

    expect(hold.resolve(screen(1000), 400), 400);
    // Same constraints, the layout picked something else (a different view size, say).
    expect(hold.resolve(screen(1000), 450), 450);
  });
}

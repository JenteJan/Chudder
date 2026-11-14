import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/routes/zoom_opening.dart';

/// The page opening on a desktop is zoomed from a picture of it, taken again
/// when the page changes - drawn live every frame, a film page was more than a
/// large window's GPU could draw in a frame.
void main() {
  late int paints;
  late ValueNotifier<int> content;

  Widget page() => ZoomOpeningProbe(
        child: CustomPaint(
          size: const Size(400, 300),
          painter: _CountingPainter(content, () => paints++),
        ),
      );

  Future<NavigatorState> open(WidgetTester tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox()));
    navigator.currentState!.push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          ZoomOpening(animation: animation, child: child),
    ));
    return navigator.currentState!;
  }

  setUp(() {
    paints = 0;
    content = ValueNotifier(0);
  });

  testWidgets('the opening page is drawn a few times, not every frame', (tester) async {
    await open(tester);
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(paints, lessThanOrEqualTo(3), reason: '15 frames of zoom from a picture');
  });

  testWidgets('a change while it opens is drawn once, not once a frame', (tester) async {
    await open(tester);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = paints;
    content.value++;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(paints - before, 1, reason: 'one new picture for the change');
  });

  testWidgets('once open the page is live', (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    final before = paints;
    content.value++;
    await tester.pump();
    expect(paints, before + 1);
  });
}

class _CountingPainter extends CustomPainter {
  _CountingPainter(this.content, this.onPaint) : super(repaint: content);

  final ValueNotifier<int> content;
  final VoidCallback onPaint;

  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    canvas.drawRect(Offset.zero & size, Paint()..color = Color(0xFF000000 + content.value * 40));
  }

  @override
  bool shouldRepaint(_CountingPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/widgets/shared/modal_bottom_sheet.dart';

void main() {
  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                builder: (context) => DismissOnOverscroll(
                  child: ListView(
                    // Clamped as on Android, whatever the test host is.
                    physics: const ClampingScrollPhysics(),
                    children: [for (var i = 0; i < 40; i++) ListTile(title: Text('Row $i'))],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);
  }

  testWidgets('pulling the list down past its top closes the sheet', (tester) async {
    await openSheet(tester);

    await tester.drag(find.text('Row 2'), const Offset(0, 160));
    await tester.pumpAndSettle();

    expect(find.text('Row 0'), findsNothing);
  });

  testWidgets('scrolling the list, and back up to its top, leaves the sheet open', (tester) async {
    await openSheet(tester);

    await tester.drag(find.text('Row 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsOneWidget);
  });
}

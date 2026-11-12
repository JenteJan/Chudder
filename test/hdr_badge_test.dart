import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/screens/video_player/components/hdr_badge.dart';
import 'package:chudder/wrappers/players/windows_hdr.dart';

void main() {
  tearDown(() => WindowsHdr.active.value = false);

  Widget host() => const MaterialApp(home: Scaffold(body: Center(child: HdrBadge())));

  testWidgets('shows nothing while the picture is SDR', (tester) async {
    WindowsHdr.active.value = false;
    await tester.pumpWidget(host());
    expect(find.text('HDR'), findsNothing);
  });

  testWidgets('appears and disappears with HDR output', (tester) async {
    await tester.pumpWidget(host());
    WindowsHdr.active.value = true;
    await tester.pump();
    expect(find.text('HDR'), findsOneWidget);

    WindowsHdr.active.value = false;
    await tester.pump();
    expect(find.text('HDR'), findsNothing);
  });

  testWidgets('takes no focus, so remote navigation passes it by', (tester) async {
    WindowsHdr.active.value = true;
    await tester.pumpWidget(host());
    expect(
      find.descendant(of: find.byType(HdrBadge), matching: find.byType(Focus)),
      findsNothing,
    );
  });
}

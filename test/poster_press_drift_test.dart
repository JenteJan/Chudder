import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/widgets/shared/pinch_poster_zoom.dart';

/// A poster on a page that offers pinch-to-zoom, pressed by a mouse that is
/// still moving - which is every press made without stopping the pointer
/// first. A scale recognizer claims a mouse a pixel or two in, well inside the
/// eighteen a tap is allowed to drift, so it used to take the press and the
/// card under it never heard about it.
void main() {
  late int opened;

  Future<void> pumpGrid(WidgetTester tester, {bool pinchZoom = false}) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    opened = 0;
    await tester.pumpWidget(
      ProviderScope(
        // The settings write behind the toggle is debounced and real; give it
        // somewhere to land rather than leave a timer throwing after the test.
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: MaterialApp(
          home: Scaffold(
            body: PinchPosterZoom(
              scaleDifference: (_) {},
              child: Center(
                child: SizedBox(
                  width: 200,
                  height: 300,
                  child: FocusButton(
                    onTap: () => opened++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (pinchZoom) {
      ProviderScope.containerOf(tester.element(find.byType(PinchPosterZoom)))
          .read(clientSettingsProvider.notifier)
          .update((current) => current.copyWith(pinchPosterZoom: true));
      await tester.pump();
    }
  }

  /// Press with [drift] logical pixels of movement between down and up.
  Future<void> pressWithDrift(WidgetTester tester, double drift) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    final target = tester.getCenter(find.byType(FocusButton));
    await mouse.moveTo(target);
    await tester.pump();
    await mouse.down(target);
    await tester.pump(const Duration(milliseconds: 8));
    if (drift > 0) {
      await mouse.moveTo(target + Offset(drift, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await mouse.up();
    await tester.pump();
  }

  testWidgets('a press that does not move opens the card', (tester) async {
    await pumpGrid(tester);
    await pressWithDrift(tester, 0);
    expect(opened, 1);
  });

  testWidgets('a press that slides a few pixels still opens the card', (tester) async {
    await pumpGrid(tester);
    // From a real session's log: presses drifted 4 to 20 pixels and did
    // nothing at all, while the few that did not move opened the card.
    await pressWithDrift(tester, 6);
    expect(opened, 1, reason: 'the pinch gesture must not take a press a mouse only slid');
  });

  testWidgets('a press that slides far still opens the card', (tester) async {
    await pumpGrid(tester);
    await pressWithDrift(tester, 16);
    expect(opened, 1);
  });

  testWidgets('with pinch zoom switched on, a mouse press still belongs to the card', (tester) async {
    await pumpGrid(tester, pinchZoom: true);
    await pressWithDrift(tester, 6);
    expect(opened, 1, reason: 'a mouse cannot pinch, so the zoom has no business taking its press');
    // The settings write is debounced; let it run rather than leave it pending.
    await tester.pump(const Duration(seconds: 2));
  });
}

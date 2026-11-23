// The remote's keyboard types where its caret is, and the arrows move it.

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/widgets/keyboard/slide_in_keyboard.dart';

import 'dpad/dpad_walk.dart';

Future<void> _press(WidgetTester tester, Finder key) async {
  await tester.tap(key);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  test('the keyboard is wide enough for its keys, within bounds', () {
    expect(keyboardWidthFactor(1920), closeTo(640 / 1920, 0.001));
    expect(keyboardWidthFactor(3840), 0.25);
    expect(keyboardWidthFactor(960), 0.45);
  });

  testWidgets('keys type at the caret, arrows move it, backspace takes the letter before it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = TextEditingController(text: 'jelyfin');
    await pumpDpad(
      tester,
      overrides: [sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance())],
      child: CustomKeyboardWrapper(
        child: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => openKeyboard(context, controller, inputType: TextInputType.url),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await _press(tester, find.text('open'));
    await tester.pump(const Duration(milliseconds: 300));

    final left = find.byIcon(Icons.chevron_left_rounded);
    final right = find.byIcon(Icons.chevron_right_rounded);
    expect(left, findsOneWidget);

    // jel|yfin -> jell|yfin
    for (var i = 0; i < 4; i++) {
      await _press(tester, left);
    }
    await _press(tester, find.text('l').first);
    expect(controller.text, 'jellyfin');
    expect(controller.selection.baseOffset, 4);

    // Past the end stays at the end; backspace there takes the last letter.
    for (var i = 0; i < 10; i++) {
      await _press(tester, right);
    }
    await _press(tester, find.byIcon(Icons.backspace_rounded));
    expect(controller.text, 'jellyfi');

    // The device keyboard types into a real field, which has to take focus.
    await _press(tester, find.text('Use the device keyboard'));
    await tester.pump(const Duration(milliseconds: 100));
    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
  });
}

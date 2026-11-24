import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/widgets/shared/card_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

  test('focus selects a card for a keyboard or remote', () {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final selection = PreviewSelection()..focused = true;
    expect(selection.active.value, isTrue);
    selection.dispose();
  });

  test('focus handed back on a touch screen selects nothing', () {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    final selection = PreviewSelection()..focused = true;
    expect(selection.active.value, isFalse);
    selection.dispose();
  });

  test('a touch drops the selection a remote had made', () {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    final selection = PreviewSelection()..focused = true;
    expect(selection.active.value, isTrue);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    expect(selection.active.value, isFalse);
    selection.dispose();
  });

  test('hover selects whatever the focus mode', () {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    final selection = PreviewSelection()..hovered = true;
    expect(selection.active.value, isTrue);
    selection.dispose();
  });
}

// A pad on the Settings search field: the selection rests on the field and
// the arrows move on, rather than a caret keeping them.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/screens/settings/settings_search.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/util/poster_defaults.dart';

AdaptiveLayoutModel _layout(InputDevice input) => AdaptiveLayoutModel(
      viewSize: ViewSize.desktop,
      layoutMode: LayoutMode.dual,
      inputDevice: input,
      platform: TargetPlatform.windows,
      isDesktop: true,
      posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
      controller: const {},
      sideBarWidth: 0,
      topBarHeight: 0,
      statusBarHeight: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  InputDevice input = InputDevice.dPad,
  ValueChanged<String>? onChanged,
  List<String> Function(String query)? suggestions,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = TextEditingController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveLayout(
          data: _layout(input),
          child: Scaffold(
            body: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Column(
                children: [
                  SettingsSearchField(
                    controller: controller,
                    query: '',
                    onChanged: onChanged ?? (_) {},
                    suggestions: suggestions,
                  ),
                  TextButton(autofocus: true, onPressed: () {}, child: const Text('First')),
                  TextButton(onPressed: () {}, child: const Text('Second')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What has the selection: the text itself, the field around it, or a row.
String _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'nothing';
  if (context.widget is EditableText || context.findAncestorStateOfType<EditableTextState>() != null) return 'caret';
  if (context.findAncestorWidgetOfExactType<SettingsSearchField>() != null) return 'field';
  String? text;
  void visit(Element element) {
    if (text != null) return;
    final widget = element.widget;
    if (widget is Text) {
      text = widget.data;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return text ?? context.widget.runtimeType.toString();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('up from the list rests on the field, and down leaves it again', (tester) async {
    await _pump(tester);
    expect(_focused(), 'First');

    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'field', reason: 'the field as a whole, not a caret that keeps the arrows');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'First');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focused(), 'Second');
  });

  testWidgets('the hint sits in the middle of the field', (tester) async {
    await _pump(tester, input: InputDevice.pointer);
    final pill = tester.getRect(
      find.descendant(of: find.byType(SettingsSearchField), matching: find.byType(AnimatedContainer)).first,
    );
    final hint = tester.getRect(find.text('Search').first);
    expect((hint.center.dy - pill.center.dy).abs(), lessThan(3));
  });

  testWidgets('the keyboard filters as it is typed on, and suggests settings', (tester) async {
    final changes = <String>[];
    await _pump(
      tester,
      onChanged: changes.add,
      suggestions: (query) => ['Video scaling', 'Video player'].where((s) => s.toLowerCase().contains(query)).toList(),
    );
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focused(), 'field');
    await _press(tester, LogicalKeyboardKey.enter);

    await tester.tap(find.widgetWithText(ElevatedButton, 'v'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'i'));
    await tester.pumpAndSettle();
    expect(changes, ['v', 'vi'], reason: 'each key reaches the page while the keyboard is open');
    expect(find.text('Video scaling'), findsOneWidget);
    expect(find.text('Video player'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.backspace_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.backspace_rounded));
    await tester.pumpAndSettle();
    // Nothing left to delete: no crash, and nothing more to report.
    await tester.tap(find.byIcon(Icons.backspace_rounded));
    await tester.pumpAndSettle();
    expect(changes, ['v', 'vi', 'v', '']);
  });
}

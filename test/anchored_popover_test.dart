import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/screens/shared/chips/category_chip.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';
import 'package:fladder/widgets/shared/anchored_popover.dart';

const _phone = Size(360, 740);

AdaptiveLayoutModel _layout(InputDevice input) => AdaptiveLayoutModel(
      viewSize: ViewSize.phone,
      layoutMode: LayoutMode.single,
      inputDevice: input,
      platform: TargetPlatform.android,
      isDesktop: false,
      posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
      controller: const {},
      sideBarWidth: 0,
      topBarHeight: 0,
      statusBarHeight: 0,
    );

/// A page under a router whose back button pops "the page".
class _PageDelegate extends RouterDelegate<Object> with ChangeNotifier {
  final WidgetBuilder builder;
  int pops = 0;
  _PageDelegate(this.builder);

  @override
  Widget build(BuildContext context) => builder(context);

  @override
  Future<bool> popRoute() {
    pops++;
    return SynchronousFuture(true);
  }

  @override
  Future<void> setNewRoutePath(Object configuration) => SynchronousFuture(null);
}

Future<_PageDelegate> _pump(
  WidgetTester tester, {
  required InputDevice input,
  required Widget Function(BuildContext context) page,
  Size size = _phone,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final delegate = _PageDelegate(page);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AdaptiveLayout(
        data: _layout(input),
        child: Router(routerDelegate: delegate, backButtonDispatcher: RootBackButtonDispatcher()),
      ),
    ),
  );
  return delegate;
}

/// A button filling the page behind the chip, and the chip near the right
/// edge, where a 300 wide panel cannot hang flush with it.
Widget _pageWithPopover({required VoidCallback onBackgroundTap, double width = 400}) => Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TextButton(key: const Key('background'), onPressed: onBackgroundTap, child: const SizedBox()),
          ),
          Positioned(
            top: 100,
            left: 280,
            child: AnchoredPopover(
              width: width,
              maxHeight: 600,
              anchorBuilder: (context, controller) =>
                  TextButton(key: const Key('anchor'), onPressed: controller.toggle, child: const Text('Open')),
              popoverBuilder: (context, controller) => ListView(
                key: const Key('panel'),
                shrinkWrap: true,
                children: List.generate(40, (i) => SizedBox(height: 40, child: Text('Row $i'))),
              ),
            ),
          ),
        ],
      ),
    );

Rect _panelRect(WidgetTester tester) => tester.getRect(
      find.ancestor(of: find.byKey(const Key('panel')), matching: find.byType(Material)).first,
    );

void main() {
  testWidgets('stays inside a phone screen', (tester) async {
    await _pump(tester, input: InputDevice.touch, page: (_) => _pageWithPopover(onBackgroundTap: () {}));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();

    final rect = _panelRect(tester);
    expect(rect.width, _phone.width - 16);
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(_phone.width - 8));
    expect(rect.bottom, lessThanOrEqualTo(_phone.height));
  });

  testWidgets('shrinks above the keyboard', (tester) async {
    await _pump(tester, input: InputDevice.touch, page: (_) => _pageWithPopover(onBackgroundTap: () {}));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();
    expect(_panelRect(tester).bottom, greaterThan(_phone.height - 300));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(_panelRect(tester).bottom, lessThanOrEqualTo(_phone.height - 300));
  });

  testWidgets('on touch, the tap that closes it does not reach the page', (tester) async {
    var taps = 0;
    await _pump(tester, input: InputDevice.touch, page: (_) => _pageWithPopover(onBackgroundTap: () => taps++));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
    expect(taps, 0);
  });

  testWidgets('with a pointer, the tap that closes it still lands', (tester) async {
    var taps = 0;
    await _pump(tester, input: InputDevice.pointer, page: (_) => _pageWithPopover(onBackgroundTap: () => taps++));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(40, 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
    expect(taps, 1);
  });

  testWidgets('a press right after hovering opened it leaves it open', (tester) async {
    await _pump(tester,
        input: InputDevice.pointer, size: const Size(800, 900), page: (_) => _pageWithPopover(onBackgroundTap: () {}));
    final anchor = find.byKey(const Key('anchor'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(anchor));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);

    // The click that meant to open it: nothing happens.
    await gesture.down(tester.getCenter(anchor));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);

    // Settled: a press closes it.
    await tester.pump(const Duration(seconds: 2));
    await gesture.down(tester.getCenter(anchor));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
  });

  testWidgets('a press that opened it closes it straight away', (tester) async {
    await _pump(tester, input: InputDevice.pointer, page: (_) => _pageWithPopover(onBackgroundTap: () {}));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
  });

  testWidgets('back closes the panel, not the page', (tester) async {
    final delegate =
        await _pump(tester, input: InputDevice.touch, page: (_) => _pageWithPopover(onBackgroundTap: () {}));
    await tester.tap(find.byKey(const Key('anchor')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
    expect(delegate.pops, 0);

    await tester.binding.handlePopRoute();
    expect(delegate.pops, 1);
  });

  group('CategoryChip search', () {
    Future<void> openChip(WidgetTester tester, {required bool searchable}) async {
      await _pump(
        tester,
        input: InputDevice.touch,
        page: (_) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CategoryChip<String>(
              label: const Text('Chip'),
              items: {for (var i = 0; i < 12; i++) 'Item $i': false},
              labelBuilder: Text.new,
              searchable: searchable,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Chip'));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);
    }

    testWidgets('a fixed list has none', (tester) async {
      await openChip(tester, searchable: false);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a long open-ended list has one', (tester) async {
      await openChip(tester, searchable: true);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('CategoryChip ticks', () {
    testWidgets('a ticked row stays where it is and applies a moment later', (tester) async {
      Map<String, bool>? saved;
      await _pump(
        tester,
        input: InputDevice.pointer,
        size: const Size(800, 1200),
        page: (_) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StatefulBuilder(
              builder: (context, setState) => CategoryChip<String>(
                label: const Text('Chip'),
                items: saved ?? {for (var i = 0; i < 12; i++) 'Item $i': i == 1},
                labelBuilder: Text.new,
                onSave: (value) => setState(() => saved = value),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Chip'));
      await tester.pumpAndSettle();
      // Ticked when the panel opened: once at the top, and once in its place.
      expect(find.text('Item 1'), findsNWidgets(2));

      final before = tester.getRect(find.text('Item 5'));
      await tester.tap(find.text('Item 5'));
      await tester.pump();
      expect(tester.getRect(find.text('Item 5')), before);
      expect(saved, isNull);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(saved?['Item 5'], isTrue);
      expect(tester.getRect(find.text('Item 5')), before);
      expect(find.text('Item 5'), findsOneWidget);
    });

    testWidgets('clear goes back to the defaults when there are any', (tester) async {
      Map<String, bool>? saved;
      await _pump(
        tester,
        input: InputDevice.pointer,
        page: (_) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CategoryChip<String>(
              label: const Text('Chip'),
              items: const {'A': false, 'B': true},
              defaults: const {'A': true, 'B': false},
              labelBuilder: Text.new,
              onSave: (value) => saved = value,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Chip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(saved, {'A': true, 'B': false});
    });
  });

  group('on a pad', () {
    FocusNode chipNode(WidgetTester tester, String label) => Focus.of(tester.element(find.text(label)));

    String? focusedText() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return null;
      if (context.findAncestorStateOfType<EditableTextState>() != null) return 'search';
      String? text;
      void visit(Element element) {
        if (text != null) return;
        final widget = element.widget;
        if (widget is Text && widget.data != null) {
          text = widget.data;
          return;
        }
        element.visitChildren(visit);
      }

      (context as Element).visitChildren(visit);
      return text;
    }

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    Future<void> pumpRow(WidgetTester tester) async {
      Widget chip(String name, {bool searchable = false}) => CategoryChip<String>(
            label: Text(name),
            items: {for (var i = 0; i < 12; i++) '$name$i': false},
            labelBuilder: Text.new,
            searchable: searchable,
            onSave: (_) {},
          );
      await _pump(
        tester,
        input: InputDevice.dPad,
        size: const Size(1200, 900),
        page: (_) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: Row(children: [chip('A'), chip('B', searchable: true), chip('C')]),
            ),
          ),
        ),
      );
    }

    Future<void> openB(WidgetTester tester) async {
      chipNode(tester, 'B').requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);
    }

    testWidgets('opens on the first choice, not the search box', (tester) async {
      await pumpRow(tester);
      await openB(tester);
      expect(focusedText(), 'B0');
    });

    testWidgets('up off the top leaves the panel for its chip', (tester) async {
      await pumpRow(tester);
      await openB(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedText(), 'B1');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'B0');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'search');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(find.text('B0'), findsNothing);
      expect(focusedText(), 'B');
    });

    testWidgets('left and right leave the panel for the chip beside it', (tester) async {
      await pumpRow(tester);
      await openB(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('B0'), findsNothing);
      expect(focusedText(), 'C');

      await openB(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(find.text('B0'), findsNothing);
      expect(focusedText(), 'A');
    });

    testWidgets('the search box lets go of the selection', (tester) async {
      await pumpRow(tester);
      await openB(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'search');

      await tester.enterText(find.byType(TextField), 'B1');
      await tester.pumpAndSettle();
      // The caret at the end of the text: left moves it rather than leaving.
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedText(), 'search');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedText(), 'B1');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedText(), 'search');
      await press(tester, LogicalKeyboardKey.backspace);
      expect(find.byType(TextField), findsOneWidget, reason: 'backspace deletes in the search box');
      // Caret back at the end.
      await press(tester, LogicalKeyboardKey.end);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('B0'), findsNothing);
      expect(focusedText(), 'C');
    });
  });
}

// A pad around the library page's edges: the letter strip, and the search
// field above the chips.
//
// Widget-level, with the pieces the traversal actually reads - focus nodes and
// their rectangles - rather than the whole page, which needs a server.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/screens/library_search/widgets/alphabet_scrubber.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/util/poster_defaults.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';

const _window = Size(800, 600);

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

Future<void> _pump(WidgetTester tester, Widget page, {InputDevice input = InputDevice.dPad}) async {
  tester.view.physicalSize = _window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AdaptiveLayout(
        data: _layout(input),
        child: FocusTraversalGroup(
          policy: GlobalFallbackTraversalPolicy(),
          child: page,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The letter under the selection, or the widget that has it.
String _focused() {
  final node = FocusManager.instance.primaryFocus;
  final context = node?.context;
  if (context == null) return 'nothing';
  String? letter;
  void visit(Element element) {
    if (letter != null) return;
    final widget = element.widget;
    if (widget is Text && widget.data != null) {
      letter = widget.data;
      return;
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  if (letter != null) return 'letter:$letter';
  return '${context.widget.runtimeType} ${node?.debugLabel ?? ''}';
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

/// A page the way the library lays it out: a card on the left, the strip down
/// the right edge, and a control ending under the strip's top - the poster
/// size slider's spot, which Flutter's own search used to prefer to the next
/// letter.
Widget _libraryPage({
  required FocusNode card,
  required FocusNode decoy,
  Key? stripKey,
  String? selected,
}) =>
    Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 20,
            top: 120,
            width: 120,
            height: 400,
            child: TextButton(key: const ValueKey('card'), focusNode: card, onPressed: () {}, child: const SizedBox()),
          ),
          Positioned(
            right: 8,
            top: 110,
            width: 150,
            height: 24,
            child: TextButton(key: const ValueKey('decoy'), focusNode: decoy, onPressed: () {}, child: const SizedBox()),
          ),
          Positioned(
            top: 100,
            bottom: 40,
            right: 8,
            child: AlphabetScrubber(key: stripKey, selected: selected, onSelected: (_) {}),
          ),
        ],
      ),
    );

void main() {
  setUp(() => lastMainFocus = null);

  group('the letter strip', () {
    testWidgets('lands on its first letter and walks down one letter at a time', (tester) async {
      final card = FocusNode();
      final decoy = FocusNode();
      addTearDown(() {
        card.dispose();
        decoy.dispose();
      });
      await _pump(tester, _libraryPage(card: card, decoy: decoy));

      final strip = alphabetScrubberNodeFor(card);
      expect(strip, isNotNull, reason: 'the card and the strip are on one page');
      strip!.requestFocus();
      await tester.pump();
      expect(_focused(), 'letter:#');

      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused(), 'letter:A', reason: 'down is the next letter, not the control under the strip');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused(), 'letter:B');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focused(), 'letter:A');
    });

    testWidgets('stops at both ends', (tester) async {
      final card = FocusNode();
      final decoy = FocusNode();
      addTearDown(() {
        card.dispose();
        decoy.dispose();
      });
      await _pump(tester, _libraryPage(card: card, decoy: decoy, selected: 'Z'));

      alphabetScrubberNodeFor(card)!.requestFocus();
      await tester.pump();
      expect(_focused(), 'letter:Z', reason: 'landing on the strip lands on the active letter');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focused(), 'letter:Z', reason: 'nothing below the last letter');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focused(), 'letter:Z', reason: 'nothing to the right of the strip');

      for (var i = 0; i < 30; i++) {
        await _press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(_focused(), 'letter:#', reason: 'nothing above the first letter');
    });

    testWidgets('left goes back to the card the selection came from', (tester) async {
      final card = FocusNode();
      final decoy = FocusNode();
      addTearDown(() {
        card.dispose();
        decoy.dispose();
      });
      await _pump(tester, _libraryPage(card: card, decoy: decoy));

      lastMainFocus = card;
      alphabetScrubberNodeFor(card)!.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(identical(FocusManager.instance.primaryFocus, card), isTrue, reason: 'was on ${_focused()}');
    });

    testWidgets('left with nothing remembered goes to the card beside the letter', (tester) async {
      final card = FocusNode();
      final decoy = FocusNode();
      addTearDown(() {
        card.dispose();
        decoy.dispose();
      });
      await _pump(tester, _libraryPage(card: card, decoy: decoy));

      alphabetScrubberNodeFor(card)!.requestFocus();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await _press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(_focused(), 'letter:H');
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(identical(FocusManager.instance.primaryFocus, card), isTrue, reason: 'was on ${_focused()}');
    });

    testWidgets('a grid finds the strip on its own page, not another tab\'s', (tester) async {
      final cardA = FocusNode();
      final decoyA = FocusNode();
      final cardB = FocusNode();
      final decoyB = FocusNode();
      addTearDown(() {
        for (final node in [cardA, decoyA, cardB, decoyB]) {
          node.dispose();
        }
      });
      // Two pages alive at once, each in a scope of its own, the way every
      // Home tab keeps its page. B mounts last, so a single "the strip"
      // variable would have pointed at B for a press made on A.
      await _pump(
        tester,
        Row(
          children: [
            Expanded(
              child: FocusScope(
                child: _libraryPage(card: cardA, decoy: decoyA, stripKey: const ValueKey('stripA')),
              ),
            ),
            Expanded(
              child: FocusScope(
                child: _libraryPage(card: cardB, decoy: decoyB, stripKey: const ValueKey('stripB')),
              ),
            ),
          ],
        ),
      );

      final stripForA = alphabetScrubberNodeFor(cardA)!;
      final stripForB = alphabetScrubberNodeFor(cardB)!;
      expect(identical(stripForA, stripForB), isFalse);

      stripForA.requestFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        focused.findAncestorWidgetOfExactType<AlphabetScrubber>()!.key,
        const ValueKey('stripA'),
      );
    });
  });

  group('the search field', () {
    testWidgets('is a control, not a group, though the text inside it can take focus', (tester) async {
      // The shape OutlinedTextField gives a field on a pad: a wrapper node
      // that catches keys, with the text kept out of traversal but still
      // focusable, and a listener node around the lot.
      final outer = FocusNode(debugLabel: 'outer');
      final wrapper = FocusNode(debugLabel: 'wrapper');
      final text = FocusNode(debugLabel: 'text');
      final chip = FocusNode(debugLabel: 'chip');
      addTearDown(() {
        for (final node in [outer, wrapper, text, chip]) {
          node.dispose();
        }
      });
      await _pump(
        tester,
        Scaffold(
          body: Column(
            children: [
              Focus(
                focusNode: outer,
                child: Focus(
                  focusNode: wrapper,
                  child: ExcludeFocusTraversal(
                    child: SizedBox(width: 300, child: TextField(focusNode: text)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(focusNode: chip, onPressed: () {}, child: const Text('Libraries')),
                ],
              ),
            ],
          ),
        ),
      );

      expect(isFocusGroup(outer), isTrue);
      expect(isFocusGroup(wrapper), isFalse, reason: 'the text under it is not traversable');
      expect(isFocusGroup(chip), isFalse);

      expect(
        identical(verticalNeighbour(chip, TraversalDirection.up), wrapper),
        isTrue,
        reason: 'up from the chip is the field, not the listener node around it',
      );
      expect(identical(firstPageControl(chip), wrapper), isTrue);
    });
  });
}

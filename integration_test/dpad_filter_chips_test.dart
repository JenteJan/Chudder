// Does a remote get around the library's filter chips and their panels?
//
// Drives the real app on Windows: opens the first film or show library, puts
// the app in pad mode, and walks the chips the way a remote would - into a
// panel and out of it every way there is, and Favourites through its three
// states - printing where the selection is after every press.
//
// Run: flutter test integration_test/dpad_filter_chips_test.dart -d windows
//
// Needs Chudder closed and an account signed in - it boots the app as it is.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/main.dart' as app;
import 'package:chudder/models/library_search/library_search_model.dart';
import 'package:chudder/providers/library_search_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/library_search/widgets/library_filter_chips.dart';
import 'package:chudder/screens/shared/media/poster_widget.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/shared/anchored_popover.dart';
import 'package:chudder/widgets/shared/button_group.dart';
import 'package:chudder/widgets/shared/grid_focus_traveler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a remote walks the filter chips and their panels', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 4));

    final context = tester.element(find.byType(NavigationBody).first);
    final l10n = AppLocalizations.of(context);
    final container = ProviderScope.containerOf(context);
    final views = container.read(viewsProvider).views;
    final view = views.firstWhere(
      (v) => v.collectionType == CollectionType.movies || v.collectionType == CollectionType.tvshows,
      orElse: () => views.first,
    );
    debugPrint('[chips] opening library ${view.name}');
    context.router.push(LibrarySearchRoute(parentId: [view.id]));
    await _pumpUntil(tester, () => find.byType(GridFocusTraveler).evaluate().isNotEmpty, const Duration(seconds: 30));
    await _settle(tester, const Duration(seconds: 4));
    final pageKey = tester.widget(find.byType(LibraryFilterChips)).key!;
    final notifier = container.read(librarySearchProvider(pageKey).notifier);

    // Into pad mode.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _log('pad mode');

    // Favourites, three times over: on, not favourites, off.
    await _selectChip(tester, l10n.favorites);
    for (var i = 0; i < 6; i++) {
      debugPrint('[chips] chips before press ${i + 1}: ${_chipLabels()} focus=${_describeFocus()} '
          'node=${identityHashCode(FocusManager.instance.primaryFocus)}');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      for (var t = 0; t < 10; t++) {
        await tester.pump(const Duration(milliseconds: 50));
        debugPrint('[chips]   +${(t + 1) * 50}ms ${_describeFocus()} '
            'node=${identityHashCode(FocusManager.instance.primaryFocus)}');
      }
      await _settle(tester, const Duration(seconds: 3));
      debugPrint('[chips] chips after press ${i + 1}: ${_chipLabels()}');
      final where =
          _log('favourites press ${i + 1} -> ${container.read(librarySearchProvider(pageKey)).filters.favourites}');
      expect(where, 'chip:${l10n.favorites}', reason: 'the selection left the favourites chip on press ${i + 1}');
    }

    // The type panel: in, and up out of it.
    final typeLabel = l10n.type(container.read(librarySearchProvider(pageKey)).filters.types.length);
    await _selectChip(tester, typeLabel);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(_log('type panel open'), startsWith('option:'));
    expect(_panelSearchBox(), findsNothing, reason: 'the type panel has no search box');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_log('up from the first type'), 'chip:$typeLabel');

    // In again, and right out of it onto the next chip.
    await _press(tester, LogicalKeyboardKey.enter);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _log('down in the type panel');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_log('right out of the type panel'), 'chip:${l10n.watchedState}');
    expect(_panelOpen(), isFalse);

    // Genres, with its search box.
    final genres = container.read(librarySearchProvider(pageKey)).filters.genres;
    if (genres.length > 10) {
      await _selectChip(tester, l10n.genre(genres.length));
      await _press(tester, LogicalKeyboardKey.enter);
      _log('genre panel open');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_log('up from the first genre'), 'search');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_log('down from the search box'), startsWith('option:'));
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_panelOpen(), isFalse, reason: 'left out of an empty search box leaves the panel');
      _log('left out of the search box');
    }

    // Years: a decade by select, and the steppers.
    final yearRange = container.read(librarySearchProvider(pageKey)).yearRange;
    if (container.read(librarySearchProvider(pageKey)).filters.years.isNotEmpty) {
      await _selectChipWhere(tester, (label) => label.startsWith(l10n.year(1)));
      await _press(tester, LogicalKeyboardKey.enter);
      final decade = _log('year panel open');
      await _press(tester, LogicalKeyboardKey.enter, settle: const Duration(seconds: 2));
      final picked = container.read(librarySearchProvider(pageKey)).yearRange;
      debugPrint('[chips] picked $decade: $yearRange -> $picked');
      expect(picked.$1, isNotNull, reason: 'select on a decade set no years');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      _log('up from the decade');
      await _press(tester, LogicalKeyboardKey.enter, settle: const Duration(seconds: 2));
      debugPrint('[chips] after a step: ${container.read(librarySearchProvider(pageKey)).yearRange}');
      await _press(tester, LogicalKeyboardKey.escape);
      _log('escape from the year panel');
      notifier.setYearsRange(null, null);
      await _settle(tester, const Duration(seconds: 2));
    }

    // Group: open, look, close.
    await _selectChipWhere(tester, (label) => label == l10n.group);
    await _press(tester, LogicalKeyboardKey.enter);
    _log('group panel open');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _log('down in the group panel');
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_panelOpen(), isFalse);
    _log('up out of the group panel');
  });
}

List<String> _chipLabels() => find
    .descendant(of: find.byType(LibraryFilterChips), matching: find.byType(ExpressiveButton))
    .evaluate()
    .map((element) => _firstText(element) ?? '?')
    .toList();

Finder _panelSearchBox() => find.descendant(
      of: find.ancestor(of: find.byType(PopoverHeader), matching: find.byType(Column)).first,
      matching: find.byType(TextField),
    );

bool _panelOpen() => find.byType(PopoverOption).evaluate().isNotEmpty;

/// Where the selection is, in a word: which chip, which choice, the search
/// box, a poster.
String _describeFocus() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'nothing';
  if (context.findAncestorStateOfType<EditableTextState>() != null) return 'search';
  final chip = context.findAncestorWidgetOfExactType<ExpressiveButton>();
  if (chip != null) return 'chip:${_firstText(context) ?? '?'}';
  if (context.findAncestorWidgetOfExactType<PopoverOption>() != null) return 'option:${_firstText(context) ?? '?'}';
  if (context.findAncestorWidgetOfExactType<PosterWidget>() != null) return 'poster';
  return '${context.widget.runtimeType} ${FocusManager.instance.primaryFocus?.debugLabel ?? ''}';
}

String _log(String step) {
  final where = _describeFocus();
  debugPrint('[chips] $step: $where (panel ${_panelOpen() ? 'open' : 'shut'})');
  return where;
}

String? _firstText(BuildContext context) {
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

Future<void> _selectChip(WidgetTester tester, String label) => _selectChipWhere(tester, (text) => text == label);

Future<void> _selectChipWhere(WidgetTester tester, bool Function(String label) matches) async {
  final chip = find.descendant(
    of: find.byType(LibraryFilterChips),
    matching: find.byWidgetPredicate((widget) => widget is Text && widget.data != null && matches(widget.data!)),
  );
  expect(chip, findsWidgets);
  Focus.of(tester.element(chip.first)).requestFocus();
  await _settle(tester, const Duration(milliseconds: 500));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key,
    {Duration settle = const Duration(milliseconds: 700)}) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, settle);
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (done()) return;
  }
  fail('timed out waiting');
}

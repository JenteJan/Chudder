// A d-pad sweep over the detail pages, run against the real app on Windows.
//
// Boots the app with whatever account is signed in, opens a film and a show
// straight through the router, then presses each direction one step at a time
// and prints where focus lands: the widgets behind the focused node, its
// rectangle and the page's scroll offset. The traversal policy prints its own
// decision for every press (see debugTraceFocusMoves), so a press that landed
// somewhere odd can be read back to the search that chose it.
//
// Run: flutter test integration_test/dpad_sweep_test.dart -d windows
//
// Deliberately never fails: it is a survey, and the findings are the output.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/main.dart' as app;
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('d-pad sweep over a film and a show', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 2));
    debugTraceFocusMoves = true;

    final context = tester.element(find.byType(NavigationBody).first);
    final container = ProviderScope.containerOf(context, listen: false);
    final api = container.read(jellyApiProvider);

    // Recently added rather than alphabetical: more likely to carry cast and
    // related rows, which is where the lower half of the page gets its stops.
    Future<String?> pick(BaseItemKind kind) async {
      final response = await api.usersUserIdItemsGet(
        includeItemTypes: [kind],
        recursive: true,
        limit: 1,
        sortBy: [ItemSortBy.datecreated],
        sortOrder: [SortOrder.descending],
      );
      return response.body?.items?.firstOrNull?.id;
    }

    final movieId = await pick(BaseItemKind.movie);
    final seriesId = await pick(BaseItemKind.series);
    _out('items movie=$movieId series=$seriesId');

    // First arrow press flips InputDetector to d-pad mode.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester, const Duration(milliseconds: 400));

    for (final (label, id) in [('movie', movieId), ('show', seriesId)]) {
      if (id == null) continue;
      _out('===== $label $id');
      tester.element(find.byType(NavigationBody).first).router.push(DetailsRoute(id: id));
      await _pumpUntil(tester, () => find.byType(MediaPlayButton).evaluate().isNotEmpty, const Duration(seconds: 30));
      // Let the page's own requests land and the transition finish.
      await _settle(tester, const Duration(seconds: 4));

      await _sweep(tester, label);
      await _probeHeaderRow(tester, label);

      // The same header at a wide window, where the row lays out differently.
      final view = tester.view;
      final originalSize = view.physicalSize;
      view.physicalSize = Size(1920 * view.devicePixelRatio, 1080 * view.devicePixelRatio);
      await _settle(tester, const Duration(seconds: 2));
      await _probeHeaderRow(tester, '$label wide');
      view.physicalSize = originalSize;
      await _settle(tester, const Duration(seconds: 1));

      tester.element(find.byType(NavigationBody).first).router.maybePop();
      await _settle(tester, const Duration(seconds: 2));
    }
    _out('done');
    await _settle(tester, const Duration(seconds: 1));
  });
}

Future<void> _sweep(WidgetTester tester, String label) async {
  _out('[$label] start: ${_describe(tester)}');
  var stops = 0;
  var stalls = 0;

  // Down until nothing moves twice in a row, then all the way back up.
  for (final direction in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowUp]) {
    final name = direction == LogicalKeyboardKey.arrowDown ? 'DOWN' : 'UP';
    var unchanged = 0;
    for (var i = 0; i < 60 && unchanged < 2; i++) {
      final before = _describe(tester);
      await tester.sendKeyEvent(direction);
      await _settle(tester, const Duration(milliseconds: 450));
      final after = _describe(tester);
      if (after == before) {
        unchanged++;
        stalls++;
        _out('[$label] $name #$i: NO CHANGE');
        continue;
      }
      unchanged = 0;
      if (name == 'DOWN') stops++;
      _out('[$label] $name #$i: $after');
    }
    for (final side in [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight]) {
      final before = _describe(tester);
      await tester.sendKeyEvent(side);
      await _settle(tester, const Duration(milliseconds: 450));
      final after = _describe(tester);
      final sideName = side == LogicalKeyboardKey.arrowLeft ? 'LEFT' : 'RIGHT';
      _out('[$label] $sideName at $name end: ${after == before ? 'NO CHANGE' : after}');
    }
  }
  _out('[$label] summary: $stops stops going down, $stalls presses that changed nothing');
}

/// Along the header's action row - play, the stream pickers, favourite and the
/// rest - pressing up and then down at every button, to see where each goes
/// and whether down brings it back.
Future<void> _probeHeaderRow(WidgetTester tester, String label) async {
  // The way a user gets there: up to the corner buttons, then down twice -
  // once onto the artwork button, once onto the row.
  for (var i = 0; i < 14; i++) {
    final before = _describe(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester, const Duration(milliseconds: 350));
    if (_describe(tester) == before) break;
  }
  for (var i = 0; i < 2; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester, const Duration(milliseconds: 450));
  }
  _out('[$label row] entered: ${_describe(tester)}');

  final entered = _describe(tester);
  // The i-th button of the row: back to its start, then right i times. Up
  // and down from each, and whether down brings it back.
  for (var i = 0; i < 10; i++) {
    if (i > 0) {
      await _toRowStart(tester, entered);
      var reached = true;
      for (var step = 0; step < i; step++) {
        final before = _describe(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await _settle(tester, const Duration(milliseconds: 350));
        if (_describe(tester) == before) {
          reached = false;
          break;
        }
      }
      if (!reached) {
        _out('[$label row] end of row after ${i - 1}');
        break;
      }
    }
    final here = _describe(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester, const Duration(milliseconds: 450));
    final up = _describe(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester, const Duration(milliseconds: 450));
    final back = _describe(tester);
    _out('[$label row] #$i at ${_short(here)}');
    _out('[$label row]    up -> ${up == here ? 'NO CHANGE' : _short(up)}');
    _out('[$label row]    down -> ${back == here ? 'back' : _short(back)}');
  }
}

/// Back onto the row's first button, from wherever focus is: up to the corner
/// buttons, then down twice.
Future<void> _toRowStart(WidgetTester tester, String entered) async {
  for (var i = 0; i < 14; i++) {
    final before = _describe(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester, const Duration(milliseconds: 300));
    if (_describe(tester) == before) break;
  }
  for (var i = 0; i < 2; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester, const Duration(milliseconds: 400));
  }
  if (_describe(tester) != entered) _out('   (re-entry landed on ${_short(_describe(tester))})');
}

String _short(String description) {
  final at = description.indexOf(' @');
  final head = at == -1 ? description : description.substring(0, at);
  final parts = head.split(' < ').take(3).join(' < ');
  return at == -1 ? parts : '$parts${description.substring(at)}';
}

/// The focused node: the widgets behind it, outermost interesting ones
/// included, its rectangle, and how far the page is scrolled.
String _describe(WidgetTester tester) {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'no focus';
  final ro = node.context?.findRenderObject();
  final rect = ro is RenderBox && ro.hasSize && ro.attached ? ro.localToGlobal(Offset.zero) & ro.size : null;
  final chain = <String>[];
  node.context?.visitAncestorElements((element) {
    final t = element.widget.runtimeType.toString();
    if (_boring.any(t.startsWith)) return true;
    chain.add(t);
    return chain.length < 10;
  });
  final r =
      rect == null ? '' : ' @${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()}';
  // The page's vertical scroll position, if the focused thing is inside one.
  String scroll = '';
  final scrollable = node.context == null ? null : Scrollable.maybeOf(node.context!, axis: Axis.vertical);
  if (scrollable != null) scroll = ' scroll=${scrollable.position.pixels.round()}';
  return '${node.debugLabel ?? ''}${chain.join(' < ')}$r$scroll';
}

const _boring = [
  'Semantics',
  'Listener',
  'RawGestureDetector',
  'GestureDetector',
  'MouseRegion',
  'Focus',
  'Actions',
  'Builder',
  'Padding',
  'Align',
  'Center',
  'Flexible',
  'Expanded',
  'SizedBox',
  'ConstrainedBox',
  'DecoratedBox',
  'ClipPath',
  'ClipRRect',
  'RepaintBoundary',
  'DefaultTextStyle',
  'AnimatedDefaultTextStyle',
  'IconTheme',
  'DefaultSelectionStyle',
  'InheritedCupertinoTheme',
  'CupertinoTheme',
  'NotificationListener',
  'CustomPaint',
  'PhysicalShape',
  'PhysicalModel',
  'KeyedSubtree',
  'TickerMode',
  'Offstage',
  'IgnorePointer',
  'AbsorbPointer',
  'Container',
  'Material',
  'InkWell',
  'InkResponse',
  '_InkResponse',
  'Positioned',
  'Stack',
  'Row',
  'Column',
  'Tooltip',
  'AnimatedContainer',
  'ValueListenableBuilder',
  'AnimatedOpacity',
  'FadeTransition',
  'Opacity',
  'Transform',
  'LayoutBuilder',
  'ExcludeFocus',
  'ExcludeSemantics',
  'MergeSemantics',
  'ScrollNotificationObserver',
  'UnconstrainedBox',
  'FittedBox',
  'AspectRatio',
  'Hero',
  'MediaQuery',
  'Theme',
  'AnimatedTheme',
  'Directionality',
  'InheritedTheme',
  '_Inherited',
  '_Theme',
  '_Effective',
  '_Focus',
  '_Actions',
  '_Listener',
  'FocusTraversal',
  'Shortcuts',
  'ButtonStyleButton',
  '_ButtonStyle',
  'AnimatedPhysicalModel',
  'AnimatedSize',
  'IntrinsicHeight',
  'IntrinsicWidth',
  'SizeTransition',
  'Wrap',
  'Consumer',
  'ProviderScope',
  'Uncontrolled',
  'PositionProvider',
];

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      _out('timeout waiting; continuing anyway');
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// pumpAndSettle never returns on a page with a looping animation, so pump
/// for a fixed time instead.
Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _out(String line) {
  // ignore: avoid_print
  print('[sweep] $line');
}

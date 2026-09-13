// A d-pad walk into and along the side bar, run against the real app on Windows.
//
// From a tab's own page, from a film opened on a tab and from the Search tab:
// left until the selection reaches the bar, then down the whole bar and back
// up, then right onto the page and left again - printing where every press
// lands, and whether that is on the bar.
//
// Run: flutter test integration_test/sidebar_dpad_test.dart -d windows
//
// Deliberately never fails: it is a survey, and the findings are the output.

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/main.dart' as app;
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/shared/media/components/media_play_button.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_button.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_bar.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('d-pad into and along the side bar', (tester) async {
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 40));
    await _settle(tester, const Duration(seconds: 3));
    debugTraceFocusMoves = true;

    // The first arrow press only flips InputDetector to d-pad mode.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _out('after first press: ${_describe()}');
    await _press(tester, LogicalKeyboardKey.arrowDown);
    _out('after second press: ${_describe()}');

    await _walk(tester, 'dashboard');

    // The way a remote is actually used: down a few rows, then left until
    // the bar has it.
    for (var i = 0; i < 3; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      _out('[dashboard rows] DOWN #$i: ${_describe()}');
    }
    for (var i = 0; i < 8 && !_inBar(); i++) {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      _out('[dashboard rows] LEFT #$i: ${_describe()}');
    }
    _out('[dashboard rows] ${_inBar() ? 'reached the bar' : 'NEVER REACHED THE BAR'}');
    await _press(tester, LogicalKeyboardKey.arrowRight);
    _out('[dashboard rows] RIGHT: ${_describe()}');

    final context = tester.element(find.byType(NavigationBody).first);
    final api = ProviderScope.containerOf(context, listen: false).read(jellyApiProvider);
    final response = await api.usersUserIdItemsGet(
      includeItemTypes: [BaseItemKind.movie],
      recursive: true,
      limit: 1,
      sortBy: [ItemSortBy.datecreated],
      sortOrder: [SortOrder.descending],
    );
    final movieId = response.body?.items?.firstOrNull?.id;
    if (movieId != null) {
      // Onto the active tab's own stack, the way a poster opens it.
      context.router.push(DetailsRoute(id: movieId));
      await _pumpUntil(tester, () => find.byType(MediaPlayButton).evaluate().isNotEmpty, const Duration(seconds: 30));
      await _settle(tester, const Duration(seconds: 4));
      await _walk(tester, 'film');
    }

    showHomeTab(context.router.root, HomeTabs.search);
    await _settle(tester, const Duration(seconds: 3));
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _walk(tester, 'search');

    _out('done');
    await _settle(tester, const Duration(seconds: 1));
  });
}

Future<void> _walk(WidgetTester tester, String label) async {
  _out('[$label] start: ${_describe()}');
  _dumpInactive(label);

  // Left until the bar has the selection, or nothing moves twice in a row.
  var unchanged = 0;
  for (var i = 0; i < 15 && !_inBar() && unchanged < 2; i++) {
    final before = _describe();
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    final after = _describe();
    unchanged = after == before ? unchanged + 1 : 0;
    _out('[$label] LEFT #$i: ${after == before ? 'NO CHANGE' : after}');
    if (after == before) _dumpInactive('$label LEFT #$i');
  }
  if (!_inBar()) {
    _out('[$label] NEVER REACHED THE BAR');
    return;
  }

  // The whole bar, down and back up.
  for (final (key, name) in [(LogicalKeyboardKey.arrowDown, 'DOWN'), (LogicalKeyboardKey.arrowUp, 'UP')]) {
    unchanged = 0;
    for (var i = 0; i < 25 && unchanged < 2; i++) {
      final before = _describe();
      await _press(tester, key);
      final after = _describe();
      unchanged = after == before ? unchanged + 1 : 0;
      _out('[$label] $name #$i: ${after == before ? 'NO CHANGE' : after}');
    }
  }

  // Back onto the page, and straight back to the bar.
  await _press(tester, LogicalKeyboardKey.arrowRight);
  _out('[$label] RIGHT: ${_describe()}');
  await _press(tester, LogicalKeyboardKey.arrowLeft);
  _out('[$label] LEFT again: ${_describe()}');
  await _press(tester, LogicalKeyboardKey.arrowRight);
  _out('[$label] RIGHT again: ${_describe()}');
}

/// Every focus node still in the tree whose widget is no longer: a traversal
/// that meets one throws in a debug build and reads a stale position in a
/// release one.
void _dumpInactive(String label) {
  final all = FocusManager.instance.rootScope.descendants.toList();
  var count = 0;
  // Grouped by the widgets above them, so a leak shows as one line with a count.
  final chains = <String, int>{};
  for (final node in all) {
    final context = node.context;
    if (context is! Element) continue;
    var active = true;
    var defunct = false;
    var chain = '';
    assert(() {
      active = context.debugIsActive;
      defunct = context.debugIsDefunct;
      if (!active) chain = context.debugGetCreatorChain(60);
      return true;
    }());
    if (active) continue;
    count++;
    final key = '${defunct ? 'DEFUNCT' : 'inactive'} canFocus=${node.canRequestFocus} :: $chain';
    chains[key] = (chains[key] ?? 0) + 1;
  }
  final sorted = chains.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted.take(12)) {
    _out('[$label] ${entry.value}x ${entry.key}');
  }
  _out('[$label] inactive focus nodes: $count of ${all.length}');
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await _settle(tester, const Duration(milliseconds: 450));
}

bool _inBar() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context != null && context.findAncestorWidgetOfExactType<SideNavigationRailOverlay>() != null;
}

/// The focused node: on the bar, the entry's label; on a page, the widgets
/// behind it and its rectangle.
String _describe() {
  final node = FocusManager.instance.primaryFocus;
  if (node == null) return 'no focus';
  final context = node.context;
  if (context == null) return 'node without context ${node.debugLabel ?? ''}';
  final ro = context.findRenderObject();
  final rect = ro is RenderBox && ro.hasSize && ro.attached ? ro.localToGlobal(Offset.zero) & ro.size : null;
  final r =
      rect == null ? '' : ' @${rect.left.round()},${rect.top.round()} ${rect.width.round()}x${rect.height.round()}';
  if (_inBar()) {
    final entry = context.findAncestorWidgetOfExactType<NavigationButton>();
    return 'BAR ${entry?.label ?? node.debugLabel ?? context.widget.runtimeType}$r';
  }
  final chain = <String>[];
  context.visitAncestorElements((element) {
    final type = element.widget.runtimeType.toString();
    if (type.startsWith('_') || _boring.contains(type)) return true;
    chain.add(type);
    return chain.length < 6;
  });
  final scope = node is FocusScopeNode ? ' (SCOPE)' : '';
  return 'PAGE ${node.debugLabel ?? ''}$scope ${chain.join(' < ')}$r';
}

const _boring = {
  'Semantics', 'Listener', 'RawGestureDetector', 'GestureDetector', 'MouseRegion', 'Focus', 'Actions',
  'Builder', 'Padding', 'Align', 'Center', 'Flexible', 'Expanded', 'SizedBox', 'ConstrainedBox',
  'DecoratedBox', 'ClipPath', 'ClipRRect', 'RepaintBoundary', 'DefaultTextStyle', 'IconTheme',
  'NotificationListener', 'CustomPaint', 'KeyedSubtree', 'TickerMode', 'Offstage', 'IgnorePointer',
  'Container', 'Material', 'InkWell', 'InkResponse', 'Positioned', 'Stack', 'Row', 'Column', 'Tooltip',
  'AnimatedContainer', 'AnimatedOpacity', 'FadeTransition', 'Opacity', 'Transform', 'LayoutBuilder',
  'ExcludeFocus', 'ExcludeSemantics', 'MediaQuery', 'Theme', 'Directionality', 'FocusTraversalGroup',
  'Shortcuts', 'AnimatedSize', 'Consumer', 'MergeSemantics', 'AnimatedDefaultTextStyle',
};

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
  print('[bar] $line');
}

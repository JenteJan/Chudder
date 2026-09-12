import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Lands in the diagnostics file like the SyncPlay and websocket traces, so
/// a forward button that misbehaves on a release build leaves a record.
final _log = Logger('Navigation');

/// Routes that must never be re-entered by going forward.
///
/// The lock screen is a guard rather than a place, and login/splash are states
/// the app moves through, not pages someone chose to visit. Sending a mouse
/// click back into any of them would be worse than doing nothing.
const _excludedFromHistory = {
  'LockRoute',
  'LoginRoute',
  'SplashRoute',
  'HomeRoute',
};

/// The forward half of browser-style navigation.
///
/// A router only ever pops: a page that has been left is gone, and there is
/// nothing to ask it to redo. So the routes we pop are remembered here, and a
/// forward press pushes the most recent one again.
///
/// Deliberately narrow. Tabs are not part of it - switching tabs is not a push
/// under [AutoTabsRouter], so "forward across a tab switch" has no meaning -
/// and neither are dialogs or the player, which are not root pages.
final navigationHistoryProvider = Provider<NavigationHistory>((ref) => NavigationHistory());

class NavigationHistory {
  final List<PageRouteInfo> _forward = [];

  /// Whether there is anywhere to go forward to.
  bool get canGoForward => _forward.isNotEmpty;

  /// Remember a route that was just left, so forward can return to it.
  ///
  /// Called with the route being popped, before it goes.
  void recordPop(RouteMatch? match) {
    if (match == null) return;
    if (_excludedFromHistory.contains(match.name)) return;
    // No de-duplication by name: every show is a DetailsRoute, so comparing
    // names dropped the second of two shows and forward only ever went one
    // page deep. The observer is the single source of pops, so there is
    // nothing to de-duplicate against anyway.
    _forward.add(match.toPageRouteInfo());
    _log.info('popped ${match.name} -> forward depth ${_forward.length}');
  }

  /// Forget the forward history.
  ///
  /// Browser semantics: navigating somewhere new makes the pages that were
  /// ahead unreachable, because the branch they belonged to no longer exists.
  void clear() => _forward.clear();

  /// Go forward, if there is anywhere to go. Returns whether it moved.
  Future<bool> goForward(StackRouter router) async {
    if (_forward.isEmpty) return false;
    final route = _forward.removeLast();
    _log.info('forward to ${route.routeName}; ${_forward.length} left');
    // Counted, not timed. The navigator notifies its observers on a later
    // frame, so a flag cleared after this method returned was already false
    // by the time didPush arrived - which then wiped the rest of the history
    // and made forward one page deep no matter how far back you had come.
    _pendingRestores++;
    // Not awaited either: push() completes when the page is POPPED, not when
    // it opens.
    unawaited(router.push(route));
    return true;
  }

  /// Pushes made by [goForward] that their didPush has not yet accounted for.
  int _pendingRestores = 0;

  /// Called when a route is pushed. Anything the user opens themselves makes
  /// the pages that were ahead unreachable - they belonged to a branch that
  /// no longer exists - which is what a browser does too.
  void recordPush() {
    if (_pendingRestores > 0) {
      _pendingRestores--;
      _log.info('push was our own restore; forward depth ${_forward.length}');
      return;
    }
    if (_forward.isNotEmpty) {
      _log.info('new navigation; dropping ${_forward.length} forward entries');
    }
    clear();
  }
}

/// Watches the root navigator so the forward history follows what actually
/// happened, rather than only what the mouse asked for.
class NavigationHistoryObserver extends NavigatorObserver {
  NavigationHistoryObserver(this.history);

  final NavigationHistory history;

  /// What had the selection when each page was opened from it.
  ///
  /// Coming back from a page lands the selection on the card *before* the one
  /// that was opened, and no amount of care in the rows could fix it, because
  /// nothing in the app moves it. Every poster sits in a [Hero], and opening a
  /// details page takes the flying card's subtree out of the tree for the
  /// flight. A [FocusScopeNode] holds its focused children as a
  /// most-recently-used stack, and a node leaving the tree is *popped off* it -
  /// so the scope quietly falls back to whatever was selected before. When the
  /// transition finishes, [ModalRoute] asks its scope to take focus, the scope
  /// descends into that stale entry, and the selection lands one card back.
  ///
  /// The rows do restore the right card as the page comes back; the route
  /// overrules them a frame or two later. So the card is put back after the
  /// transition has finished having its say - keyed by route, so a page opened
  /// from a page remembers its own.
  final Map<Route<dynamic>, _Selection> _selectionBeforePush = {};

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Only real pages. A dialog or a bottom sheet is not somewhere the user
    // navigated to, and closing one should not cost them their forward
    // history.
    if (_routeMatch(route) == null) return;
    // Still on the card that was pressed: didPush runs as the push is made,
    // before the page it opens has built anything.
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null) {
      _selectionBeforePush[route] = _Selection(
        node: focused,
        // The card itself, not only the node that drew it. The page rebuilds
        // its rows as it comes back, so the button the selection was on is a
        // new one by the time the route settles - same card, different node.
        posterId: focused.context?.findAncestorWidgetOfExactType<PosterWidget>()?.poster.id,
      );
    }
    history.recordPush();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Recorded here rather than in the back handler, so it covers every way
    // of going back - the on-screen arrow, backspace, the system gesture -
    // not only the mouse button that happens to have a forward twin.
    history.recordPop(_routeMatch(route));

    final remembered = _selectionBeforePush.remove(route);
    if (remembered == null) return;

    // The last of these is after the transition has finished: as a route
    // settles, [ModalRoute] asks its own scope to take focus, and that is the
    // press being answered. Timed off the route's transition rather than its
    // animation object, which the navigator disposes on the way to dismissed -
    // a status listener on it never hears the end of the flight.
    //
    // The scope is put right more than once, because it goes wrong more than
    // once: the rows restore the correct card as the page comes back, the
    // route's own scope overrules them a frame later, and the page settling
    // can rebuild the row again under both. Each attempt does nothing when the
    // selection is already where it belongs, so this is one correction made to
    // stick rather than a selection being dragged about.
    // Tried often rather than late: the card is drawn by a new button once the
    // page has rebuilt its rows, and there is nothing to put the selection on
    // before that. Asking every frame or so means it is put right on the first
    // frame it can be, instead of the selection sitting visibly on the wrong
    // card until the page has finished settling.
    final settle = route is ModalRoute ? route.transitionDuration : Duration.zero;
    final until = settle.inMilliseconds + 200;
    for (var delay = 32; delay <= until; delay += 32) {
      Timer(Duration(milliseconds: delay), () => _restore(remembered));
    }
  }

  /// Put the selection back on the card the popped page was opened from.
  void _restore(_Selection remembered) {
    final selection = remembered.liveNode();
    if (selection == null) return;
    if (FocusManager.instance.primaryFocus == selection) return;
    final context = selection.context!;
    // Only a pad's selection is put back. A ring appearing under a mouse that
    // never asked for one is the bug this would otherwise trade for. Read
    // without subscribing - this is a timer, not a build - and read leniently:
    // a node whose context cannot answer still gets its selection back, which
    // is the behaviour being fixed.
    final layout = context.getInheritedWidgetOfExactType<AdaptiveLayout>();
    if (layout != null && layout.data.inputDevice != InputDevice.dPad) return;
    // The page it belongs to is the one on top again.
    if (ModalRoute.of(context)?.isCurrent != true) return;
    selection.requestFocus();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _selectionBeforePush.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _selectionBeforePush.remove(oldRoute);
  }

  /// The auto_route match behind a navigator route, or null if this is not one
  /// of its pages (a dialog, a sheet, anything pushed by hand).
  RouteMatch? _routeMatch(Route<dynamic> route) {
    final settings = route.settings;
    return settings is AutoRoutePage ? settings.routeData.route : null;
  }
}

/// The selection a page was left on, as both the button and the card it was
/// drawn for.
class _Selection {
  _Selection({required this.node, required this.posterId});

  final FocusNode node;
  final String? posterId;

  static bool _usable(FocusNode node) {
    final context = node.context;
    return context != null && context.mounted && node.canRequestFocus && !node.skipTraversal;
  }

  /// The button that now stands for this selection, or null if it has gone.
  ///
  /// The node that was remembered first, while it is still a real button. It
  /// usually is not: a page rebuilds its rows as it comes back, and the card is
  /// drawn by a new button by then - so the card is looked up by id instead.
  FocusNode? liveNode() {
    if (_usable(node)) return node;
    final id = posterId;
    if (id == null) return null;
    for (final candidate in FocusManager.instance.rootScope.traversalDescendants) {
      if (!_usable(candidate)) continue;
      if (candidate.context!.findAncestorWidgetOfExactType<PosterWidget>()?.poster.id == id) {
        return candidate;
      }
    }
    return null;
  }
}

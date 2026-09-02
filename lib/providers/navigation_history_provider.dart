import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

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

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Only real pages. A dialog or a bottom sheet is not somewhere the user
    // navigated to, and closing one should not cost them their forward
    // history.
    if (_routeMatch(route) == null) return;
    history.recordPush();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Recorded here rather than in the back handler, so it covers every way
    // of going back - the on-screen arrow, backspace, the system gesture -
    // not only the mouse button that happens to have a forward twin.
    history.recordPop(_routeMatch(route));
  }

  /// The auto_route match behind a navigator route, or null if this is not one
  /// of its pages (a dialog, a sheet, anything pushed by hand).
  RouteMatch? _routeMatch(Route<dynamic> route) {
    final settings = route.settings;
    return settings is AutoRoutePage ? settings.routeData.route : null;
  }
}

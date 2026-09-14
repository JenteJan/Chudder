import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/routes/tab_stack.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/login/lock_screen.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

const settingsPageRoute = "settings";
const controlPanelPageRoute = "control-panel";

const fullScreenRoutes = {
  PhotoViewerRoute.name,
};

const topBarNoBlurRoutes = {
  SettingsRoute.name,
  ControlPanelRoute.name,
  DetailsRoute.name,
};

@AutoRouterConfig(replaceInRouteName: 'Screen|Page,Route')
class AutoRouter extends RootStackRouter {
  AutoRouter({
    required this.ref,
  });

  final WidgetRef ref;

  @override
  List<AutoRouteGuard> get guards => [...super.guards, AuthGuard(ref: ref)];

  @override
  RouteType get defaultRouteType => RouteType.custom(
        transitionsBuilder: _adaptiveTransition,
        // Material's own page duration, so the desktop transition is the one it
        // always was rather than the same animation at a different speed.
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 300),
      );

  @override
  List<AutoRoute> get routes => [
        ..._defaultRoutes,
        ...otherRoutes,
      ];

  /// Home owns the tabs, and each tab the pages opened from it (see
  /// [homeRoutes]) - settings and the control panel included, on a tab of
  /// their own.
  ///
  /// The tabs used to be entries on the same stack as details, settings and
  /// the control panel, so "which tab am I on" had to be inferred from the
  /// route name - and a route that was not a tab read as no tab at all, which
  /// is what kept taking the navigation bar and the drawer away. The active
  /// tab stays a fact the tabs router can be asked for.
  ///
  /// The browsing pages are here as well as on the tabs for what is not
  /// opened from a tab: a link straight to a film, a page opened from
  /// settings. Those still cover Home the way every page once did.
  final List<AutoRoute> otherRoutes = [
    _homeRoute.copyWith(children: [...homeRoutes]),
    ...detailsRoutes,
    AutoRoute(page: LockRoute.page, path: '/locked'),
  ];
}

/// A wipe in from the right on a small screen, and the platform's own
/// transition on anything larger.
///
/// A page sliding in reads well where a page fills the window and there is a
/// clear back; on a desktop window, where the page is one panel among several,
/// it looked like the whole app had been shoved sideways.
Widget _adaptiveTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // Asked of the layout when it is there, and measured directly when it is not
  // - a route can be built before anything has told it how big the window is,
  // and 600 is where [AdaptiveLayout] draws the same line.
  final viewSize = AdaptiveLayout.maybeOf(context)?.data.viewSize;
  final isCompact = viewSize == ViewSize.phone || (viewSize == null && MediaQuery.sizeOf(context).width < 600);

  if (!isCompact) {
    final route = ModalRoute.of(context);
    // Always a page route in practice; without one there is no transition to
    // hand back to the platform, so the page simply arrives.
    if (route is! PageRoute<dynamic>) return child;
    final platform = Theme.of(context).platform;
    if (!kIsWeb && (platform == TargetPlatform.windows || platform == TargetPlatform.linux)) {
      // The platform's zoom, but with a page being opened drawn live. By
      // default the zoom paints the page coming in from a picture taken on its
      // first frame and keeps showing that picture for the whole 300 ms, so
      // the backdrop, the rows and anything that arrives in the meantime all
      // appear at once when it ends.
      //
      // Only the opening is live. The zoom is two in one: this route's own
      // animation (opening, and closing when it is popped) and the one it
      // plays underneath the routes above it. The second stays on pictures:
      // a page you come back to is already loaded, and drawing a whole
      // dashboard live for every frame of the way back cost the frame rate.
      return _desktopOpening.buildTransitions<dynamic>(
        route,
        context,
        animation,
        kAlwaysDismissedAnimation,
        _desktopUnderneath.buildTransitions<dynamic>(
          route,
          context,
          kAlwaysCompleteAnimation,
          secondaryAnimation,
          child,
        ),
      );
    }
    return Theme.of(context).pageTransitionsTheme.buildTransitions<dynamic>(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
  }

  return SlideTransition(
    position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
    ),
    child: child,
  );
}

/// The zoom as this route opens and closes, with the opening drawn live.
const _desktopOpening = ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false);

/// The zoom this route plays while others open over it and close again.
const _desktopUnderneath = ZoomPageTransitionsBuilder();

final AutoRoute _homeRoute = AutoRoute(page: HomeRoute.page, path: '/');

/// Home's tabs, each a stack of its own: the tab's own page first, and above
/// it whatever is opened from there. See [TabStack].
final List<AutoRoute> homeRoutes = [
  _tab(HomeTabs.dashboard, 'dashboard', DashboardRoute.page, initial: true),
  _tab(HomeTabs.library, 'libraries', LibraryRoute.page),
  _tab(HomeTabs.favorites, 'favourites', FavouritesRoute.page),
  _tab(HomeTabs.seerr, 'seerr', SeerrRoute.page),
  _tab(HomeTabs.sync, 'synced', SyncedRoute.page),
  _tab(HomeTabs.search, 'search', LibrarySearchRoute.page),
  _tab(
    HomeTabs.settings,
    settingsPageRoute,
    SettingsRoute.page,
    firstPageChildren: _settingsChildren,
    extraRoutes: [
      AutoRoute(page: ControlPanelRoute.page, path: controlPanelPageRoute, children: _controlPanelRoutes),
    ],
  ),
];

AutoRoute _tab(
  HomeTabs tab,
  String path,
  PageInfo firstPage, {
  bool initial = false,
  List<AutoRoute>? firstPageChildren,
  List<AutoRoute> extraRoutes = const [],
}) =>
    AutoRoute(
      page: PageInfo(tab.stackName, builder: buildTabStack),
      path: path,
      initial: initial,
      children: [
        AutoRoute(page: firstPage, path: '', initial: true, children: firstPageChildren),
        ...extraRoutes,
        // Search's own page is already the first one on its stack, and a
        // stack can hold a page again without being told about it twice.
        for (final route in _browseRoutes())
          if (route.name != firstPage.name) route,
      ],
    );

/// The pages you browse to, for every tab to keep a stack of. Pushes find the
/// innermost stack that knows a page, so anything opened from a tab lands on
/// that tab without the pushing code having to say which one it is on.
List<AutoRoute> _browseRoutes() => [
      AutoRoute(page: DetailsRoute.page, path: 'details'),
      AutoRoute(page: LibrarySearchRoute.page, path: 'library'),
      AutoRoute(page: LiveTvRoute.page, path: 'live-tv'),
      AutoRoute(page: SeerrSearchRoute.page, path: 'seerr-search'),
      AutoRoute(page: SeerrDetailsRoute.page, path: 'seerr/:mediaType/:tmdbId'),
    ];

final List<AutoRoute> detailsRoutes = [
  AutoRoute(page: DetailsRoute.page, path: '/details'),
  AutoRoute(page: PhotoViewerRoute.page, path: "/album"),
  AutoRoute(
    page: LibrarySearchRoute.page,
    path: '/library',
    usesPathAsKey: true,
  ),
  AutoRoute(page: LiveTvRoute.page, path: '/live-tv'),
  AutoRoute(page: SeerrSearchRoute.page, path: '/seerr-search'),
  AutoRoute(page: SeerrDetailsRoute.page, path: '/seerr/:mediaType/:tmdbId'),
];

final List<AutoRoute> _defaultRoutes = [
  AutoRoute(page: SplashRoute.page, path: '/splash'),
  AutoRoute(page: LoginRoute.page, path: '/login', maintainState: false),
];

final List<AutoRoute> _settingsChildren = [
  AutoRoute(page: SettingsSelectionRoute.page, path: 'list'),
  AutoRoute(page: ClientSettingsRoute.page, path: 'client', maintainState: false),
  AutoRoute(page: ProfileSettingsRoute.page, path: 'security', maintainState: false),
  AutoRoute(page: PlayerSettingsRoute.page, path: 'player', maintainState: false),
  AutoRoute(page: AboutSettingsRoute.page, path: 'about'),
];

final List<AutoRoute> _controlPanelRoutes = [
  AutoRoute(page: ControlPanelSelectionRoute.page, path: 'list'),
  AutoRoute(page: ControlDashboardRoute.page, path: 'dashboard', maintainState: false),
  AutoRoute(page: ControlActiveTasksRoute.page, path: 'active-tasks', maintainState: false),
  AutoRoute(page: ControlServerRoute.page, path: 'server-settings', maintainState: false),
  AutoRoute(page: ControlUsersRoute.page, path: 'user-management', maintainState: false),
  AutoRoute(page: ControlUserEditRoute.page, path: 'edit-user', maintainState: false),
  AutoRoute(page: ControlLibrariesRoute.page, path: 'library-management', maintainState: false),
  AutoRoute(page: ControlLiveTvRoute.page, path: 'live-tv', maintainState: false),
];

class LockScreenGuard extends AutoRouteGuard {
  final WidgetRef ref;

  const LockScreenGuard({required this.ref});

  @override
  Future<void> onNavigation(NavigationResolver resolver, StackRouter router) async {
    if (ref.read(lockScreenActiveProvider) && resolver.routeName != const LockRoute().routeName) {
      router.replace(const LockRoute());
      return;
    } else {
      return resolver.next(true);
    }
  }
}

class AuthGuard extends AutoRouteGuard {
  final WidgetRef ref;

  const AuthGuard({required this.ref});

  @override
  Future<void> onNavigation(NavigationResolver resolver, StackRouter router) async {
    if (resolver.route == router.current.route) {
      return;
    }

    if (ref.read(userProvider) != null ||
        resolver.routeName == LoginRoute().routeName ||
        resolver.routeName == SplashRoute().routeName) {
      // We assume the last main focus is no longer active after navigating
      lastMainFocus = null;
      return resolver.next(true);
    }

    resolver.redirectUntil<bool>(SplashRoute(loggedIn: (value) {
      if (value) {
        resolver.next(true);
      } else {
        router.replace(LoginRoute());
      }
    }));

    // We assume the last main focus is no longer active after navigating
    lastMainFocus = null;
    return;
  }
}

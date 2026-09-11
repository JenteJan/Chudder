import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart' hide AutoRouter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_drawer.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:fladder/widgets/navigation_scaffold/home_destinations.dart';

/// The pages that get the navigation bar beside them: everything you browse,
/// as opposed to what you configure.
const _routesWithChrome = {
  HomeRoute.name,
  DetailsRoute.name,
  LibrarySearchRoute.name,
  LiveTvRoute.name,
  SeerrSearchRoute.name,
  SeerrDetailsRoute.name,
};

/// Whether the bar belongs over what the root router is showing right now.
bool _wantsBar(AutoRouter router, AdaptiveLayoutModel layout, {required bool playerOpen, required bool tvLayout}) =>
    _routesWithChrome.contains(router.current.name) && layout.viewSize != ViewSize.phone && !playerOpen && !tvLayout;

/// The one side bar, over Home and over every page you browse to from it.
///
/// Home used to draw a bar of its own inside its scaffold, and a details page
/// - a sibling of Home on the root stack - had none; then it had one of its
/// own, and the two swapped places on every push and pop, which read as a bar
/// that jumped. There is one now, drawn once, that pages slide under the way
/// they slide under SyncPlay and Cast in the corner, and every page is told
/// how wide it is.
///
/// Two halves. This widget sits above the router and only wraps the pages in
/// the width they need to keep clear of - never anything that comes and goes,
/// because swapping the navigator's ancestors builds a fresh navigator and
/// loses the stack. The bar itself is an entry in the root navigator's own
/// overlay: the buttons in it show tooltips, open menus and sheets, and ask the
/// context for a router, all of which need a navigator above them - and the
/// navigator re-lists its own routes on every push, so an entry that is not a
/// route always ends up back on top.
class PersistentNavigationChrome extends ConsumerStatefulWidget {
  final AutoRouter router;
  final Widget child;

  const PersistentNavigationChrome({required this.router, required this.child, super.key});

  @override
  ConsumerState<PersistentNavigationChrome> createState() => _PersistentNavigationChromeState();
}

class _PersistentNavigationChromeState extends ConsumerState<PersistentNavigationChrome> {
  late final OverlayEntry _entry = OverlayEntry(builder: (context) => _ChromeBar(router: widget.router));
  bool _inserted = false;

  @override
  void initState() {
    super.initState();
    widget.router.addListener(_onRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _insert());
  }

  /// Into the navigator's overlay, once there is one. The navigator is built
  /// by the router a frame or two after this widget is.
  void _insert() {
    if (_inserted || !mounted) return;
    final overlay = widget.router.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _insert());
      return;
    }
    overlay.insert(_entry);
    _inserted = true;
  }

  @override
  void dispose() {
    widget.router.removeListener(_onRouteChanged);
    if (_inserted) _entry.remove();
    _entry.dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    setState(() {});
    if (_inserted) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    final layout = AdaptiveLayout.of(context);
    final playerOpen = ref.watch(isVideoPlayerRouteOpenProvider);
    final tvLayout = layout.viewSize >= ViewSize.television &&
        ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final showBar = _wantsBar(widget.router, layout, playerOpen: playerOpen, tvLayout: tvLayout);
    final expanded = ref.watch(clientSettingsProvider.select((value) => value.expandSideBar));

    // The pages keep clear of the bar the way Home's do. Always the same
    // wrapper whether or not the bar is up, so the navigator inside is never
    // rebuilt.
    return AdaptiveLayout(
      key: sideNavigationPageLayerKey,
      data: showBar ? layout.copyWith(sideBarWidth: SideNavigationRail.widthFor(context, expanded: expanded)) : layout,
      child: widget.child,
    );
  }
}

/// The bar, built inside the navigator's overlay.
class _ChromeBar extends ConsumerStatefulWidget {
  final AutoRouter router;
  const _ChromeBar({required this.router});

  @override
  ConsumerState<_ChromeBar> createState() => _ChromeBarState();
}

class _ChromeBarState extends ConsumerState<_ChromeBar> {
  /// The first entry of this bar, for a page to hand the selection to.
  final FocusNode _navNode = FocusNode(debugLabel: 'chromeNavBar');

  @override
  void dispose() {
    if (identical(chromeNavBarNode, _navNode)) chromeNavBarNode = null;
    _navNode.dispose();
    super.dispose();
  }

  void _navigateTab(HomeTabs tab) => showHomeTab(widget.router, tab);

  @override
  Widget build(BuildContext context) {
    final layout = AdaptiveLayout.of(context);
    final playerOpen = ref.watch(isVideoPlayerRouteOpenProvider);
    final tvLayout = layout.viewSize >= ViewSize.television &&
        ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final showBar = _wantsBar(widget.router, layout, playerOpen: playerOpen, tvLayout: tvLayout);

    // While this bar is up it is the one a press off a page's edge should
    // land on, not Home's underneath.
    chromeNavBarNode = showBar ? _navNode : null;
    if (!showBar) return const SizedBox.shrink();

    // A dialog or a sheet over the page covers the page, and should cover
    // the bar with it - an overlay entry would otherwise sit on top of the
    // barrier.
    final covered = widget.router.hasPagelessTopRoute;

    final routeName = widget.router.current.name;
    final destinations = buildHomeDestinations(
      context,
      ref,
      navigateTab: _navigateTab,
      // Onto the tab on screen, like everything else opened from it.
      navigateRoute: (route) => widget.router.push(route),
    );
    // On Home the lit entry is the active tab, asked of the tabs router; on
    // any other page it is whichever entry claims that page, if one does.
    final activeTab = widget.router.innerRouterOf<TabsRouter>(HomeRoute.name)?.activeIndex;
    final currentIndex = routeName == HomeRoute.name && activeTab != null
        ? destinations.indexWhere((destination) => destination.tab.index == activeTab)
        : destinations.indexWhere((destination) => destination.activeRouteName == routeName);

    return IgnorePointer(
      ignoring: covered,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: covered ? 0 : 1,
        child: StackRouterScope(
          controller: widget.router,
          stateHash: widget.router.stateHash,
          child: FocusTraversalGroup(
            policy: GlobalFallbackTraversalPolicy(fallbackNode: _navNode),
            child: SideNavigationRailOverlay(
              currentIndex: currentIndex,
              destinations: destinations,
              currentLocation: routeName,
              onOpenDrawer: () => _showDrawer(context, destinations, currentIndex, routeName),
              // Home's own bar - alive under this page - holds the shared
              // node; this one has a node of its own.
              useNavFocusNode: false,
              firstEntryFocusNode: _navNode,
            ),
          ),
        ),
      ),
    );
  }

  /// The narrow layout's drawer, slid in from the edge as a route of its own:
  /// there is no scaffold up here to hang one on.
  Future<void> _showDrawer(
      BuildContext context, List<DestinationModel> destinations, int currentIndex, String routeName) {
    final views = ref.read(viewsProvider).views;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'navigation',
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.4),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondary, child) => SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      ),
      pageBuilder: (context, animation, secondary) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: StackRouterScope(
          controller: widget.router,
          stateHash: widget.router.stateHash,
          child: NestedNavigationDrawer(
            toggleExpanded: (value) => Navigator.of(context).pop(),
            views: views,
            destinations: destinations,
            currentLocation: routeName,
            currentIndex: currentIndex,
          ),
        ),
      ),
    );
  }
}

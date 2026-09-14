import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart' hide AutoRouter;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/routes/auto_router.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:chudder/widgets/navigation_scaffold/home_destinations.dart';

/// The pages that get the navigation bar beside them: Home - its tabs,
/// Settings among them, and what they open - and the pages you browse to over
/// it.
const _routesWithChrome = {
  HomeRoute.name,
  DetailsRoute.name,
  LibrarySearchRoute.name,
  LiveTvRoute.name,
  SeerrSearchRoute.name,
  SeerrDetailsRoute.name,
};

/// Whether the bar belongs over what the root router is showing right now.
///
/// The player is not in this: it is pushed straight onto the navigator, so the
/// router still names the page underneath it. The bar fades out for it
/// instead (see [_ChromeBar]), and the pages underneath keep the width they
/// have - a page that re-laid itself the frame the player opened jumped
/// sideways under the picture growing over it.
bool _wantsBar(AutoRouter router, AdaptiveLayoutModel layout, {required bool tvLayout}) =>
    _routesWithChrome.contains(router.current.name) && layout.viewSize != ViewSize.phone && !tvLayout;

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
    final tvLayout = layout.viewSize >= ViewSize.television &&
        ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final showBar = _wantsBar(widget.router, layout, tvLayout: tvLayout);
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
  /// A node per entry for the life of the bar, so a page can hand the
  /// selection to whichever entry is lit - see [navBarNode]. Kept by tab
  /// rather than by position: an entry appearing higher up the bar never
  /// takes over another's node.
  final Map<HomeTabs, FocusNode> _entryNodes = {};

  FocusNode _tabNode(HomeTabs tab) => _entryNodes.putIfAbsent(
        tab,
        () => FocusNode(debugLabel: 'chromeNavBar ${tab.name}'),
      );

  FocusNode _entryNode(DestinationModel destination) => _tabNode(destination.tab);

  @override
  void dispose() {
    if (_entryNodes.values.contains(chromeNavBarNode)) chromeNavBarNode = null;
    for (final node in _entryNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _navigateTab(HomeTabs tab) => showHomeTab(widget.router, tab);

  @override
  Widget build(BuildContext context) {
    final layout = AdaptiveLayout.of(context);
    final tvLayout = layout.viewSize >= ViewSize.television &&
        ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    final showBar = _wantsBar(widget.router, layout, tvLayout: tvLayout);

    if (!showBar) {
      chromeNavBarNode = null;
      return const SizedBox.shrink();
    }

    // A dialog or a sheet over the page covers the page, and should cover
    // the bar with it - an overlay entry would otherwise sit on top of the
    // barrier. The player covers it too, being above the pages - and takes
    // it out with a fade rather than a cut, since it opens by growing its
    // picture over the page while the black comes up behind: a bar gone in
    // the first frame was the one thing in that picture that jumped.
    final playerOpen = ref.watch(isVideoPlayerRouteOpenProvider);
    final covered = widget.router.hasPagelessTopRoute || playerOpen;

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

    // Settings has no entry among the others: the profile picture is its.
    final settingsSelected = settingsTabShown(widget.router);

    // While this bar is up it is the one a press off a page's edge lands on:
    // on the entry that is lit, or the first on a page none claims.
    chromeNavBarNode = playerOpen
        ? null
        : settingsSelected
            ? _tabNode(HomeTabs.settings)
            : destinations.isEmpty
                ? null
                : _entryNode(destinations[currentIndex >= 0 ? currentIndex : 0]);

    return IgnorePointer(
      ignoring: covered,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: playerOpen ? 250 : 150),
        curve: Curves.easeOut,
        opacity: covered ? 0 : 1,
        child: StackRouterScope(
          controller: widget.router,
          stateHash: widget.router.stateHash,
          // Out of the pad's reach as well while it is covered, or left off
          // a row in a sheet could hand the selection to a bar nobody sees.
          child: ExcludeFocus(
            excluding: covered,
            // The Material a page's scaffold would have given it. Up here in
            // the overlay there is none, so any text without a style of its
            // own came out in Flutter's glaring fallback - large, red and
            // underlined - and ink had nothing to draw on.
            child: Material(
              type: MaterialType.transparency,
              child: SideNavigationRailOverlay(
                currentIndex: currentIndex,
                destinations: destinations,
                currentLocation: routeName,
                // Nodes of this bar's own, one per entry; the shared one is
                // the drawer's.
                useNavFocusNode: false,
                focusNodeFor: _entryNode,
                settingsSelected: settingsSelected,
                settingsFocusNode: _tabNode(HomeTabs.settings),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

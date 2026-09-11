import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/dashboard_mode_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/shared/global_hotkeys.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/home_destinations.dart';
import 'package:fladder/widgets/navigation_scaffold/navigation_scaffold.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

enum HomeTabs {
  dashboard,
  library,
  favorites,
  seerr,
  sync,

  /// A tab like the others, but added after them - last, so the indices the
  /// others had stay what they were.
  search;

  const HomeTabs();

  IconData get icon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusLinear.home_1,
        HomeTabs.library => IconsaxPlusLinear.book,
        HomeTabs.favorites => IconsaxPlusLinear.heart,
        HomeTabs.seerr => IconsaxPlusLinear.discover_1,
        HomeTabs.sync => IconsaxPlusLinear.cloud,
        HomeTabs.search => IconsaxPlusLinear.search_normal_1,
      };

  IconData get selectedIcon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusBold.home_1,
        HomeTabs.library => IconsaxPlusBold.book,
        HomeTabs.favorites => IconsaxPlusBold.heart,
        HomeTabs.seerr => IconsaxPlusBold.discover,
        HomeTabs.sync => IconsaxPlusBold.cloud,
        HomeTabs.search => IconsaxPlusBold.search_normal_1,
      };

  /// The name of the stack this tab keeps its pages on (routes/tab_stack.dart).
  String get stackName => '${name[0].toUpperCase()}${name.substring(1)}Tab';

  /// This tab as the tabs router knows it: a stack with the tab's own page
  /// first, and whatever was opened from there above it.
  PageRouteInfo get route => PageRouteInfo(stackName);

  /// This enum's declaration order IS the tabs router's route order - the
  /// `routes:` list in [HomeScreen] is built from it. Every tab keeps its
  /// index whether or not its button is shown, so hiding Seerr or Downloads
  /// cannot shift what the others point at.

  /// Shows this tab. See [showHomeTab].
  void navigate(BuildContext context) => showHomeTab(context.router.root, this);

  String label(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.localized.dashboard,
        HomeTabs.library => context.localized.library(0),
        HomeTabs.favorites => context.localized.favorites,
        HomeTabs.seerr => 'Seerr',
        HomeTabs.sync => context.localized.sync,
        HomeTabs.search => context.localized.search,
      };
}

/// Shows [tab], from wherever the app is.
///
/// Every tab keeps the pages opened on it, so another tab comes back exactly
/// as it was left. The tab already on screen goes back to its own page
/// instead: pressing it again is how its pages are cleared. Pages over Home -
/// a film opened straight from a link - are closed first.
void showHomeTab(StackRouter root, HomeTabs tab) {
  final tabsRouter = root.innerRouterOf<TabsRouter>(HomeRoute.name);
  if (tabsRouter == null) {
    root.navigate(HomeRoute(children: [tab.route]));
    return;
  }
  if (root.current.name != HomeRoute.name) {
    root.popUntilRouteWithName(HomeRoute.name);
    tabsRouter.setActiveIndex(tab.index);
    return;
  }
  if (tabsRouter.activeIndex == tab.index) {
    tabsRouter.stackRouterOfIndex(tab.index)?.popUntilRoot();
  } else {
    tabsRouter.setActiveIndex(tab.index);
  }
}

/// Home's tabs, in the tabs router's order - which is the enum's.
final List<PageRouteInfo> _tabRoutes = [for (final tab in HomeTabs.values) tab.route];

@RoutePage()
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Future<void> _showDashboardSwitcher(BuildContext context) async {
    // Back to the dashboard's own page, whichever of the two it now is.
    void showDashboard() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final tabsRouter = AutoTabsRouter.of(context);
        tabsRouter.setActiveIndex(HomeTabs.dashboard.index);
        tabsRouter.stackRouterOfIndex(HomeTabs.dashboard.index)?.popUntilRoot();
      });
    }

    await showBottomSheetPill(
      context: context,
      content: (sheetContext, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(IconsaxPlusLinear.home_1),
              title: Text(sheetContext.localized.dashboard),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(musicDashboardModeProvider.notifier).state = false;
                ref.read(windowTitleProvider.notifier).refreshTitle();
                showDashboard();
              },
            ),
            ListTile(
              leading: const Icon(IconsaxPlusLinear.music),
              title: Text(context.localized.musicDashboard),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(musicDashboardModeProvider.notifier).state = true;
                ref.read(windowTitleProvider.notifier).refreshTitle();
                showDashboard();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<DestinationModel> buildDestinations(BuildContext context) => buildHomeDestinations(
          context,
          ref,
          navigateTab: (tab) => tab.navigate(context),
          // Onto the tab on screen, like everything else opened from it.
          navigateRoute: (route) => context.router.push(route),
          onDashboardLongPress: () => _showDashboardSwitcher(context),
        );

    return NotificationManagerInitializer(
      child: GlobalHotkeys(
        enabledHotkeys: GlobalHotKeys.values.toSet(),
        // No hero controller up here: every tab is a navigator of its own, and
        // each brings its own controller (routes/tab_stack.dart).
        child: AutoTabsRouter(
          // Fixed and complete: the tabs router indexes THIS list, so every
          // tab must be present even when its button is hidden.
          routes: _tabRoutes,
          builder: (context, child) {
            final tabsRouter = AutoTabsRouter.of(context);
            final destinations = buildDestinations(context);
            // A page opened on a tab is news to the root router, not to the
            // tabs router - so the root is what this listens to, to know
            // whether the tab is on its own page or on one opened from it.
            return ListenableBuilder(
              listenable: tabsRouter.root,
              builder: (context, _) {
                final tabStack = tabsRouter.stackRouterOfIndex(tabsRouter.activeIndex);
                return _OfflineTabRedirect(
                  child: CustomKeyboardWrapper(
                    child: NavigationScaffold(
                      destinations: destinations,
                      // Asked, not inferred. The active tab is a fact the tabs
                      // router holds; it used to be guessed from the current
                      // route name, and anything that was not a tab read as no
                      // tab at all - which hid the bar and the drawer with it.
                      currentIndex: destinations.indexWhere(
                        (destination) => destination.tab.index == tabsRouter.activeIndex,
                      ),
                      atTabRoot: (tabStack?.stack.length ?? 1) <= 1,
                      nestedChild: child,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Sends the user to Downloads the moment the server goes away.
///
/// Every other tab needs the server, so offline they have nothing to show;
/// the downloads are the only thing that still plays. Only on the transition,
/// so coming back online leaves the tab where it is.
class _OfflineTabRedirect extends ConsumerWidget {
  const _OfflineTabRedirect({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(offlineStateProvider, (previous, next) {
      if (previous == true || !next) return;
      if (!ref.read(showSyncButtonProviderProvider)) return;
      // Not from inside the listener: it runs while this tree is building, and
      // switching tabs there modifies the router's providers mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final tabsRouter = AutoTabsRouter.of(context);
        if (tabsRouter.activeIndex == HomeTabs.sync.index) return;
        tabsRouter.setActiveIndex(HomeTabs.sync.index);
      });
    });
    return child;
  }
}

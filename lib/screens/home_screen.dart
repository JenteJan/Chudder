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

  /// Not a tab of the tabs router at all - a root page - but an entry in the
  /// bar like the others. Last, so the router's indices stay what they were.
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

  /// The route this tab owns. Search has none in the tabs router; its page
  /// is pushed over Home instead.
  PageRouteInfo get route => switch (this) {
        HomeTabs.dashboard => const DashboardRoute(),
        HomeTabs.library => const LibraryRoute(),
        HomeTabs.favorites => const FavouritesRoute(),
        HomeTabs.seerr => const SeerrRoute(),
        HomeTabs.sync => const SyncedRoute(),
        HomeTabs.search => LibrarySearchRoute(),
      };

  /// Whether this is one of the tabs router's pages.
  bool get isTab => this != HomeTabs.search;

  /// This enum's declaration order IS the tabs router's route order - the
  /// `routes:` list in [HomeScreen] must stay in step with it. Every tab keeps
  /// its index whether or not its button is shown, so hiding Seerr or
  /// Downloads cannot shift what the others point at.

  /// Switches tab rather than pushing a route. Tabs used to be entries on one
  /// shared stack, so opening one pushed it on top of the last - which is why
  /// back walked through previously visited tabs.
  void navigate(BuildContext context) {
    if (!isTab) {
      context.router.navigate(route);
      return;
    }
    AutoTabsRouter.of(context).setActiveIndex(index);
  }

  String label(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.localized.dashboard,
        HomeTabs.library => context.localized.library(0),
        HomeTabs.favorites => context.localized.favorites,
        HomeTabs.seerr => 'Seerr',
        HomeTabs.sync => context.localized.sync,
        HomeTabs.search => context.localized.search,
      };
}

@RoutePage()
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// One for the life of the screen. It used to be made in build, so every
  /// rebuild - a download starting, the dashboard mode flipping - installed a
  /// fresh controller over a flight the old one was still running, and leaked
  /// the old one.
  final HeroController _heroController = HeroController();

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  Future<void> _showDashboardSwitcher(BuildContext context) async {
    void switchDashboard(PageRouteInfo route) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          context.router.navigate(route);
        }
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
                switchDashboard(const DashboardRoute());
              },
            ),
            ListTile(
              leading: const Icon(IconsaxPlusLinear.music),
              title: Text(context.localized.musicDashboard),
              onTap: () {
                Navigator.of(sheetContext).pop();
                ref.read(musicDashboardModeProvider.notifier).state = true;
                ref.read(windowTitleProvider.notifier).refreshTitle();
                switchDashboard(const DashboardRoute());
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
          navigateRoute: (route) => context.router.navigate(route),
          onDashboardLongPress: () => _showDashboardSwitcher(context),
        );

    return NotificationManagerInitializer(
      child: GlobalHotkeys(
        enabledHotkeys: GlobalHotKeys.values.toSet(),
        child: HeroControllerScope(
          controller: _heroController,
          child: AutoTabsRouter(
            // Fixed and complete: the tabs router indexes THIS list, so every
            // tab must be present even when its button is hidden.
            routes: const [
              DashboardRoute(),
              LibraryRoute(),
              FavouritesRoute(),
              SeerrRoute(),
              SyncedRoute(),
            ],
            builder: (context, child) {
              final tabsRouter = AutoTabsRouter.of(context);
              final destinations = buildDestinations(context);
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
                    nestedChild: child,
                  ),
                ),
              );
            },
          ),
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

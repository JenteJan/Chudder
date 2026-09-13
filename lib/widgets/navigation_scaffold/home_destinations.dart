import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/providers/dashboard_mode_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/seerr/seerr_models.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:chudder/widgets/navigation_scaffold/components/destination_model.dart';

/// The entries in the navigation bar, wherever the bar is drawn.
///
/// Home builds these for its tabs, and the chrome that stays up over a details
/// page builds the same list - so a film's page and the dashboard show one
/// bar, not two that drifted apart. [navigateTab] is how a tab is reached from
/// wherever the bar is - see `showHomeTab`; [navigateRoute] opens a page on
/// the tab on screen.
List<DestinationModel> buildHomeDestinations(
  BuildContext context,
  WidgetRef ref, {
  required void Function(HomeTabs tab) navigateTab,
  required void Function(PageRouteInfo route) navigateRoute,
  VoidCallback? onDashboardLongPress,
}) {
  final canDownload = ref.watch(showSyncButtonProviderProvider);
  final isMusicDashboardMode = ref.watch(musicDashboardModeProvider);
  final seerrAuthenticated = ref.watch(
    userProvider.select((user) => user?.seerrCredentials?.isConfigured ?? false),
  );

  // Search right after the dashboard: it is the second thing anyone reaches
  // for, and the enum keeps it last only so the tabs router's indices stay
  // what they were.
  const order = [
    HomeTabs.dashboard,
    HomeTabs.search,
    HomeTabs.library,
    HomeTabs.favorites,
    HomeTabs.seerr,
    HomeTabs.sync
  ];
  return order
      .map((e) {
        switch (e) {
          case HomeTabs.dashboard:
            return DestinationModel(
              tab: e,
              label: context.localized.navigationDashboard,
              icon: Icon(
                isMusicDashboardMode ? IconsaxPlusLinear.music_square : IconsaxPlusLinear.home_1,
              ),
              selectedIcon: Icon(
                isMusicDashboardMode ? IconsaxPlusBold.music_square : IconsaxPlusBold.home_1,
              ),
              route: const DashboardRoute(),
              action: () => navigateTab(e),
              onLongPress: onDashboardLongPress,
              onSecondaryTapDown: onDashboardLongPress == null ? null : (_) => onDashboardLongPress(),
            );
          case HomeTabs.search:
            // A tab like the others, with a stack of its own: what you open
            // from the results is still there when you come back to them.
            return DestinationModel(
              tab: e,
              label: context.localized.navigationSearch,
              icon: Icon(e.icon),
              selectedIcon: Icon(e.selectedIcon),
              action: () => navigateTab(e),
            );
          case HomeTabs.favorites:
            return DestinationModel(
              tab: e,
              label: context.localized.navigationFavorites,
              icon: Icon(e.icon),
              selectedIcon: Icon(e.selectedIcon),
              route: const FavouritesRoute(),
              floatingActionButton: AdaptiveFab(
                context: context,
                title: context.localized.filter(0),
                key: Key(e.name.capitalize()),
                onPressed: () => navigateRoute(LibrarySearchRoute(favourites: true)),
                child: const Icon(IconsaxPlusLinear.filter),
              ),
              action: () => navigateTab(e),
            );
          case HomeTabs.seerr:
            if (seerrAuthenticated) {
              return DestinationModel(
                tab: e,
                label: context.localized.discover,
                icon: Icon(e.icon),
                selectedIcon: Icon(e.selectedIcon),
                route: const SeerrRoute(),
                activeRouteName: SeerrSearchRoute.name,
                floatingActionButton: AdaptiveFab(
                  context: context,
                  title: context.localized.search,
                  key: Key(e.name.capitalize()),
                  onPressed: () => navigateRoute(SeerrSearchRoute(
                    mode: SeerrSearchMode.search,
                  )),
                  child: const Icon(IconsaxPlusLinear.search_normal_1),
                ),
                action: () => navigateTab(e),
              );
            }
          case HomeTabs.sync:
            if (canDownload && !kIsWeb) {
              return DestinationModel(
                tab: e,
                label: context.localized.navigationSync,
                icon: Icon(e.icon),
                badge: Consumer(
                  builder: (context, ref, child) {
                    final length = ref.watch(activeDownloadTasksProvider.select((value) => value.length));
                    return length != 0
                        ? CircleAvatar(
                            radius: 10,
                            child: FittedBox(
                              child: Text(length.toString()),
                            ),
                          )
                        : const SizedBox.shrink();
                  },
                ),
                selectedIcon: Icon(e.selectedIcon),
                route: const SyncedRoute(),
                action: () => navigateTab(e),
              );
            }
          case HomeTabs.library:
            if (!isMusicDashboardMode) {
              return DestinationModel(
                tab: e,
                label: context.localized.library(0),
                icon: Icon(e.icon),
                selectedIcon: Icon(e.selectedIcon),
                route: const LibraryRoute(),
                action: () => navigateTab(e),
              );
            }
          // Not in [order]: the profile picture at the foot of the bar is
          // this tab's button.
          case HomeTabs.settings:
            break;
        }
        return null;
      })
      .nonNulls
      .toList();
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/dashboard_mode_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/screens/shared/global_hotkeys.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/string_extensions.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/navigation_scaffold.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

enum HomeTabs {
  dashboard,
  library,
  favorites,
  seerr,
  sync;

  const HomeTabs();

  IconData get icon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusLinear.home_1,
        HomeTabs.library => IconsaxPlusLinear.book,
        HomeTabs.favorites => IconsaxPlusLinear.heart,
        HomeTabs.seerr => IconsaxPlusLinear.discover_1,
        HomeTabs.sync => IconsaxPlusLinear.cloud,
      };

  IconData get selectedIcon => switch (this) {
        HomeTabs.dashboard => IconsaxPlusBold.home_1,
        HomeTabs.library => IconsaxPlusBold.book,
        HomeTabs.favorites => IconsaxPlusBold.heart,
        HomeTabs.seerr => IconsaxPlusBold.discover,
        HomeTabs.sync => IconsaxPlusBold.cloud,
      };

  /// The route this tab owns, whether or not its destination is currently
  /// built. [_navigationRouteName] needs to tell "a tab we are not showing"
  /// apart from "a screen that means to hide the navigation".
  PageRouteInfo get route => switch (this) {
        HomeTabs.dashboard => const DashboardRoute(),
        HomeTabs.library => const LibraryRoute(),
        HomeTabs.favorites => const FavouritesRoute(),
        HomeTabs.seerr => const SeerrRoute(),
        HomeTabs.sync => const SyncedRoute(),
      };

  Future navigate(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.router.navigate(const DashboardRoute()),
        HomeTabs.library => context.router.navigate(const LibraryRoute()),
        HomeTabs.favorites => context.router.navigate(const FavouritesRoute()),
        HomeTabs.seerr => context.router.navigate(const SeerrRoute()),
        HomeTabs.sync => context.router.navigate(const SyncedRoute()),
      };

  String label(BuildContext context) => switch (this) {
        HomeTabs.dashboard => context.localized.dashboard,
        HomeTabs.library => context.localized.library(0),
        HomeTabs.favorites => context.localized.favorites,
        HomeTabs.seerr => 'Seerr',
        HomeTabs.sync => context.localized.sync,
      };
}

@RoutePage()
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _showDashboardSwitcher(BuildContext context, WidgetRef ref) async {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final canDownload = ref.watch(showSyncButtonProviderProvider);
    final isMusicDashboardMode = ref.watch(musicDashboardModeProvider);
    final seerrAuthenticated = ref.watch(
      userProvider.select((user) => user?.seerrCredentials?.isConfigured ?? false),
    );
    // Built from the router's OWN context, supplied by the AutoRouter builder
    // below. Asking `context.router` up here answers with the PARENT router,
    // whose current route is never one of the tabs - which silently made the
    // Downloads tab vanish underneath the route that was on screen.
    List<DestinationModel> buildDestinations(BuildContext context) {
      final onSyncedRoute = context.router.current.name == const SyncedRoute().routeName;
      return HomeTabs.values
        .map((e) {
          switch (e) {
            case HomeTabs.dashboard:
              return DestinationModel(
                label: context.localized.navigationDashboard,
                icon: Icon(
                  isMusicDashboardMode ? IconsaxPlusLinear.music_square : IconsaxPlusLinear.home_1,
                ),
                selectedIcon: Icon(
                  isMusicDashboardMode ? IconsaxPlusBold.music_square : IconsaxPlusBold.home_1,
                ),
                route: const DashboardRoute(),
                action: () => e.navigate(context),
                onLongPress: () => _showDashboardSwitcher(context, ref),
                onSecondaryTapDown: (_) => _showDashboardSwitcher(context, ref),
              );
            case HomeTabs.favorites:
              return DestinationModel(
                label: context.localized.navigationFavorites,
                icon: Icon(e.icon),
                selectedIcon: Icon(e.selectedIcon),
                route: const FavouritesRoute(),
                floatingActionButton: AdaptiveFab(
                  context: context,
                  title: context.localized.filter(0),
                  key: Key(e.name.capitalize()),
                  onPressed: () => context.router.navigate(LibrarySearchRoute(favourites: true)),
                  child: const Icon(IconsaxPlusLinear.search_normal_1),
                ),
                action: () => e.navigate(context),
              );
            case HomeTabs.seerr:
              if (seerrAuthenticated) {
                return DestinationModel(
                  label: context.localized.discover,
                  icon: Icon(e.icon),
                  selectedIcon: Icon(e.selectedIcon),
                  route: const SeerrRoute(),
                  floatingActionButton: AdaptiveFab(
                    context: context,
                    title: context.localized.search,
                    key: Key(e.name.capitalize()),
                    onPressed: () => context.router.navigate(SeerrSearchRoute(
                      mode: SeerrSearchMode.search,
                    )),
                    child: const Icon(IconsaxPlusLinear.search_normal_1),
                  ),
                  action: () => e.navigate(context),
                );
              }
            case HomeTabs.sync:
              if ((canDownload || onSyncedRoute) && !kIsWeb) {
                return DestinationModel(
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
                  action: () => e.navigate(context),
                );
              }
            case HomeTabs.library:
              if (!isMusicDashboardMode) {
                return DestinationModel(
                  label: context.localized.library(0),
                  icon: Icon(e.icon),
                  selectedIcon: Icon(e.selectedIcon),
                  route: const LibraryRoute(),
                  action: () => e.navigate(context),
                  floatingActionButton: AdaptiveFab(
                    context: context,
                    title: context.localized.search,
                    key: Key(e.name.capitalize()),
                    onPressed: () => context.router.navigate(LibrarySearchRoute()),
                    child: const Icon(IconsaxPlusLinear.search_normal_1),
                  ),
                );
              }
          }
        })
        .nonNulls
        .toList();
    }

    return NotificationManagerInitializer(
      child: GlobalHotkeys(
        enabledHotkeys: GlobalHotKeys.values.toSet(),
        child: HeroControllerScope(
          controller: HeroController(),
          child: AutoRouter(
            builder: (context, child) {
              // Subscribe to the router. `context.router` is a plain read, so
              // popping a details screen changed the stack without rebuilding
              // any of this: the bar and the drawer kept resolving against the
              // route we had LEFT, which is not a destination - so the tabs
              // hid and `drawer:` was built as null while the popped-to page
              // sat on screen. That is the dead hamburger.
              AutoRouter.of(context, watch: true);
              // The video player is pushed on the ROOT router, so popping out
              // of it never notified the nested one - the bar and drawer kept
              // resolving against the route we were on before playing. Watch
              // both, so anything that changes either stack rebuilds this.
              context.watchRouter;
              final destinations = buildDestinations(context);
              return _NavigationGuard(
                destinations: destinations,
                child: CustomKeyboardWrapper(
                  child: NavigationScaffold(
                    destinations: destinations,
                    currentRouteName: _navigationRouteName(context, destinations),
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

/// Which destination the navigation should consider itself on.
///
/// Normally just the router's current route. Everything the app is navigated
/// with hangs off this one answer - the drawer, the bottom bar, the search
/// button and the side bar are all built only while a destination matches - so
/// an answer the navigation does not recognise takes all of them away together
/// and leaves no way anywhere except restarting the app.
///
/// A details screen is not recognised either, and that is correct: overview and
/// details routes are siblings in this router, and a details screen is meant to
/// put the navigation away. So not-recognised on its own is no reason to
/// override anything.
///
/// What is not correct is a current route that is not a page in this stack at
/// all. `RouteData get current => currentChild ?? routeData` - with no current
/// child a router answers with its own route rather than one of its children,
/// and that route is never a destination. The navigation then disappears with
/// an overview screen still on display and nothing to bring it back. In that
/// case, and only then, take the nearest route below that is recognised.
String? _navigationRouteName(BuildContext context, List<DestinationModel> destinations) {
  final router = context.router;
  final current = router.current.name;

  final known = destinations.map((destination) => destination.route?.routeName).nonNulls.toSet();
  if (known.contains(current)) return current;

  // A tab whose destination is not being built right now - Downloads goes
  // away whenever the app cannot confirm the download permission, which is
  // every cold start without a server. Sitting on such a route is the one
  // case that must never hide the navigation: the tab that would bring it
  // back is precisely the one that is missing, so the user is stranded.
  final tabRoutes = HomeTabs.values.map((tab) => tab.route.routeName).toSet();
  final onOrphanedTab = tabRoutes.contains(current);

  final stack = router.stackData;
  // A real page in this stack - a details screen, settings, the control panel.
  // Those are entitled to say the navigation does not apply to them.
  if (!onOrphanedTab && stack.any((data) => data.name == current)) return current;

  for (final data in stack.reversed) {
    if (known.contains(data.name)) return data.name;
  }

  return current;
}

/// Keeps the navigation reachable.
///
/// Two jobs, both of which have to run UNDER the AutoRouter: above it,
/// `context.router` is the parent router whose current route is never one of
/// the tabs, so anything asked up there gets the wrong answer.
///
/// 1. When the server goes away, move to Downloads - every other tab needs the
///    server, and the downloads are the only thing that still plays. Only on
///    the transition and only from a tab, so a details screen or the player is
///    not interrupted.
/// 2. When the router lands somewhere the navigation cannot place at all, go
///    somewhere valid. The bar is built only while a destination matches, so
///    an unplaceable route hides every way off the screen; a details screen or
///    any other real page in the stack is left alone, because those are meant
///    to hide the navigation and can still be popped.
class _NavigationGuard extends ConsumerWidget {
  const _NavigationGuard({required this.destinations, required this.child});

  final List<DestinationModel> destinations;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(offlineStateProvider, (previous, next) {
      if (previous == true || !next) return;
      if (!ref.read(showSyncButtonProviderProvider)) return;
      // Not from inside the listener: it runs while this tree is building, and
      // navigating there modifies the router's providers mid-build. By the
      // next frame this may be gone, which is its own crash if we touch it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final current = context.router.current.name;
        if (current == const SyncedRoute().routeName) return;
        if (!HomeTabs.values.any((tab) => tab.route.routeName == current)) return;
        HomeTabs.sync.navigate(context);
      });
    });

    final known = destinations.map((destination) => destination.route?.routeName).nonNulls.toSet();
    final stack = context.router.stackData;
    final current = context.router.current.name;
    // An empty stack is a router that has not built its first child yet, not a
    // stranded one: `current` falls back to the router's own route until it
    // does. Recovering there pushed a second Dashboard on top of the one the
    // router was about to create, and that duplicate is what made going back
    // land on the Dashboard again instead of leaving it.
    final stranded = stack.isNotEmpty &&
        !known.contains(current) &&
        !stack.any((data) => data.name == current);
    if (stranded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        // Re-check: a frame later the router may have settled on its own.
        final now = context.router.current.name;
        final nowStack = context.router.stackData;
        if (nowStack.isEmpty || known.contains(now) || nowStack.any((data) => data.name == now)) {
          return;
        }
        final offline = ref.read(offlineStateProvider);
        final target = offline && known.contains(const SyncedRoute().routeName)
            ? HomeTabs.sync
            : HomeTabs.dashboard;
        // replaceAll, not navigate: the stack we are recovering FROM is the
        // problem, and navigating would push onto it and leave the bad entries
        // underneath - so going back walks straight into them again. This
        // rebuilds the stack as a single valid route.
        context.router.replaceAll([target.route]);
      });
    }

    return child;
  }
}

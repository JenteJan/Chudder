import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/theme_extensions.dart';

@RoutePage()
class JellybotScreen extends ConsumerStatefulWidget {
  const JellybotScreen({super.key});

  @override
  ConsumerState<JellybotScreen> createState() => _JellybotScreenState();
}

class _JellybotScreenState extends ConsumerState<JellybotScreen> {
  final scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return AutoTabsRouter(
      builder: (context, content) {
        checkForNullIndex(context);
        return PopScope(
          canPop: context.tabsRouter.activeIndex == 0 || AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              context.tabsRouter.setActiveIndex(0);
            }
          },
          child: AdaptiveLayout.layoutModeOf(context) == LayoutMode.single
              ? Card(
                  elevation: 0,
                  child: Stack(
                    children: [_leftPane(context), content],
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: _leftPane(context)),
                    Expanded(
                      flex: 3,
                      child: content,
                    ),
                  ],
                ),
        );
      },
    );
  }

  void checkForNullIndex(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentIndex = context.tabsRouter.activeIndex;
      if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual && currentIndex == 0) {
        context.tabsRouter.setActiveIndex(1);
      }
    });
  }

  Widget _leftPane(BuildContext context) {
    void navigateTo(PageRouteInfo route) => context.tabsRouter.navigate(route);

    bool containsRoute(PageRouteInfo route) =>
        AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual && context.tabsRouter.current.name == route.routeName;

    return Padding(
      padding: EdgeInsets.only(left: AdaptiveLayout.of(context).sideBarWidth),
      child: Container(
        color: context.colors.surface,
        child: SettingsScaffold(
          label: context.localized.jellybot,
          scrollController: scrollController,
          showBackButtonNested: true,
          items: [
            SettingsListTile(
              label: Text(context.localized.jellybotProviderSearch),
              subLabel: Text(context.localized.jellybotProviderSearchDesc),
              autoFocus: true,
              selected: containsRoute(const JellybotProviderSearchRoute()),
              icon: IconsaxPlusLinear.search_normal,
              onTap: () => navigateTo(const JellybotProviderSearchRoute()),
            ),
            SettingsListTile(
              label: Text(context.localized.jellybotCrawlLinks),
              subLabel: Text(context.localized.jellybotCrawlLinksDesc),
              selected: containsRoute(const JellybotCrawlLinksRoute()),
              icon: IconsaxPlusLinear.link_21,
              onTap: () => navigateTo(const JellybotCrawlLinksRoute()),
            ),
            SettingsListTile(
              label: Text(context.localized.jellybotDownloads),
              subLabel: Text(context.localized.jellybotDownloadsDesc),
              selected: containsRoute(const JellybotDownloadsRoute()),
              icon: IconsaxPlusLinear.arrow_down_2,
              onTap: () => navigateTo(const JellybotDownloadsRoute()),
            ),
            SettingsListTile(
              label: Text(context.localized.jellybotAdmin),
              subLabel: Text(context.localized.jellybotAdminDesc),
              selected: containsRoute(const JellybotAdminRoute()),
              icon: IconsaxPlusLinear.setting_2,
              onTap: () => navigateTo(const JellybotAdminRoute()),
            ),
          ],
        ),
      ),
    );
  }
}

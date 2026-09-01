import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/util/localization_helper.dart';

import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_button.dart';

class DestinationModel {
  /// Which tab this button selects. The bar shows a subset of the tabs
  /// router's fixed route list, so a button's position is not its index.
  final HomeTabs tab;
  final String label;
  final Widget? icon;
  final Widget? selectedIcon;
  final PageRouteInfo? route;
  final Function()? action;
  final Function()? onLongPress;
  final Function(TapDownDetails details)? onSecondaryTapDown;
  final String? tooltip;
  final Widget? badge;
  final AdaptiveFab? floatingActionButton;

  /// Custom FAB widget - takes precedence over floatingActionButton if provided
  final Widget? customFab;

  DestinationModel({
    required this.tab,
    required this.label,
    this.icon,
    this.selectedIcon,
    this.route,
    this.action,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.tooltip,
    this.badge,
    this.floatingActionButton,
    this.customFab,
  });

  /// Returns the FAB widget to use - prefers customFab over floatingActionButton.normal
  Widget? get fabWidget => customFab ?? floatingActionButton?.normal;

  /// The corner action for a screen that doesn't define one of its own. Every
  /// overview screen has a button in the same corner doing the same thing.
  static AdaptiveFab searchFab(BuildContext context) => AdaptiveFab(
        context: context,
        title: context.localized.search,
        key: const Key('search_action'),
        onPressed: () => context.router.navigate(LibrarySearchRoute()),
        child: const Icon(IconsaxPlusLinear.search_normal_1),
      );

  /// Converts this [DestinationModel] to a [NavigationRailDestination] used in a [NavigationRail].
  NavigationRailDestination toNavigationRailDestination({EdgeInsets? padding}) {
    return NavigationRailDestination(
      icon: icon!,
      label: Text(label),
      selectedIcon: selectedIcon,
      padding: padding,
    );
  }

  /// Converts this [DestinationModel] to a [NavigationDrawerDestination] used in a [NavigationDrawer].
  NavigationDrawerDestination toNavigationDrawerDestination() {
    return NavigationDrawerDestination(
      icon: icon!,
      label: Text(label),
      selectedIcon: selectedIcon,
    );
  }

  /// Converts this [DestinationModel] to a [NavigationDestination] used in a [BottomNavigationBar].
  NavigationDestination toNavigationDestination() {
    return NavigationDestination(
      icon: icon!,
      label: label,
      selectedIcon: selectedIcon,
      tooltip: tooltip,
    );
  }

  NavigationButton toNavigationButton(bool selected, bool horizontal, bool expanded,
      {bool navFocusNode = false, Widget? customIcon}) {
    return NavigationButton(
      label: label,
      selected: selected,
      navFocusNode: navFocusNode,
      badge: badge,
      onPressed: action,
      onLongPress: onLongPress,
      onSecondaryTapDown: onSecondaryTapDown,
      horizontal: horizontal,
      expanded: expanded,
      customIcon: customIcon,
      selectedIcon: selectedIcon!,
      icon: icon!,
    );
  }
}

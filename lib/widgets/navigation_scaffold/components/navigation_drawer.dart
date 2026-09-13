import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/view_model.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_button.dart';
import 'package:chudder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_buttons.dart';
import 'package:chudder/widgets/shared/custom_tooltip.dart';

/// The bar a phone slides in, built to the same measurements as the one a
/// desktop window keeps open beside its pages.
///
/// It used to be a Material [NavigationDrawer], which is 360 wide by default -
/// most of a phone's screen, and nearly twice the width of the same bar on a
/// desktop, for the same list of entries. It is the desktop bar now: the same
/// width, the same chevron at the top, the same entries, and the profile
/// pinned to the bottom rather than sitting at the end of the list.
class NestedNavigationDrawer extends ConsumerWidget {
  final bool isExpanded;
  final Function(bool expanded) toggleExpanded;
  final List<DestinationModel> destinations;
  final List<ViewModel> views;
  final String currentLocation;
  final int currentIndex;
  const NestedNavigationDrawer({
    this.isExpanded = false,
    required this.toggleExpanded,
    required this.destinations,
    required this.currentLocation,
    required this.views,
    required this.currentIndex,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final padding = MediaQuery.paddingOf(context);
    final startInset = isRtl ? padding.right : padding.left;

    return Drawer(
      key: const Key('navigation_drawer'),
      // The desktop bar's own width, plus whatever the screen's edge takes.
      width: SideNavigationRail.expandedWidth + startInset,
      backgroundColor: isExpanded ? Colors.transparent : null,
      surfaceTintColor: isExpanded ? Colors.transparent : null,
      child: SafeArea(
        // The far edge is the drawer's own; only the screen's near edge eats
        // into it, and that is already in the width above.
        left: !isRtl,
        right: isRtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            spacing: 2,
            children: [
              // The same chevron the desktop bar folds itself with, pointing
              // the way this one leaves.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: IconButton(
                    tooltip: context.localized.navigation,
                    icon: Icon(isRtl ? IconsaxPlusLinear.arrow_right_3 : IconsaxPlusLinear.arrow_left_1),
                    onPressed: () => toggleExpanded(false),
                  ),
                ),
              ),
              // Everything between the chevron and the profile scrolls, so a
              // long library list cannot push the profile off the bottom.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: SideNavigationButtons(
                        largeBar: true,
                        destinations: destinations,
                        tooltipPosition: isRtl ? TooltipPosition.left : TooltipPosition.right,
                        currentIndex: currentIndex,
                        shouldExpand: true,
                        useOverflow: false,
                      ),
                    ),
                  ),
                ),
              ),
              NavigationButton(
                label: context.localized.settings,
                selected: settingsTabShown(context.router.root),
                selectedIcon: const Icon(IconsaxPlusBold.setting_3),
                horizontal: true,
                expanded: true,
                icon: const SizedBox.shrink(),
                customIcon: const ExcludeFocusTraversal(
                  child: SizedBox.square(dimension: 40, child: SettingsUserIcon()),
                ),
                onPressed: () => showHomeTab(context.router.root, HomeTabs.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

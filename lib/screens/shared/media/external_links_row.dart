import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/external_links.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

/// Where else something can be opened, behind one small button: a menu of
/// the sites, each in its own colour as a dot beside the name. Quiet enough
/// to sit at the end of a line of scores without competing with anything.
class LinksMenuButton extends ConsumerWidget {
  final List<ExternalLink> links;

  const LinksMenuButton({required this.links, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (links.isEmpty || ref.watch(argumentsStateProvider).htpcMode) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final actions = links
        .map(
          (link) => ItemActionButton(
            icon: _SiteDot(site: link.site),
            label: Text(link.site == ExternalSite.other ? link.name : context.localized.openIn(link.site.label)),
            action: () => launchUrl(context, link.url),
          ),
        )
        .toList();

    final icon = Icon(IconsaxPlusLinear.export_3, size: 18, color: colors.onSurface.withValues(alpha: 0.6));
    if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer) {
      return PopupMenuButton(
        tooltip: context.localized.links,
        icon: icon,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        itemBuilder: (context) => actions.popupMenuItems(useIcons: true),
      );
    }
    return IconButton(
      tooltip: context.localized.links,
      icon: icon,
      visualDensity: VisualDensity.compact,
      onPressed: () => showBottomSheetPill(
        context: context,
        content: (context, scrollController) => ListView(
          shrinkWrap: true,
          controller: scrollController,
          children: actions.listTileItems(context, useIcons: true),
        ),
      ),
    );
  }
}

class _SiteDot extends StatelessWidget {
  final ExternalSite site;
  const _SiteDot({required this.site});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: site == ExternalSite.other ? Theme.of(context).colorScheme.onSurfaceVariant : site.color,
        shape: BoxShape.circle,
      ),
    );
  }
}

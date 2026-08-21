import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/widgets/navigation_scaffold/components/playback_chrome_actions.dart';
import 'package:fladder/widgets/syncplay/syncplay_utils.dart';

/// Reusable button that opens the SyncPlay group sheet. Reflects the active
/// state (filled icon + accent dot) and adapts between a compact icon button
/// and a full-width labelled button via [extended]. Used across the navigation
/// chrome and the video player so SyncPlay is reachable everywhere.
class SyncPlayButton extends ConsumerWidget {
  const SyncPlayButton({
    super.key,
    this.extended = false,
    this.background = false,
  });

  /// When true renders a full-width labelled button; otherwise a compact icon.
  final bool extended;

  /// Chrome fill, for the app bar and navigation rails. The player controls
  /// have their own backdrop and want the button bare.
  final bool background;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(isSyncPlayActiveProvider);

    if (extended) {
      return AdaptiveFab(
        context: context,
        title: context.localized.syncPlay,
        backgroundColor: isActive ? Theme.of(context).colorScheme.primaryContainer : null,
        onPressed: () => showSyncPlaySheet(context),
        child: _SyncPlayIcon(isActive: isActive),
      ).extended;
    }

    // No background: being active reads from the filled icon and its accent
    // dot, so the button doesn't need a tonal chip behind it as well.
    return IconButton(
      iconSize: 26,
      tooltip: context.localized.syncPlay,
      onPressed: () => showSyncPlaySheet(context),
      color: isActive ? Theme.of(context).colorScheme.primary : null,
      style: background ? chromeButtonStyle(context) : null,
      icon: Padding(
        padding: const EdgeInsets.all(8.0),
        child: _SyncPlayIcon(isActive: isActive),
      ),
    );
  }
}

class _SyncPlayIcon extends StatelessWidget {
  const _SyncPlayIcon({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Icon(isActive ? IconsaxPlusBold.people : IconsaxPlusLinear.people),
        if (isActive)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

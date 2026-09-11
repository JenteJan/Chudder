import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/item_membership_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/collections/add_to_collection.dart';
import 'package:fladder/screens/playlists/add_to_playlists.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

/// The item's menu: a row of the four states you flip most - favourite,
/// watched, in a collection, in a playlist - each one button that shows
/// whether it is on, and the rest of the actions as a list under it.
///
/// The list used to spell every state out twice, "mark as watched" and "mark
/// as unwatched" one under the other; the page's own header carried a copy of
/// two of them as well. One button per state, in the menu, and the header
/// keeps only play.
Future<void> showItemActionsSheet(
  BuildContext context,
  WidgetRef ref,
  ItemBaseModel item, {
  Set<ItemActions> exclude = const {},
  FutureOr<void> Function()? onFavorite,
}) async {
  final isAdmin = ref.read(userProvider)?.policy?.isAdministrator ?? false;
  final canCollect = isAdmin && item.type != FladderItemType.boxset;
  final canPlaylist = item.type != FladderItemType.playlist;
  await showBottomSheetPill(
    context: context,
    item: item,
    content: (sheet, scrollController) => ListView(
      controller: scrollController,
      shrinkWrap: true,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: ItemQuickToggles(
            item: item,
            onFavorite: onFavorite,
            showCollection: canCollect,
            showPlaylist: canPlaylist,
          ),
        ),
        ...item.generateActions(
          context,
          ref,
          exclude: {
            ItemActions.setFavorite,
            ItemActions.markPlayed,
            ItemActions.markUnplayed,
            if (canCollect) ItemActions.addCollection,
            if (canPlaylist) ItemActions.addPlaylist,
            ...exclude,
          },
        ).listTileItems(sheet, useIcons: true),
      ],
    ),
  );
  if (context.mounted) context.refreshData();
}

/// The four state buttons themselves. Keeps its own copy of the two states it
/// can flip on the spot, so the sheet shows the change without waiting for
/// the page behind it to reload.
class ItemQuickToggles extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  final FutureOr<void> Function()? onFavorite;
  final bool showCollection;
  final bool showPlaylist;

  const ItemQuickToggles({
    required this.item,
    this.onFavorite,
    this.showCollection = true,
    this.showPlaylist = true,
    super.key,
  });

  @override
  ConsumerState<ItemQuickToggles> createState() => _ItemQuickTogglesState();
}

class _ItemQuickTogglesState extends ConsumerState<ItemQuickToggles> {
  late bool _favourite = widget.item.userData.isFavourite;
  late bool _watched = widget.item.userData.played;
  String? _busy;

  Future<void> _run(String key, FutureOr<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = widget.item;
    final membership = ref.watch(itemMembershipProvider(item.id)).valueOrNull ?? ItemMembership.unknown;

    Future<void> afterMembershipChange() async {
      ref.read(membershipCacheProvider).invalidate();
      ref.invalidate(itemMembershipProvider(item.id));
    }

    return Row(
      spacing: 8,
      children: [
        Expanded(
          child: _ToggleTile(
            icon: _favourite ? IconsaxPlusBold.heart : IconsaxPlusLinear.heart,
            label: context.localized.favorite,
            selected: _favourite,
            color: const Color(0xFFE0304A),
            busy: _busy == 'favourite',
            onTap: () => _run('favourite', () async {
              if (widget.onFavorite != null) {
                await widget.onFavorite!();
              } else {
                await ref.read(userProvider.notifier).setAsFavorite(!_favourite, item.id);
              }
              if (mounted) setState(() => _favourite = !_favourite);
            }),
          ),
        ),
        Expanded(
          child: _ToggleTile(
            icon: _watched ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.tick_circle,
            label: context.localized.played,
            selected: _watched,
            color: colors.primary,
            busy: _busy == 'watched',
            onTap: () => _run('watched', () async {
              await ref.read(userProvider.notifier).markAsPlayed(!_watched, item.id);
              if (mounted) setState(() => _watched = !_watched);
            }),
          ),
        ),
        if (widget.showCollection)
          Expanded(
            child: _ToggleTile(
              icon: membership.inCollection == true ? IconsaxPlusBold.folder_2 : IconsaxPlusLinear.folder_2,
              label: context.localized.mediaTypeBoxset(1),
              selected: membership.inCollection == true,
              color: colors.tertiary,
              busy: _busy == 'collection',
              onTap: () => _run('collection', () async {
                await addItemToCollection(context, [item]);
                await afterMembershipChange();
              }),
            ),
          ),
        if (widget.showPlaylist)
          Expanded(
            child: _ToggleTile(
              icon: membership.inPlaylist == true ? IconsaxPlusBold.music_playlist : IconsaxPlusLinear.music_playlist,
              label: context.localized.mediaTypePlaylist(1),
              selected: membership.inPlaylist == true,
              color: colors.secondary,
              busy: _busy == 'playlist',
              onTap: () => _run('playlist', () async {
                await addItemToPlaylist(context, [item]);
                await afterMembershipChange();
              }),
            ),
          ),
      ],
    );
  }
}

/// One state as a tile: icon over a short word, filled in its colour while on.
class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final bool busy;
  final VoidCallback onTap;

  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.white : colors.onSurface;
    return FocusButton(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      darkOverlay: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : colors.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            busy
                ? SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: foreground),
                  )
                : Icon(icon, size: 22, color: foreground),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

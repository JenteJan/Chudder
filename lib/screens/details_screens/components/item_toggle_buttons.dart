import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/providers/item_membership_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/collections/add_to_collection.dart';
import 'package:chudder/screens/playlists/add_to_playlists.dart';
import 'package:chudder/util/favourite_prompt.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/modal_bottom_sheet.dart';

/// The actions a state button stands in for, so the list under the buttons
/// does not offer them a second time.
const _stateKinds = {
  ItemActions.setFavorite,
  ItemActions.markPlayed,
  ItemActions.markUnplayed,
  ItemActions.addCollection,
  ItemActions.addPlaylist,
};

/// An item's menu, wherever it is opened from: a row of buttons for the
/// states you flip most - favourite, watched, in a collection, in a playlist -
/// each showing whether it is on, and the rest of the actions as a list under
/// them.
///
/// [actions] is whatever the caller would have listed - its own exclusions,
/// extra entries and callbacks included - and defaults to the item's standard
/// set. A state gets a button only when that list offers it, so an item that
/// cannot be marked watched, or a user who cannot collect, simply sees fewer.
/// The list used to spell every state out twice, "mark as watched" and "mark
/// as unwatched" one under the other.
Future<void> showItemActionsSheet(
  BuildContext context,
  WidgetRef ref,
  ItemBaseModel item, {
  List<ItemAction>? actions,
  Set<ItemActions> exclude = const {},
  FutureOr<void> Function()? onFavorite,
  void Function(UserData? newData)? onUserDataChanged,
}) async {
  final all = actions ??
      item.generateActions(
        context,
        ref,
        exclude: exclude,
        onUserDataChanged: onUserDataChanged,
      );
  bool offers(ItemActions kind) => all.any((action) => action is ItemActionButton && action.kind == kind);
  final showFavourite = offers(ItemActions.setFavorite);
  final showWatched = offers(ItemActions.markPlayed) || offers(ItemActions.markUnplayed);
  final showCollection = offers(ItemActions.addCollection);
  final showPlaylist = offers(ItemActions.addPlaylist);
  final rest = _withoutStrayDividers(
    all.where((action) => !(action is ItemActionButton && _stateKinds.contains(action.kind))),
  );

  // Only a button pressed in the sheet itself leaves the page behind stale;
  // the list's own entries reload it when they are done.
  var changed = false;
  await showBottomSheetPill(
    context: context,
    item: item,
    content: (sheet, scrollController) => ListView(
      controller: scrollController,
      shrinkWrap: true,
      children: [
        if (showFavourite || showWatched || showCollection || showPlaylist)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: ItemQuickToggles(
              item: item,
              onFavorite: onFavorite,
              onUserDataChanged: onUserDataChanged,
              onChanged: () => changed = true,
              showFavourite: showFavourite,
              showWatched: showWatched,
              showCollection: showCollection,
              showPlaylist: showPlaylist,
            ),
          ),
        ...rest.listTileItems(sheet, useIcons: true),
      ],
    ),
  );
  if (changed && context.mounted) context.refreshData();
}

/// The list with the entries the buttons replace taken out: no divider first
/// or last, and never two in a row where the entries between them went.
List<ItemAction> _withoutStrayDividers(Iterable<ItemAction> actions) {
  final result = <ItemAction>[];
  for (final action in actions) {
    if (action is ItemActionDivider && (result.isEmpty || result.last is ItemActionDivider)) continue;
    result.add(action);
  }
  while (result.isNotEmpty && result.last is ItemActionDivider) {
    result.removeLast();
  }
  return result;
}

/// The state buttons themselves. Keeps its own copy of the two states it can
/// flip on the spot, so the sheet shows the change without waiting for the
/// page behind it to reload.
class ItemQuickToggles extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  final FutureOr<void> Function()? onFavorite;
  final void Function(UserData? newData)? onUserDataChanged;
  final VoidCallback? onChanged;
  final bool showFavourite;
  final bool showWatched;
  final bool showCollection;
  final bool showPlaylist;

  const ItemQuickToggles({
    required this.item,
    this.onFavorite,
    this.onUserDataChanged,
    this.onChanged,
    this.showFavourite = true,
    this.showWatched = true,
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

  Future<void> _run(String key, FutureOr<bool> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      if (await action()) widget.onChanged?.call();
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
        if (widget.showFavourite)
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
                  // The prompt the list's own entry asks: an episode can take
                  // its show with it.
                  final newData = await setAsFavoriteWithPrompt(context, ref, item, !_favourite);
                  if (newData == null) return false;
                  widget.onUserDataChanged?.call(newData);
                }
                if (mounted) setState(() => _favourite = !_favourite);
                return true;
              }),
            ),
          ),
        if (widget.showWatched)
          Expanded(
            child: _ToggleTile(
              icon: _watched ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.tick_circle,
              label: context.localized.played,
              selected: _watched,
              color: colors.primary,
              busy: _busy == 'watched',
              onTap: () => _run('watched', () async {
                final response = await ref.read(userProvider.notifier).markAsPlayed(!_watched, item.id);
                widget.onUserDataChanged?.call(response?.body);
                if (mounted) setState(() => _watched = !_watched);
                return true;
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
                return true;
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
                return true;
              }),
            ),
          ),
      ],
    );
  }
}

/// One state as a tile: its icon, and the word under it where there is room.
///
/// On says so in the colour of the icon and the word, over a faint wash of
/// the same colour - not a block of it with the word inverted, which shouted
/// over everything else in the sheet. Narrower than a word fits, the tile
/// keeps only its icon and says the word as a tooltip: four across a phone
/// has no room for them, and the icons carry the meaning anyway.
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
    final foreground = selected ? color : colors.onSurface.withValues(alpha: 0.75);
    final background = selected ? color.withValues(alpha: 0.14) : colors.surfaceContainerHighest.withValues(alpha: 0.45);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel = constraints.maxWidth >= 84;
        final tile = FocusButton(
          // Kept non-null while the request is in flight. A FocusButton with
          // nothing to do drops its Focus widget altogether, so nulling this
          // mid-press unfocused the tile and handed the pad to the one beside
          // it - press favourite and the selection appeared on watched. [_run]
          // already ignores a second press while one is running.
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          darkOverlay: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(vertical: showLabel ? 12 : 14),
            decoration: BoxDecoration(
              color: background,
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
                if (showLabel)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
              ],
            ),
          ),
        );
        return showLabel ? tile : Tooltip(message: label, child: tile);
      },
    );
  }
}

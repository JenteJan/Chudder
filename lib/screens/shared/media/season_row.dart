import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/providers/sync/sync_provider_helpers.dart';
import 'package:fladder/screens/syncing/sync_button.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/shared/clickable_text.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/status_card.dart';

class SeasonsRow extends ConsumerWidget {
  final EdgeInsets contentPadding;
  final List<SeasonModel>? seasons;

  /// Marked the way the episode row marks the episode you are on.
  final int? currentSeason;

  /// Given, a season is picked where it stands rather than opened.
  final ValueChanged<SeasonModel>? onSeasonTap;

  const SeasonsRow({
    super.key,
    required this.seasons,
    this.currentSeason,
    this.onSeasonTap,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = seasons ?? [];
    // indexWhere gives -1 for a season that is not in the list, which as a
    // scroll position would be an error rather than the start of the row.
    final currentIndex = currentSeason == null ? 0 : items.indexWhere((season) => season.season == currentSeason);

    return HorizontalList(
      label: context.localized.season(items.length),
      items: items,
      // The same ratio the cast row uses, so seasons and faces are one size.
      dominantRatio: 0.6,
      contentPadding: contentPadding,
      startIndex: currentIndex < 0 ? 0 : currentIndex,
      itemBuilder: (
        context,
        index,
      ) {
        final season = items[index];
        return SeasonPoster(
          season: season,
          isCurrentSeason: currentSeason != null && season.season == currentSeason,
          onTap: onSeasonTap != null ? () => onSeasonTap!(season) : null,
        );
      },
    );
  }
}

class SeasonPoster extends ConsumerWidget {
  final SeasonModel season;
  final bool isCurrentSeason;

  /// Given, replaces opening the season's own page.
  final VoidCallback? onTap;

  const SeasonPoster({
    required this.season,
    this.isCurrentSeason = false,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myKey = key ?? UniqueKey();
    Padding placeHolder(String title) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          child: Card(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.65),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Hero(
              tag: myKey,
              child: FocusButton(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: FladderTheme.smallShape.borderRadius,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                  ),
                  foregroundDecoration: isCurrentSeason
                      ? FladderTheme.currentItemDecoration(context)
                      : FladderTheme.defaultPosterDecoration,
                  child: FladderImage(
                    image: season.getPosters?.primary ??
                        season.parentImages?.backDrop?.firstOrNull ??
                        season.parentImages?.primary,
                    placeHolder: placeHolder(season.name),
                  ),
                ),
                onSecondaryTapDown: (details) async {
                  Offset localPosition = details.globalPosition;
                  RelativeRect position =
                      RelativeRect.fromLTRB(localPosition.dx, localPosition.dy, localPosition.dx, localPosition.dy);
                  await showMenu(
                      context: context,
                      position: position,
                      items: season.generateActions(context, ref).popupMenuItems(useIcons: true));
                },
                onTap: onTap ??
                    () async {
                      await season.navigateTo(context, ref: ref, tag: myKey);
                      if (!context.mounted) return;
                      context.refreshData();
                    },
                onLongPress: AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch
                    ? () {
                        showBottomSheetPill(
                          context: context,
                          content: (context, scrollController) => ListView(
                            shrinkWrap: true,
                            controller: scrollController,
                            children: season.generateActions(context, ref).listTileItems(context, useIcons: true),
                          ),
                        );
                      }
                    : null,
                overlays: [
                  if (season.images?.primary == null)
                    Align(
                      alignment: Alignment.topLeft,
                      child: placeHolder(season.name),
                    ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ref.watch(syncedItemProvider(season)).when(
                              error: (error, stackTrace) => const SizedBox.shrink(),
                              data: (syncedItem) {
                                if (syncedItem == null) {
                                  return const SizedBox.shrink();
                                }
                                return StatusCard(
                                  child: SyncButton(item: season, syncedItem: syncedItem),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                            ),
                        if (season.userData.unPlayedItemCount != 0)
                          StatusCard(
                            color: Theme.of(context).colorScheme.primary,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                season.userData.unPlayedItemCount.toString(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  overflow: TextOverflow.visible,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                        else
                          Align(
                            alignment: Alignment.topRight,
                            child: StatusCard(
                              color: Theme.of(context).colorScheme.primary,
                              child: const Icon(
                                Icons.check_rounded,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                focusedOverlays: [
                  if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer)
                    ExcludeFocus(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: PopupMenuButton(
                          tooltip: context.localized.options,
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          itemBuilder: (context) => season.generateActions(context, ref).popupMenuItems(useIcons: true),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          ClickableText(
            text: season.localizedName(context.localized),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

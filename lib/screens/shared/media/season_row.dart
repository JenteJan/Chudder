import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/providers/sync/sync_provider_helpers.dart';
import 'package:chudder/screens/details_screens/components/item_toggle_buttons.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/screens/syncing/sync_button.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/widgets/shared/clickable_text.dart';
import 'package:chudder/widgets/shared/focus_hero.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';
import 'package:chudder/widgets/shared/horizontal_list.dart';
import 'package:chudder/widgets/shared/status_card.dart';

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

    // Measured like every other row of portraits on the page, so seasons stand
    // as wide as the related films under them and their posters are whole.
    final metrics = posterCardMetrics(context, ref, artRatio: 2 / 3, maxLines: 1);

    return HorizontalList(
      label: context.localized.season(items.length),
      items: items,
      height: metrics.height,
      dominantRatio: metrics.ratio,
      contentPadding: contentPadding,
      startIndex: currentIndex < 0 ? 0 : currentIndex,
      itemBuilder: (
        context,
        index,
      ) {
        final season = items[index];
        return SeasonPoster(
          season: season,
          aspectRatio: metrics.ratio,
          isCurrentSeason: currentSeason != null && season.season == currentSeason,
          onTap: onSeasonTap != null ? () => onSeasonTap!(season) : null,
        );
      },
    );
  }
}

class SeasonPoster extends ConsumerStatefulWidget {
  final SeasonModel season;
  final bool isCurrentSeason;

  /// The shape of the whole card. The poster inside keeps its own 2:3.
  final double aspectRatio;

  /// Given, replaces opening the season's own page.
  final VoidCallback? onTap;

  const SeasonPoster({
    required this.season,
    this.isCurrentSeason = false,
    this.aspectRatio = 0.6,
    this.onTap,
    super.key,
  });

  @override
  ConsumerState<SeasonPoster> createState() => _SeasonPosterState();
}

class _SeasonPosterState extends ConsumerState<SeasonPoster> {
  final ValueNotifier<bool> _highlight = ValueNotifier(false);
  bool _hovered = false;
  bool _focused = false;

  SeasonModel get season => widget.season;
  bool get isCurrentSeason => widget.isCurrentSeason;
  VoidCallback? get onTap => widget.onTap;

  void _updateHighlight() => _highlight.value = _hovered || _focused;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myKey = widget.key ?? UniqueKey();
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

    return FocusScale(
      highlight: _highlight,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  // The button keeps its focus node through the flight, see
                  // [FocusHero].
                  child: FocusHero(
                    tag: myKey,
                    child: FocusButton(
                      onHover: (hovering) {
                        _hovered = hovering;
                        _updateHighlight();
                      },
                      onFocusChanged: (focused) {
                        _focused = focused;
                        _updateHighlight();
                      },
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
                        await showItemActionsSheet(context, ref, season, actions: season.generateActions(context, ref));
                      },
                      onTap: onTap ??
                          () async {
                            await season.navigateTo(context, ref: ref, tag: myKey);
                            if (!context.mounted) return;
                            context.refreshData();
                          },
                      onLongPress: AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch
                          ? () {
                              showItemActionsSheet(context, ref, season, actions: season.generateActions(context, ref));
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
                              child: IconButton(
                                tooltip: context.localized.options,
                                icon: const Icon(Icons.more_vert, color: Colors.white),
                                onPressed: () => showItemActionsSheet(
                                  context,
                                  ref,
                                  season,
                                  actions: season.generateActions(context, ref),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            ClickableText(
              text: season.localizedName(context.localized),
              maxLines: 1,
              highlight: _highlight,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

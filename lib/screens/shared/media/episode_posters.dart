import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/sync/sync_provider_helpers.dart';
import 'package:fladder/screens/syncing/sync_button.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/enum_selection.dart';
import 'package:fladder/widgets/shared/focus_row.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/status_card.dart';

/// The names to put on a season picker, by season number: the season's own
/// name when the show gave us one, and a numbered fallback when it did not.
Map<int, String> seasonNamesFor(
  BuildContext context,
  List<EpisodeModel> episodes,
  List<SeasonModel> seasons, {
  /// The grouping, when the caller has it already; grouping a long show is
  /// a sort of every episode, and this used to do it again for the names.
  Map<int, List<EpisodeModel>>? bySeason,
}) {
  return {
    for (final entry in (bySeason ?? episodes.episodesBySeason).entries)
      entry.key: seasons.firstWhereOrNull((element) => element.season == entry.key)?.name ??
          "${context.localized.season(1)} ${entry.key}"
  };
}

/// The season dropdown, on its own so the episode row and the episode
/// grid/list can put the same control in their title.
class SeasonSelectionBox extends StatelessWidget {
  final List<EpisodeModel> episodes;
  final List<SeasonModel> seasons;
  final int? selectedSeason;
  final ValueChanged<int?> onSeasonChanged;
  const SeasonSelectionBox({
    required this.episodes,
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bySeason = episodes.episodesBySeason;
    final names = seasonNamesFor(context, episodes, seasons, bySeason: bySeason);
    return EnumBox(
      current: selectedSeason != null
          ? names[selectedSeason!] ?? "${context.localized.season(1)} ${selectedSeason!}"
          : context.localized.all,
      itemBuilder: (context) => [
        ItemActionButton(
          label: Text(context.localized.all),
          action: () => onSeasonChanged(null),
        ),
        ...bySeason.keys.map(
          (season) => ItemActionButton(
            label: Text(names[season] ?? "${context.localized.season(1)} $season"),
            action: () => onSeasonChanged(season),
          ),
        )
      ],
    );
  }
}

class EpisodePosters extends ConsumerStatefulWidget {
  final List<EpisodeModel> episodes;
  final List<SeasonModel> seasons;
  final String? label;
  final VerticalDirection? titleActionsPosition;
  final ValueChanged<EpisodeModel> playEpisode;
  final EdgeInsets contentPadding;
  final EpisodeModel? selectedEpisode;
  final Function(VoidCallback action, EpisodeModel episodeModel)? onEpisodeTap;
  final Function(EpisodeModel selected)? onFocused;

  /// Which season the row is narrowed to, null being all of them. Only read
  /// when [onSeasonChanged] is given; without one the row keeps its own.
  final int? selectedSeason;

  /// Given, the season picker reports upwards instead of filtering on its own,
  /// so a page can keep a season row and this row saying the same thing.
  final ValueChanged<int?>? onSeasonChanged;

  /// Put in the title ahead of the season picker.
  final List<Widget> leadingTitleActions;

  /// Put at the far end of the title, away from the name.
  final List<Widget> trailingTitleActions;

  const EpisodePosters({
    this.label,
    this.titleActionsPosition = VerticalDirection.up,
    required this.contentPadding,
    required this.playEpisode,
    required this.episodes,
    this.seasons = const [],
    this.onEpisodeTap,
    this.selectedEpisode,
    this.onFocused,
    this.selectedSeason,
    this.onSeasonChanged,
    this.leadingTitleActions = const [],
    this.trailingTitleActions = const [],
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EpisodePosterState();
}

class _EpisodePosterState extends ConsumerState<EpisodePosters> {
  // The season of whatever you are looking at, falling back to next-up for
  // the screens that don't have a selected episode.
  late int? _ownSeason = widget.selectedSeason ?? widget.selectedEpisode?.season ?? widget.episodes.nextUp?.season;

  bool get _controlled => widget.onSeasonChanged != null;

  int? get selectedSeason => _controlled ? widget.selectedSeason : _ownSeason;

  void _setSeason(int? season) {
    if (_controlled) {
      widget.onSeasonChanged!(season);
    } else {
      setState(() => _ownSeason = season);
    }
  }

  final FocusNode seasonFocusNode = FocusNode();

  /// One hero tag per episode for the life of this row. A tag made in the
  /// item builder was a new one on every rebuild, so a poster that rebuilt
  /// between the tap and the page opening had a different tag by then and
  /// no flight began.
  final Map<String, UniqueKey> _heroTags = {};

  // The season's episodes and the grouping by season, each kept until the
  // list or the selection changes. Both are read several times per build,
  // and each read used to walk - and for the grouping, sort - every episode
  // of the show again.
  List<EpisodeModel>? _episodesSource;
  int? _episodesSeason;
  List<EpisodeModel>? _episodes;
  Map<int, List<EpisodeModel>>? _bySeason;

  List<EpisodeModel> get episodes {
    if (_episodes != null && identical(_episodesSource, widget.episodes) && _episodesSeason == selectedSeason) {
      return _episodes!;
    }
    _episodesSource = widget.episodes;
    _episodesSeason = selectedSeason;
    return _episodes = selectedSeason == null
        ? widget.episodes
        : widget.episodes.where((element) => element.season == selectedSeason).toList();
  }

  Map<int, List<EpisodeModel>> get episodesBySeason {
    if (_bySeason != null && identical(_episodesSource, widget.episodes)) return _bySeason!;
    // Reading [episodes] first keeps both caches keyed on the same list.
    episodes;
    return _bySeason = widget.episodes.episodesBySeason;
  }

  @override
  void dispose() {
    seasonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = this.episodes;
    final episodesBySeason = this.episodesBySeason;
    // Where the row parks itself: on the episode being looked at when there is
    // one, so selecting a season brings that season's place into view, and on
    // next-up otherwise.
    final selectedIndex = widget.selectedEpisode == null
        ? -1
        : episodes.indexWhere((episode) => episode.id == widget.selectedEpisode!.id);
    final indexOfCurrent = selectedIndex >= 0
        ? selectedIndex
        : (episodes.nextUp != null ? episodes.indexOf(episodes.nextUp!) : 0).clamp(0, episodes.length);
    final allPlayed = episodes.allPlayed;

    final isDPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    final constructSeasonNames = seasonNamesFor(context, widget.episodes, widget.seasons, bySeason: episodesBySeason);

    final hasSeasons = episodesBySeason.isNotEmpty && episodesBySeason.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        HorizontalList(
          label: widget.label,
          titleActionsPosition: widget.titleActionsPosition,
          onFocused: (index) {
            widget.onFocused?.call(episodes[index]);
          },
          onFocusChange: (value) {
            if (value) {
              context.ensureVisible();
            }
          },
          titleActions: [
            if (widget.leadingTitleActions.isNotEmpty) ...[
              const SizedBox(width: 16),
              ...widget.leadingTitleActions,
            ],
            if (!isDPad && hasSeasons) ...{
              const SizedBox(width: 16),
              SeasonSelectionBox(
                episodes: widget.episodes,
                seasons: widget.seasons,
                selectedSeason: selectedSeason,
                onSeasonChanged: _setSeason,
              )
            }
          ],
          trailingTitleActions: widget.trailingTitleActions,
          contentPadding: widget.contentPadding,
          startIndex: indexOfCurrent,
          items: episodes,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            final tag = _heroTags.putIfAbsent(episode.id, UniqueKey.new);
            return EpisodePoster(
              episode: episode,
              heroTag: tag,
              blur: allPlayed ? false : indexOfCurrent < index,
              onTap: widget.onEpisodeTap != null
                  ? () {
                      widget.onEpisodeTap?.call(
                        () {
                          episode.navigateTo(context, tag: tag);
                        },
                        episode,
                      );
                    }
                  : () {
                      episode.navigateTo(context, tag: tag);
                    },
              onLongPress: () async {
                await showBottomSheetPill(
                  context: context,
                  item: episode,
                  content: (context, scrollController) {
                    return ListView(
                      shrinkWrap: true,
                      controller: scrollController,
                      children: episode.generateActions(context, ref).listTileItems(context, useIcons: true).toList(),
                    );
                  },
                );
                context.refreshData();
              },
              actions: episode.generateActions(context, ref),
              isCurrentEpisode: widget.selectedEpisode?.id == episode.id,
            );
          },
        ),
        if (isDPad && hasSeasons)
          FocusRow(
            focusNode: seasonFocusNode,
            child: Container(
              padding: widget.contentPadding,
              height: 40,
              child: Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Builder(builder: (context) {
                        return Row(
                          children: [
                            ItemActionButton(
                              selected: selectedSeason == null,
                              label: Text(context.localized.all),
                              action: () => _setSeason(null),
                            ),
                            ...episodesBySeason.entries.map(
                              (e) => ItemActionButton(
                                selected: selectedSeason == e.key,
                                label: Text(constructSeasonNames[e.key] ?? "${context.localized.season(1)} ${e.key}"),
                                action: () => _setSeason(e.key),
                              ),
                            ),
                          ]
                              .groupButtons(
                                context,
                                useIcons: true,
                                shouldPop: false,
                              )
                              .addInBetween(
                                const SizedBox(width: 12),
                              ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class EpisodePoster extends ConsumerWidget {
  final EpisodeModel episode;
  final bool showLabel;
  final Function()? onTap;
  final Function()? onLongPress;
  final bool blur;
  final List<ItemAction> actions;
  final Function(bool value)? onFocusChanged;
  final bool isCurrentEpisode;
  final Object? heroTag;

  const EpisodePoster({
    super.key,
    required this.episode,
    this.showLabel = true,
    this.onTap,
    this.onLongPress,
    this.blur = false,
    required this.actions,
    this.onFocusChanged,
    this.isCurrentEpisode = false,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget placeHolder = Container(
      height: double.infinity,
      child: const Icon(Icons.local_movies_outlined),
    );
    bool episodeAvailable = episode.status == EpisodeStatus.available;
    final syncedDetails = ref.watch(syncedItemProvider(episode));
    return AspectRatio(
      aspectRatio: 1.76,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: FocusButton(
              onTap: onTap,
              onLongPress: onLongPress,
              onFocusChanged: onFocusChanged,
              onSecondaryTapDown: (details) async {
                Offset localPosition = details.globalPosition;
                RelativeRect position =
                    RelativeRect.fromLTRB(localPosition.dx, localPosition.dy, localPosition.dx, localPosition.dy);
                await showMenu(context: context, position: position, items: actions.popupMenuItems(useIcons: true));
              },
              child: Hero(
                tag: heroTag ?? UniqueKey(),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: FladderTheme.smallShape.borderRadius,
                    color: Theme.of(context).colorScheme.surfaceContainer,
                  ),
                  foregroundDecoration: isCurrentEpisode ? FladderTheme.currentItemDecoration(context) : null,
                  child: FladderImage(
                    image: !episodeAvailable ? episode.parentImages?.primary : episode.images?.primary,
                    placeHolder: placeHolder,
                    blurOnly: !episodeAvailable
                        ? true
                        : ref.watch(clientSettingsProvider.select((value) => value.blurUpcomingEpisodes))
                            ? blur
                            : false,
                  ),
                ),
              ),
              overlays: [
                if (!episodeAvailable)
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Card(
                        color: episode.status.color,
                        elevation: 3,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            episode.status.label(context.localized, episode.dateAired),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.topRight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      switch (syncedDetails) {
                        AsyncValue<SyncedItem?>(:final value) => Builder(
                            builder: (context) {
                              if (value == null) {
                                return const SizedBox.shrink();
                              }
                              return StatusCard(
                                child: SyncButton(item: episode, syncedItem: value),
                              );
                            },
                          ),
                      },
                      if (episode.userData.isFavourite)
                        const StatusCard(
                          color: Colors.red,
                          child: Icon(
                            Icons.favorite_rounded,
                          ),
                        ),
                      if (episode.userData.played)
                        StatusCard(
                          color: Theme.of(context).colorScheme.primary,
                          child: const Icon(
                            Icons.check_rounded,
                          ),
                        ),
                    ],
                  ),
                ),
                if ((episode.userData.progress) > 0)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: Colors.black.withValues(alpha: 0.75),
                      value: episode.userData.progress / 100,
                    ),
                  ),
              ],
              focusedOverlays: [
                if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer && actions.isNotEmpty)
                  ExcludeFocus(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: PopupMenuButton(
                        tooltip: context.localized.options,
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white,
                        ),
                        itemBuilder: (context) => actions.popupMenuItems(useIcons: true),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (showLabel) ...{
            const SizedBox(height: 4),
            Text(
              episode.episodeLabel(context.localized),
              maxLines: 1,
            ),
          }
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/items/collection_details_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/collections/collection_add_titles.dart';
import 'package:chudder/screens/details_screens/components/item_toggle_buttons.dart';
import 'package:chudder/screens/details_screens/components/media_stream_information.dart';
import 'package:chudder/screens/details_screens/components/overview_header.dart';
import 'package:chudder/screens/shared/detail_scaffold.dart';
import 'package:chudder/screens/video_player/components/remember_languages_prompt.dart';
import 'package:chudder/screens/shared/media/components/media_play_button.dart';
import 'package:chudder/screens/shared/media/expanding_text.dart';
import 'package:chudder/screens/shared/media/people_row.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:chudder/screens/shared/media/poster_grid.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/item_base_model/play_item_helpers.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/router_extension.dart';
import 'package:chudder/util/widget_extensions.dart';
import 'package:chudder/widgets/shared/subtle_icon_button.dart';

/// A collection as a real detail page — banner artwork, overview, a play
/// button for the next unwatched entry, and the contents in release order —
/// instead of the bare search grid it used to open.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const CollectionDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  StateNotifierProvider<CollectionDetailsNotifier, CollectionDetails> get providerInstance =>
      collectionDetailsProvider(widget.item.id);

  LanguageScope _scope(CollectionDetails details) {
    final collection = details.collection ?? widget.item;
    return LanguageScope(id: collection.id, name: collection.name, kind: LanguageScopeKind.collection);
  }

  void _chooseStreams(BuildContext context, CollectionDetails details, MediaStreamsModel changed) {
    final before = languagesOf(details.nextFull?.streamModel);
    ref.read(providerInstance.notifier).chooseStreams(changed);
    final after = languagesOf(changed);
    if (after == null || after == before) return;
    askToRememberLanguages(context, ProviderScope.containerOf(context, listen: false), _scope(details), after);
  }

  void _refetch() => ref.read(providerInstance.notifier).fetch(widget.item);

  /// The collection from [CollectionDetails.nextToWatch] on, in order. A show
  /// as the next thing to watch plays its own next episode, as its page would.
  Future<void> _playInOrder(
    BuildContext context,
    CollectionDetails details, {
    bool restart = false,
    bool askHow = false,
  }) async {
    final next = details.nextToWatch;
    if (next == null) return;
    // The entry in full, with the tracks picked for it here, goes first.
    final full = details.nextFull;
    final playable = details.children
        .where((child) => child.playAble)
        .map((child) => full != null && child.id == full.id ? full : child)
        .toList();
    final from = playable.indexWhere((child) => child.id == next.id);
    if (next.type == FladderItemType.series || from < 0) {
      await next.play(context, ref, startPosition: restart ? Duration.zero : null, showPlaybackOption: askHow);
    } else {
      await playable.sublist(from).playLibraryItems(
            context,
            ref,
            startPosition: restart ? Duration.zero : null,
            showPlaybackOptions: askHow,
            origin: _scope(details),
          );
    }
    _refetch();
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerInstance);
    final collection = details.collection ?? widget.item;
    final images = details.effectiveImages ?? collection.images;
    final nextToWatch = details.nextToWatch;
    final wrapAlignment =
        AdaptiveLayout.viewSizeOf(context) != ViewSize.phone ? WrapAlignment.start : WrapAlignment.center;

    return DetailScaffold(
      label: collection.name,
      item: details.collection,
      actions: (context) => details.collection?.generateActions(
        context,
        ref,
        exclude: {
          ItemActions.play,
          ItemActions.playFromStart,
          ItemActions.details,
        },
        onDeleteSuccesFully: (item) {
          if (context.mounted) {
            context.router.popBack();
          }
        },
      ),
      onRefresh: () async => await ref.read(providerInstance.notifier).fetch(widget.item),
      backDrops: images,
      content: (detailsContext, padding) => Padding(
        padding: const EdgeInsets.only(bottom: 64),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OverviewHeader(
              name: collection.name,
              image: images,
              padding: padding,
              // From the first thing not yet watched, with the rest of the
              // collection after it in order - a collection plays on the way
              // a show does, instead of stopping after one film.
              mainButton: nextToWatch != null
                  ? MediaPlayButton(
                      item: nextToWatch,
                      onPressed: (restart) => _playInOrder(detailsContext, details, restart: restart),
                      onLongPressed: (restart) =>
                          _playInOrder(detailsContext, details, restart: restart, askHow: true),
                    )
                  : null,
              // The audio and subtitles of the film the play button starts,
              // the way a film's own page offers them; a change is offered
              // to be remembered for the whole collection.
              mediaStreamHelper: details.nextFull?.streamModel?.audioStreams.isNotEmpty == true
                  ? MediaStreamHelper(
                      mediaStream: details.nextFull!.streamModel!,
                      onItemChanged: (changed) => _chooseStreams(detailsContext, details, changed),
                    )
                  : null,
              centerButtons: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: wrapAlignment,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Everything in it mixed, a show's episodes among the
                  // films - as a show's own page offers for its episodes.
                  SubtleIconButton(
                    tooltip: detailsContext.localized.collectionShuffle,
                    icon: IconsaxPlusLinear.shuffle,
                    onTap: details.children.where((child) => child.playAble).length < 2
                        ? null
                        : () async {
                            await details.children
                                .where((child) => child.playAble)
                                .toList()
                                .playLibraryItems(detailsContext, ref, shuffle: true, origin: _scope(details));
                            _refetch();
                          },
                  ),
                  if (canManageCollections(ref) && details.collection != null)
                    SubtleIconButton(
                      tooltip: detailsContext.localized.collectionAddTitles,
                      icon: IconsaxPlusLinear.add_square,
                      onTap: () async {
                        final changed = await showAddTitlesToCollection(
                          detailsContext,
                          collection: collection,
                          members: details.children,
                        );
                        if (changed) _refetch();
                      },
                    ),
                ],
              ),
              menuButton: SubtleIconButton(
                tooltip: detailsContext.localized.moreOptions,
                icon: IconsaxPlusLinear.more,
                onTap: () => showItemActionsSheet(
                  detailsContext,
                  ref,
                  collection,
                  actions: collection.generateActions(detailsContext, ref),
                  onUserDataChanged: (_) => _refetch(),
                ),
              ),
              subTitle: [
                context.localized.mediaTypeBoxset(1),
                if (details.children.isNotEmpty) "${details.watchedCount}/${details.children.length}",
              ].join(" · "),
              productionYear: details.yearSpan,
              runTime: details.totalRunTime > Duration.zero ? details.totalRunTime : null,
              genres: collection.overview.genreItems,
              onGenreClicked: (genre) {
                LibrarySearchRoute(
                  genres: {genre.name: true},
                  types: const {FladderItemType.movie: true, FladderItemType.series: true},
                ).push(context);
              },
              officialRating: collection.overview.parentalRating,
              communityRating: collection.overview.communityRating,
            ),
            if (collection.overview.summary.isNotEmpty)
              ExpandingText(
                text: collection.overview.summary,
              ).padding(padding),
            // The contents, grouped by what they are — a collection is
            // usually all movies, but nothing stops a mixed one.
            ...details.children.groupedItems.entries.map(
              (group) => Padding(
                padding: padding,
                child: PosterGrid(
                  name: group.key.label(context.localized, count: group.value.length),
                  posters: group.value,
                ),
              ),
            ),
            // Cast below the contents — the movies are what you came for.
            if (details.recurringCast.isNotEmpty)
              PeopleRow(
                people: details.recurringCast,
                contentPadding: padding,
              ),
            if (details.related.isNotEmpty)
              PosterRow(
                posters: details.related,
                contentPadding: padding,
                label: detailsContext.localized.related,
              ),
            // Last, as everywhere else: things to request, not press play on.
            if (details.seerrRecommended.isNotEmpty)
              SeerrPosterRow(
                posters: details.seerrRecommended,
                label: "${detailsContext.localized.discover} ${detailsContext.localized.recommended.toLowerCase()}",
                contentPadding: padding,
              ),
            if (!details.loading && details.children.isEmpty)
              Padding(
                padding: padding.copyWith(top: 32, bottom: 32),
                child: Text(
                  context.localized.noItemsToShow,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
          ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/collection_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/media/poster_grid.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/util/widget_extensions.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';

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
  AutoDisposeStateNotifierProvider<CollectionDetailsNotifier, CollectionDetails> get providerInstance =>
      collectionDetailsProvider(widget.item.id);

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
              // Play the first thing not yet watched — a collection's
              // equivalent of a show's next episode.
              mainButton: nextToWatch != null
                  ? MediaPlayButton(
                      item: nextToWatch,
                      onPressed: (restart) async {
                        await nextToWatch.play(
                          detailsContext,
                          ref,
                          startPosition: restart ? Duration.zero : null,
                        );
                        ref.read(providerInstance.notifier).fetch(widget.item);
                      },
                      onLongPressed: (restart) async {
                        await nextToWatch.play(
                          detailsContext,
                          ref,
                          showPlaybackOption: true,
                          startPosition: restart ? Duration.zero : null,
                        );
                        ref.read(providerInstance.notifier).fetch(widget.item);
                      },
                    )
                  : null,
              centerButtons: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: wrapAlignment,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableIconButton(
                    onPressed: () async {
                      await ref
                          .read(userProvider.notifier)
                          .setAsFavorite(!collection.userData.isFavourite, collection.id);
                      ref.read(providerInstance.notifier).fetch(widget.item);
                    },
                    selected: collection.userData.isFavourite,
                    selectedIcon: IconsaxPlusBold.heart,
                    icon: IconsaxPlusLinear.heart,
                  ),
                  SelectableIconButton(
                    onPressed: () async {
                      await ref.read(userProvider.notifier).markAsPlayed(!collection.userData.played, collection.id);
                      ref.read(providerInstance.notifier).fetch(widget.item);
                    },
                    selected: collection.userData.played,
                    selectedIcon: IconsaxPlusBold.tick_circle,
                    icon: IconsaxPlusLinear.tick_circle,
                  ),
                  SelectableIconButton(
                    refreshOnEnd: false,
                    onPressed: () async {
                      await showBottomSheetPill(
                        context: detailsContext,
                        content: (context, scrollController) => ListView(
                          controller: scrollController,
                          shrinkWrap: true,
                          children:
                              collection.generateActions(detailsContext, ref).listTileItems(context, useIcons: true),
                        ),
                      );
                    },
                    selected: false,
                    icon: IconsaxPlusLinear.more,
                  ),
                ],
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
                // The ratio the season and cast rows use, so every row of
                // portraits on the page stands the same size.
                collectionAspectRatio: 0.6,
                label: detailsContext.localized.related,
              ),
            // Last, as everywhere else: things to request, not press play on.
            if (details.seerrRecommended.isNotEmpty)
              SeerrPosterRow(
                posters: details.seerrRecommended,
                label:
                    "${detailsContext.localized.discover} ${detailsContext.localized.recommended.toLowerCase()}",
                contentPadding: padding,
                aspectRatio: 0.6,
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

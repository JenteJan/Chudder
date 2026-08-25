import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/movies_details_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/screens/details_screens/components/detail_poster.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/chapter_row.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/media/special_features_row.dart';
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

class MovieDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const MovieDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends ConsumerState<MovieDetailScreen> {
  MovieDetailsProvider get providerInstance => movieDetailsProvider(widget.item.id);

  /// Whether the film is still on its way, so the header can hold the space its
  /// genres will need. They are not on the poster that opened the page — only
  /// the film's own request has them — and arriving into a row that is not
  /// there yet is what pushes the page down.
  bool loading = true;

  /// The fetch currently in flight — see the show page; the same two callers
  /// would otherwise make the same request twice.
  Future<void>? _inFlight;

  Future<void> _fetch() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = ref.read(providerInstance.notifier).fetchDetails(widget.item).then<void>((_) {}).whenComplete(() {
      _inFlight = null;
      if (mounted) setState(() => loading = false);
    });

    _inFlight = future;
    return future;
  }

  Future<void> _refresh() {
    if (_inFlight == null && !loading && mounted) setState(() => loading = true);
    return _fetch();
  }

  @override
  void initState() {
    super.initState();
    // Opened from a poster we already have everything the header needs, so
    // there is no reason for the page to start empty - and a reason for it not
    // to: the poster that was tapped is flying towards the one in that header,
    // and a hero looks for its far end on the first frame.
    final item = widget.item;
    if (item is MovieModel) {
      ref.read(providerInstance.notifier).seed(item);
    }
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerInstance);
    final wrapAlignment =
        AdaptiveLayout.viewSizeOf(context) != ViewSize.phone ? WrapAlignment.start : WrapAlignment.center;

    return DetailScaffold(
      label: widget.item.name,
      item: details,
      actions: (context) => details?.generateActions(
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
      onRefresh: _refresh,
      backDrops: details?.images,
      content: (detailsContext, padding) => details != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OverviewHeader(
                    name: details.name,
                    image: details.images,
                    poster: DetailPoster.fitsBeside(context) ? DetailPoster(item: details) : null,
                    padding: padding,
                    mainButton: MediaPlayButton(
                      item: details,
                      onLongPressed: (restart) async {
                        await details.play(
                          detailsContext,
                          ref,
                          showPlaybackOption: true,
                          startPosition: restart ? Duration.zero : null,
                        );
                        ref.read(providerInstance.notifier).fetchDetails(widget.item);
                      },
                      onPressed: (restart) async {
                        await details.play(
                          detailsContext,
                          ref,
                          startPosition: restart ? Duration.zero : null,
                        );
                        ref.read(providerInstance.notifier).fetchDetails(widget.item);
                      },
                    ),
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
                                .setAsFavorite(!details.userData.isFavourite, details.id);
                          },
                          selected: details.userData.isFavourite,
                          selectedIcon: IconsaxPlusBold.heart,
                          icon: IconsaxPlusLinear.heart,
                        ),
                        SelectableIconButton(
                          onPressed: () async {
                            await ref.read(userProvider.notifier).markAsPlayed(!details.userData.played, details.id);
                          },
                          selected: details.userData.played,
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
                                    details.generateActions(detailsContext, ref).listTileItems(context, useIcons: true),
                              ),
                            );
                          },
                          selected: false,
                          icon: IconsaxPlusLinear.more,
                        ),
                      ],
                    ),
                    originalTitle: details.originalTitle.isEmpty ? null : details.originalTitle,
                    productionYear: details.premiereDate.year.toString(),
                    runTime: details.overview.runTime,
                    reserveGenres: loading,
                    genres: details.overview.genreItems,
                    onGenreClicked: (genre) {
                      // Whole library, typed to movies/shows (see series screen).
                      LibrarySearchRoute(
                        genres: {genre.name: true},
                        types: const {FladderItemType.movie: true, FladderItemType.series: true},
                      ).push(context);
                    },
                    studios: details.overview.studios,
                    officialRating: details.overview.parentalRating,
                    communityRating: details.overview.communityRating,
                    mediaStreamHelper: details.mediaStreams.isNotEmpty
                        ? MediaStreamHelper(
                            mediaStream: details.mediaStreams,
                            onItemChanged: (changed) {
                              ref.read(providerInstance.notifier).setMediaStreamHelper(changed);
                            },
                          )
                        : null,
                  ),
                  if (details.overview.summary.isNotEmpty == true)
                    ExpandingText(
                      text: details.overview.summary,
                    ).padding(padding),
                  if (details.chapters.isNotEmpty)
                    ChapterRow(
                      chapters: details.chapters,
                      contentPadding: padding,
                      onPressed: (chapter) {
                        details.play(
                          detailsContext,
                          ref,
                          startPosition: chapter.startPosition,
                        );
                      },
                    ),
                  if (details.overview.people.isNotEmpty)
                    PeopleRow(
                      people: details.overview.people,
                      contentPadding: padding,
                    ),
                  if (details.specialFeatures.isNotEmpty)
                    SpecialFeaturesRow(
                        contentPadding: padding,
                        label: detailsContext.localized.specialFeature(details.specialFeatures.length),
                        specialFeatures: details.specialFeatures),
                  if (details.related.isNotEmpty)
                    PosterRow(
                      posters: details.related,
                      contentPadding: padding,
                      // The ratio the season and cast rows use, so every row of
                      // portraits on the page stands the same size.
                      collectionAspectRatio: 0.6,
                      label: detailsContext.localized.related,
                    ),
                  if (details.seerrRecommended.isNotEmpty)
                    SeerrPosterRow(
                      posters: details.seerrRecommended,
                      label:
                          "${detailsContext.localized.discover} ${detailsContext.localized.recommended.toLowerCase()}",
                      contentPadding: padding,
                      aspectRatio: 0.6,
                    ),
                  if (details.seerrRelated.isNotEmpty)
                    SeerrPosterRow(
                      posters: details.seerrRelated,
                      label: "${detailsContext.localized.discover} ${detailsContext.localized.related.toLowerCase()}",
                      contentPadding: padding,
                      aspectRatio: 0.6,
                    ),
                  if (details.overview.externalUrls?.isNotEmpty == true)
                    Padding(
                      padding: padding,
                      child: ExternalUrlsRow(
                        urls: details.overview.externalUrls,
                      ),
                    )
                ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
              ),
            )
          : Container(),
    );
  }
}

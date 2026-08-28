import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/items/series_details_provider.dart';
import 'package:fladder/providers/items/series_next_up_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/details_screens/components/detail_poster.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/chapter_row.dart';
import 'package:fladder/screens/shared/media/components/media_play_button.dart';
import 'package:fladder/screens/shared/media/episode_details_list.dart';
import 'package:fladder/screens/shared/media/episode_posters.dart';
import 'package:fladder/screens/shared/media/expanding_text.dart';
import 'package:fladder/screens/shared/media/external_urls.dart';
import 'package:fladder/screens/shared/media/people_row.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/screens/shared/media/season_row.dart';
import 'package:fladder/screens/shared/media/special_features_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/favourite_prompt.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/item_base_model/play_item_helpers.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/people_extension.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/shared/defer_until_settled.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/selectable_icon_button.dart';
import 'package:fladder/widgets/shared/shimmer.dart';
import 'package:fladder/widgets/shared/shimmer_poster_row.dart';

/// How long the swapping half of the header takes to cross over. Short enough
/// to read as instant, long enough that the page does not appear to jump.
const _swapDuration = Duration(milliseconds: 180);

/// The whole of a show on one page: the series, its seasons and every episode.
///
/// A season is a filter over the episode row and an episode is a selection
/// within it, so moving between them changes the information on screen without
/// touching the navigator or the network — everything is already in
/// [seriesDetailsProvider], which fetches the show in one pass.
///
/// It accepts a series, a season or an episode, because all three are things
/// the rest of the app links to; whichever arrives only decides what is
/// selected when the page opens.
class ShowDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const ShowDetailScreen({required this.item, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen> {
  /// The show this page is, whichever of its parts we were handed.
  late final String seriesId = switch (widget.item) {
    SeriesModel series => series.id,
    SeasonModel season => season.seriesId,
    EpisodeModel episode => episode.parentId ?? episode.id,
    final item => item.parentId ?? item.id,
  };

  /// Held by id rather than by model so a refresh — after playing something,
  /// say — hands the header the new progress instead of a stale copy.
  late String? selectedEpisodeId = switch (widget.item) {
    EpisodeModel episode => episode.id,
    _ => null,
  };

  /// null is every season at once, the way the episode row has always meant it.
  late int? selectedSeason = switch (widget.item) {
    EpisodeModel episode => episode.season,
    SeasonModel season => season.season,
    _ => null,
  };

  /// Whether "all seasons" is something that was asked for or only where we
  /// started. Until it is asked for, the row opens on the season next-up is in
  /// — which is the season the show is at, and what the series page has always
  /// shown — and next-up is not known until the show has been fetched.
  late bool seasonChosen = selectedSeason != null;

  EpisodeDetailsViewType episodeView = EpisodeDetailsViewType.row;

  /// Whether the show is still on its way. Drives the placeholders, which is
  /// the whole reason it is worth tracking: the rows have to hold their space
  /// before there is anything to put in them.
  bool loading = true;

  /// What was last chosen in the version, audio and subtitle pickers, and for
  /// which episode. Held here as well as in the provider because the header
  /// reads whichever copy of the episode is fullest at the time, and that copy
  /// changes underneath it as fetches land.
  MediaStreamsModel? _streamChoice;
  String? _streamChoiceFor;

  void _chooseStreams(EpisodeModel episode, MediaStreamsModel streams) {
    setState(() {
      _streamChoice = streams;
      _streamChoiceFor = episode.id;
    });
    ref.read(providerId.notifier).updateEpisodeInfo(episode.copyWith(mediaStreams: streams));
  }

  /// Whether the route has finished animating in.
  ///
  /// Filling in an episode replaces the episode list, and replacing the episode
  /// list rebuilds the whole page. Doing that halfway through a transition is
  /// the one moment it costs the most, for information — chapters, the guest
  /// cast — that cannot be seen until the transition is over anyway.
  bool _settled = false;
  Animation<double>? _routeAnimation;

  AutoDisposeStateNotifierProvider<SeriesDetailViewNotifier, SeriesModel?> get providerId =>
      seriesDetailsProvider(seriesId);

  /// What the page paints until the provider has something.
  ///
  /// Whatever we were handed already carries the show's name and artwork, so
  /// there is no reason for the page to start as placeholders — and a reason
  /// for it not to: the poster that was tapped is flying towards the one in
  /// the header, and a hero looks for its far end on the first frame. A page
  /// that starts as a skeleton has nothing there to be found.
  ///
  /// Kept here rather than pushed into the provider: writing a provider from
  /// initState is writing it while the tree is building, which Riverpod
  /// refuses. The provider is handed the same seed by [_fetch], which applies
  /// it once the build is over.
  ///
  /// Carries the next-up episode too when the poster was hovered on the way
  /// in — see [seriesNextUpProvider] — so the play button names an episode on
  /// the frame the page is built rather than a request later.
  late final SeriesModel? _seed = _buildSeed();

  SeriesModel? _buildSeed() {
    final cache = ref.read(seriesNextUpProvider);
    // The show from the cache before whatever handed us the page: an episode
    // knows the show's name and poster, the cache knows its genres and its
    // overview too, and the header is complete on the first frame either way.
    final show = cache.showOf(seriesId) ?? _seedShow();
    final prefetched = cache.of(seriesId);
    if (show == null || prefetched == null) return show;
    return show.copyWith(selectedEpisode: prefetched);
  }

  @override
  void initState() {
    super.initState();
    // Opened from a show's own poster, everything the header still needs is
    // behind this one call — the episode the play button names, the streams the
    // language pickers list. Waiting for the pull-to-refresh indicator to
    // trigger it costs a frame and the indicator's own start-up before the
    // request has even left, which is the whole of the difference between this
    // and a page opened from an episode, where nothing had to be asked at all.
    _fetch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted || animation.isDismissed) {
      _settled = true;
      return;
    }
    if (identical(animation, _routeAnimation)) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _settled || !mounted) return;
    setState(() => _settled = true);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  /// A stand-in for the show, built from whichever of its parts opened the page.
  ///
  /// Deliberately bare — a name, the artwork, and nothing claimed about the
  /// show that is not actually known. The real thing replaces it within about a
  /// tenth of a second; anything invented to fill the gap would be visible for
  /// exactly that long and then change under the reader.
  SeriesModel? _seedShow() {
    final item = widget.item;
    if (item is SeriesModel) return item;

    final (String name, ImagesData? images) = switch (item) {
      EpisodeModel episode => (episode.seriesName ?? "", episode.parentImages),
      SeasonModel season => (season.seriesName, season.parentImages),
      _ => ("", null),
    };
    if (images == null && name.isEmpty) return null;

    return SeriesModel(
      name: name,
      id: seriesId,
      overview: const OverviewModel(),
      parentId: null,
      playlistId: null,
      images: images,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      originalTitle: "",
      sortName: "",
      status: "",
    );
  }

  SeriesModel? get details => ref.read(providerId);

  /// The fetch currently in flight, so the two things that ask for one — this
  /// page opening, and the refresh indicator starting itself — join the same
  /// request instead of making two of it.
  Future<void>? _inFlight;

  Future<void> _fetch() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = ref
        .read(providerId.notifier)
        .fetchDetails(seriesId, seed: _seed)
        .then<void>((_) {})
        .whenComplete(() {
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

  /// Chapters and an episode's own cast are not in the show-wide fetch — see
  /// [SeriesDetailViewNotifier.ensureEpisodeDetails]. Asked for as soon as we
  /// know which episode the header is on, which includes next-up, so the
  /// common case has them before anyone picks anything.
  void _ensureEpisodeDetails(String? episodeId) {
    if (episodeId == null) return;
    // No guard here any more. The provider decides, on what the episode is
    // actually missing - a guard on this side once meant that an episode asked
    // about early, and then replaced by a thinner copy, was never asked about
    // again.
    Future.microtask(() {
      if (mounted) ref.read(providerId.notifier).ensureEpisodeDetails(episodeId);
    });
  }

  /// Selecting is what tapping an episode does now, so the same tap has to be
  /// able to undo itself — otherwise there is no way back to the show's own
  /// overview once you have picked something.
  void _selectEpisode(EpisodeModel? episode) {
    setState(() {
      // Deliberately leaves the season filter alone: narrowing the row you
      // just tapped in, out from under you, is not what the tap asked for.
      selectedEpisodeId = (episode == null || episode.id == selectedEpisodeId) ? null : episode.id;
      if (_streamChoiceFor != selectedEpisodeId) {
        _streamChoice = null;
        _streamChoiceFor = null;
      }
    });
  }

  /// A season used to be a page of its own; it is a filter now, and picking one
  /// lands on the episode you would have opened it for.
  void _selectSeason(int? season) {
    setState(() {
      selectedSeason = season;
      seasonChosen = true;
      if (season == null) {
        selectedEpisodeId = null;
        return;
      }
      final inSeason = details?.availableEpisodes?.where((episode) => episode.season == season).toList() ?? [];
      selectedEpisodeId = (inSeason.nextUp ?? inSeason.firstOrNull)?.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerId) ?? _seed;
    final wrapAlignment =
        AdaptiveLayout.viewSizeOf(context) != ViewSize.phone ? WrapAlignment.start : WrapAlignment.center;

    final allEpisodes = details?.availableEpisodes ?? const <EpisodeModel>[];

    // The episode we were handed is a complete one — whatever offered it, a
    // next-up card or a search result, fetched it with its streams and its
    // overview. The show's own fetch brings back a thinner copy of the same
    // episode, so where the two overlap the fuller one wins.
    //
    // Without this the page went backwards a moment after it opened: the
    // header appeared with the episode's title, rating and language buttons,
    // and then the list arrived and took them all away again until the
    // per-episode request had been and gone.
    final handedEpisode = widget.item is EpisodeModel ? widget.item as EpisodeModel : null;

    // Copies of the same episode that were fetched with their streams: the one
    // that opened the page, and the single early one the show page asks for
    // before the episode list. The list itself is fetched without streams, so
    // when it lands it is thinner than what the header is already showing —
    // and without this the language pickers went blank the moment it did.
    final richer = [handedEpisode, details?.selectedEpisode].nonNulls;

    EpisodeModel? fullest(EpisodeModel? episode) {
      if (episode == null || episode.mediaStreams.versionStreams.isNotEmpty) return episode;
      // Only ever fills in the same episode. Standing in for a different one
      // would put the wrong streams behind the right title.
      final fuller = richer.firstWhereOrNull(
        (candidate) => candidate.id == episode.id && candidate.mediaStreams.versionStreams.isNotEmpty,
      );
      if (fuller == null) return episode;
      return episode.copyWith(
        mediaStreams: fuller.mediaStreams,
        chapters: episode.chapters.isEmpty ? fuller.chapters : episode.chapters,
      );
    }

    // Found in the list once it is here, and taken from what opened the page
    // until then — so an episode page is an episode page from its first frame,
    // rather than a show page that turns into one.
    final selectedEpisode = selectedEpisodeId == null
        ? null
        : fullest(allEpisodes.firstWhereOrNull((episode) => episode.id == selectedEpisodeId)) ??
            (handedEpisode?.id == selectedEpisodeId ? handedEpisode : null);

    // The play button follows next-up until you pick something, exactly as the
    // series page always has; the rest of the header only leaves the series
    // behind once there is a selection to leave it for.
    // In order of authority: what you picked, what the episode list says is
    // next, the early stand-in fetched on its own for exactly this moment, and
    // finally whatever handed us the page.
    final baseHeaderEpisode = selectedEpisode ?? fullest(details?.nextUp) ?? details?.selectedEpisode ?? handedEpisode;

    // Whatever was last chosen in the pickers, laid over whichever copy of the
    // episode the header is reading. The provider is told as well, but the
    // header must not wait for that to come back around to it — nor lose the
    // choice when a fetch swaps the copy underneath.
    final headerEpisode = baseHeaderEpisode != null && _streamChoice != null && _streamChoiceFor == baseHeaderEpisode.id
        ? baseHeaderEpisode.copyWith(mediaStreams: _streamChoice!)
        : baseHeaderEpisode;
    final focused = selectedEpisode != null;

    _ensureEpisodeDetails(headerEpisode?.id);

    // What the play button acts on: the episode when there is one, the show
    // itself before the episode list has arrived. Null only on a bare link,
    // where there is nothing to show yet and the page is placeholders anyway.
    final ItemBaseModel? playTarget = headerEpisode ?? details;

    final activeSeason = seasonChosen ? selectedSeason : details?.nextUp?.season;
    final seasonEpisodes =
        activeSeason == null ? allEpisodes : allEpisodes.where((e) => e.season == activeSeason).toList();

    // What the top-right menu and the download button act on: the episode when
    // you are looking at one, the show otherwise.
    final actionItem = selectedEpisode ?? details;

    return DetailScaffold(
      label: details?.name ?? widget.item.name,
      windowTitle: (selectedEpisode ?? details)?.windowTitle(context.localized),
      // Falls back to whatever opened the page, so the artwork the flight from
      // the poster is heading for exists before the show has been fetched.
      item: actionItem ?? widget.item,
      actions: (context) => actionItem?.generateActions(
        context,
        ref,
        exclude: {
          ItemActions.play,
          ItemActions.playFromStart,
          ItemActions.details,
          // Both would land back on this page.
          ItemActions.openShow,
          ItemActions.openParent,
        },
        onDeleteSuccesFully: (item) {
          if (item.id == selectedEpisodeId) {
            _selectEpisode(null);
            _refresh();
          } else if (context.mounted) {
            context.router.popBack();
          }
        },
      ),
      onRefresh: _refresh,
      backDrops: details?.images,
      content: (detailsContext, padding) => details == null
          ? _ShowSkeleton(padding: padding)
          : Padding(
              padding: const EdgeInsets.only(bottom: 64),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OverviewHeader(
                    name: details.name,
                    image: details.images,
                    poster: DetailPoster.fitsBeside(context) ? DetailPoster(item: details) : null,
                    // The episode once we know which one, and the show itself
                    // until then — opened from a show's own poster there is no
                    // episode in hand and the list takes a moment, and a play
                    // button that turns up after the page has been read is a
                    // play button that was not there when it was wanted.
                    // Playing a show resolves to its next-up episode anyway, so
                    // the early button does the same thing as the late one; all
                    // that changes is what it calls itself.
                    mainButton: playTarget == null
                        ? null
                        : MediaPlayButton(
                            // Not keyed on the episode: when the stand-in
                            // gives way to the list's answer the button
                            // should change its label, not be torn down and
                            // faded back in.
                            item: playTarget,
                            // Never the page's opening focus: on a remote
                            // the artwork's copy takes that, and on a
                            // pointer nothing autofocuses at all.
                            autoFocus: OverviewHeader.showsArtworkButton(context) ? false : null,
                            onPressed: (restart) async {
                              await playTarget.play(
                                detailsContext,
                                ref,
                                startPosition: restart ? Duration.zero : null,
                              );
                              _refresh();
                            },
                            onLongPressed: (restart) async {
                              await playTarget.play(
                                detailsContext,
                                ref,
                                showPlaybackOption: true,
                                startPosition: restart ? Duration.zero : null,
                              );
                              _refresh();
                            },
                          ),
                    artworkButton: playTarget == null
                        ? null
                        : MediaPlayButton(
                            item: playTarget,
                            large: true,
                            showRestartOption: false,
                            onPressed: (restart) async {
                              await playTarget.play(
                                detailsContext,
                                ref,
                                startPosition: restart ? Duration.zero : null,
                              );
                              _refresh();
                            },
                            onLongPressed: (restart) async {
                              await playTarget.play(
                                detailsContext,
                                ref,
                                showPlaybackOption: true,
                                startPosition: restart ? Duration.zero : null,
                              );
                              _refresh();
                            },
                          ),
                    centerButtons: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: wrapAlignment,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SelectableIconButton(
                          onPressed: () async {
                            if (selectedEpisode != null) {
                              await setAsFavoriteWithPrompt(
                                  context, ref, selectedEpisode, !selectedEpisode.userData.isFavourite);
                            } else {
                              await ref
                                  .read(userProvider.notifier)
                                  .setAsFavorite(!details.userData.isFavourite, details.id);
                            }
                          },
                          selected: (selectedEpisode ?? details).userData.isFavourite,
                          selectedIcon: IconsaxPlusBold.heart,
                          icon: IconsaxPlusLinear.heart,
                        ),
                        SelectableIconButton(
                          onPressed: () async {
                            final target = selectedEpisode ?? details;
                            await ref.read(userProvider.notifier).markAsPlayed(!target.userData.played, target.id);
                          },
                          selected: (selectedEpisode ?? details).userData.played,
                          selectedIcon: IconsaxPlusBold.tick_circle,
                          icon: IconsaxPlusLinear.tick_circle,
                        ),
                        SelectableIconButton(
                          onPressed: () {
                            final target = selectedEpisode ?? details;
                            showBottomSheetPill(
                              context: detailsContext,
                              item: target,
                              content: (context, scrollController) => ListView(
                                controller: scrollController,
                                shrinkWrap: true,
                                children: target.generateActions(detailsContext, ref, exclude: {
                                  ItemActions.openParent,
                                  ItemActions.openShow,
                                  ItemActions.details,
                                }).listTileItems(context, useIcons: true),
                              ),
                            );
                          },
                          selected: false,
                          refreshOnEnd: false,
                          icon: IconsaxPlusLinear.more,
                        ),
                      ],
                    ),
                    padding: padding,
                    // Naming the episode is what tells you the page has moved;
                    // the show's own title stays put above it.
                    subTitle: selectedEpisode?.detailedName(detailsContext.localized),
                    onTitleClicked: focused ? () => _selectEpisode(null) : null,
                    originalTitle: details.originalTitle.isEmpty ? null : details.originalTitle,
                    productionYear: focused
                        ? (selectedEpisode.dateAired != null
                            ? DateFormat.yMMMEd(context.localized.localeName).format(selectedEpisode.dateAired!)
                            : null)
                        : details.overview.yearAired?.toString(),
                    runTime: focused ? selectedEpisode.overview.runTime : details.overview.runTime,
                    studios: details.overview.studios,
                    officialRating: focused ? selectedEpisode.overview.parentalRating : details.overview.parentalRating,
                    // Held open until the show has answered, since that is the
                    // only place its genres exist.
                    reserveGenres: loading,
                    // The show's, once it has told us. Until then whatever the
                    // episode carried, which is usually the same list.
                    genres: details.overview.genreItems.isNotEmpty
                        ? details.overview.genreItems
                        : (handedEpisode?.overview.genreItems ?? const []),
                    onGenreClicked: (genre) {
                      // Whole library, not just the source view — and typed to
                      // movies/shows so the recursive fetch doesn't drown the
                      // result in episodes.
                      LibrarySearchRoute(
                        genres: {genre.name: true},
                        types: const {FladderItemType.movie: true, FladderItemType.series: true},
                      ).push(context);
                    },
                    // Present from the first frame, whether or not there is an
                    // episode behind them yet. Opened from a show's own poster
                    // there is not one for a moment, and buttons that turn up
                    // afterwards are buttons that move the page — these sit
                    // directly above everything else on it.
                    mediaStreamHelper: MediaStreamHelper(
                      mediaStream: headerEpisode?.mediaStreams ?? MediaStreamsModel(versionStreams: const []),
                      onItemChanged: headerEpisode == null ? null : (changed) => _chooseStreams(headerEpisode, changed),
                    ),
                    communityRating:
                        focused ? selectedEpisode.overview.communityRating : details.overview.communityRating,
                  ),
                  // Everything below swaps with the selection, so it animates
                  // its own height rather than shunting the rows underneath.
                  AnimatedSize(
                    duration: _swapDuration,
                    alignment: Alignment.topLeft,
                    curve: Curves.easeOutCubic,
                    child: AnimatedSwitcher(
                      duration: _swapDuration,
                      // A switcher stacks its children centred unless told
                      // otherwise, which took the description off the left
                      // margin every other block on the page lines up with.
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        alignment: AlignmentDirectional.topStart,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      ),
                      child: Builder(
                        key: ValueKey(selectedEpisodeId ?? details.id),
                        builder: (context) {
                          final summary = focused ? selectedEpisode.overview.summary : details.overview.summary;
                          if (summary.isEmpty) return const SizedBox(width: double.infinity);
                          // Full width, so the text wraps against the margin
                          // rather than against its own longest line.
                          return SizedBox(
                            width: double.infinity,
                            child: Padding(
                              padding: padding,
                              child: ExpandingText(
                                text: summary,
                                onFocusChange: (onFocus) {
                                  if (onFocus) {
                                    context.ensureVisible(alignment: 1);
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (allEpisodes.isEmpty && loading)
                    ShimmerPosterRow(
                      label: detailsContext.localized.episode(2),
                      contentPadding: padding,
                      aspectRatio: 1.76,
                    )
                  else if (allEpisodes.isNotEmpty)
                    Builder(builder: (context) {
                      return _EpisodeSection(
                        padding: padding,
                        label: detailsContext.localized.episode(allEpisodes.length),
                        allEpisodes: allEpisodes,
                        seasonEpisodes: seasonEpisodes,
                        seasons: details.seasons ?? const [],
                        selectedEpisode: selectedEpisode ?? details.nextUp,
                        selectedSeason: activeSeason,
                        viewType: episodeView,
                        onViewTypeChanged: (value) => setState(() => episodeView = value),
                        onSeasonChanged: _selectSeason,
                        onEpisodeSelected: _selectEpisode,
                        onEpisodeFocused: (_) => context.ensureVisible(alignment: 0.8),
                        onPlayEpisode: (episode) async {
                          await episode.play(context, ref);
                          _refresh();
                        },
                      );
                    }),
                  // An episode's own chapters, so they arrive and leave with it.
                  // Below the fold, so it waits for the transition rather
                  // than competing with it. See [DeferUntilSettled].
                  DeferUntilSettled(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (focused)
                          ChapterRow(
                            key: ValueKey('chapters-${selectedEpisode.id}'),
                            chapters: selectedEpisode.chapters,
                            contentPadding: padding,
                            onPressed: (chapter) async {
                              await selectedEpisode.play(detailsContext, ref, startPosition: chapter.startPosition);
                              _refresh();
                            },
                          ),
                        if ((details.seasons?.isEmpty ?? true) && loading)
                          ShimmerPosterRow(
                            label: detailsContext.localized.season(2),
                            contentPadding: padding,
                            aspectRatio: 0.6,
                            dominantRatio: 0.6,
                          )
                        else if (details.seasons?.isNotEmpty ?? false)
                          SeasonsRow(
                            contentPadding: padding,
                            seasons: details.seasons,
                            currentSeason: activeSeason ?? headerEpisode?.season,
                            // A season no longer opens anything; it narrows the row
                            // above and takes the header to where you left off in it.
                            onSeasonTap: (season) => _selectSeason(season.season),
                          ),
                        // The guest cast of the episode you are on, ahead of the
                        // show's regulars — it is the part that just changed.
                        if (focused && selectedEpisode.overview.people.guestActors.isNotEmpty)
                          PeopleRow(
                            key: ValueKey('guests-${selectedEpisode.id}'),
                            people: selectedEpisode.overview.people.guestActors,
                            contentPadding: padding,
                          ),
                        if (details.overview.people.isNotEmpty)
                          PeopleRow(
                            people: details.overview.people,
                            contentPadding: padding,
                          ),
                        if (details.specialFeatures?.isNotEmpty ?? false)
                          SpecialFeaturesRow(
                              contentPadding: padding,
                              label: detailsContext.localized.specialFeature(details.specialFeatures?.length ?? 2),
                              specialFeatures: details.specialFeatures ?? []),
                        if (details.related.isNotEmpty)
                          PosterRow(
                            posters: details.related,
                            contentPadding: padding,
                            // The ratio the season and cast rows use, so every row of
                            // portraits on the page stands the same size.
                            collectionAspectRatio: 0.6,
                            label: detailsContext.localized.related,
                          ),
                        if (details.overview.externalUrls?.isNotEmpty == true)
                          Padding(
                            padding: padding,
                            child: ExternalUrlsRow(
                              urls: details.overview.externalUrls,
                            ),
                          ),
                        // Last: these are things to request elsewhere, not things in
                        // the library you can press play on.
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
                            label:
                                "${detailsContext.localized.discover} ${detailsContext.localized.related.toLowerCase()}",
                            contentPadding: padding,
                            aspectRatio: 0.6,
                          )
                      ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ),
                ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
    );
  }
}

/// The page before the show has arrived.
///
/// This is the gap that actually exists. The rows have their own placeholders,
/// but by the time there is a show to hang them under, the rows are there too -
/// they come back in the same response now - so on their own they were never on
/// screen long enough to see. What there is instead is this: a moment where the
/// page knows which show it is opening and nothing else.
class _ShowSkeleton extends StatelessWidget {
  final EdgeInsets padding;
  const _ShowSkeleton({required this.padding});

  @override
  Widget build(BuildContext context) {
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    // Where [OverviewHeader] starts once it has something to draw: just inside
    // the bottom of the artwork on a phone, below it everywhere else.
    final headerOffset = detailArtworkHeight(context) * (isPhone ? 0.74 : 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: headerOffset),
          Padding(
            padding: padding,
            child: Shimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  const ShimmerBox(height: 38, width: 280),
                  const ShimmerBox(height: 46, width: 190),
                  ...List.filled(3, const ShimmerBox(height: 16)),
                  const ShimmerBox(height: 16, width: 220),
                ],
              ),
            ),
          ),
          ShimmerPosterRow(
            label: context.localized.episode(2),
            contentPadding: padding,
            aspectRatio: 1.76,
          ),
          ShimmerPosterRow(
            label: context.localized.season(2),
            contentPadding: padding,
            aspectRatio: 0.6,
            dominantRatio: 0.6,
          ),
        ].addPadding(const EdgeInsets.symmetric(vertical: 16)),
      ),
    );
  }
}

/// The episode picker, in whichever of the three shapes is selected: the row
/// the series page has always had, or the grid and list the season page used to
/// own. All three select in place rather than opening anything.
class _EpisodeSection extends StatelessWidget {
  final EdgeInsets padding;
  final String label;
  final List<EpisodeModel> allEpisodes;
  final List<EpisodeModel> seasonEpisodes;
  final List<SeasonModel> seasons;
  final EpisodeModel? selectedEpisode;
  final int? selectedSeason;
  final EpisodeDetailsViewType viewType;
  final ValueChanged<EpisodeDetailsViewType> onViewTypeChanged;
  final ValueChanged<int?> onSeasonChanged;
  final ValueChanged<EpisodeModel> onEpisodeSelected;
  final ValueChanged<EpisodeModel> onEpisodeFocused;
  final ValueChanged<EpisodeModel> onPlayEpisode;

  const _EpisodeSection({
    required this.padding,
    required this.label,
    required this.allEpisodes,
    required this.seasonEpisodes,
    required this.seasons,
    required this.selectedEpisode,
    required this.selectedSeason,
    required this.viewType,
    required this.onViewTypeChanged,
    required this.onSeasonChanged,
    required this.onEpisodeSelected,
    required this.onEpisodeFocused,
    required this.onPlayEpisode,
  });

  @override
  Widget build(BuildContext context) {
    final viewSwitch = EpisodeViewTypeButton(
      current: viewType,
      onChanged: onViewTypeChanged,
    );
    final seasonPicker = allEpisodes.episodesBySeason.length > 1
        ? SeasonSelectionBox(
            episodes: allEpisodes,
            seasons: seasons,
            selectedSeason: selectedSeason,
            onSeasonChanged: onSeasonChanged,
          )
        : null;

    if (viewType == EpisodeDetailsViewType.row) {
      return EpisodePosters(
        contentPadding: padding,
        selectedEpisode: selectedEpisode,
        seasons: seasons,
        selectedSeason: selectedSeason,
        onSeasonChanged: onSeasonChanged,
        // Above the row, like every other row on the page. A d-pad still gets
        // neither, because there the focus says where you are and the header
        // only competes.
        titleActionsPosition: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad ? null : VerticalDirection.up,
        label: label,
        trailingTitleActions: [viewSwitch],
        onFocused: onEpisodeFocused,
        onEpisodeTap: (_, episode) => onEpisodeSelected(episode),
        playEpisode: onPlayEpisode,
        episodes: allEpisodes,
      );
    }

    // The same bar the row draws above itself, so the switch that got us here
    // has not moved by so much as a pixel.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        HorizontalListTitleBar(
          contentPadding: padding,
          label: label,
          titleActions: [
            if (seasonPicker != null) ...[
              const SizedBox(width: 16),
              seasonPicker,
            ]
          ],
          trailingTitleActions: [viewSwitch],
        ),
        EpisodeDetailsList(
          episodes: seasonEpisodes,
          padding: padding,
          selectedEpisode: selectedEpisode,
          onEpisodeTap: onEpisodeSelected,
        ),
      ],
    );
  }
}

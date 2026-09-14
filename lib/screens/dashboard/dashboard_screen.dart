import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/library_filter_model.dart';
import 'package:chudder/models/library_search/library_search_options.dart';
import 'package:chudder/models/recommended_model.dart';
import 'package:chudder/models/settings/home_settings_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/providers/dashboard_mode_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/dashboard_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/settings/home_settings_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/dashboard/dashboard_rows.dart';
import 'package:chudder/screens/dashboard/home_banner_widget.dart';
import 'package:chudder/screens/dashboard/music_dashboard_screen.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/screens/shared/nested_scaffold.dart';
import 'package:chudder/screens/shared/nested_sliver_appbar.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/continue_row.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/sliver_list_padding.dart';
import 'package:chudder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:chudder/widgets/shared/pinch_poster_zoom.dart';
import 'package:chudder/widgets/shared/poster_size_slider.dart';
import 'package:chudder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final Timer _timer;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  final textController = TextEditingController();

  final selectedPoster = ValueNotifier<ItemBaseModel?>(null);

  /// A tick that came while nobody was looking, to be honoured when they are.
  bool _refreshOwed = false;
  TabsRouter? _tabsRouter;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 120), (timer) => _tick());
    // The first load, once, and without the indicator - see the PullToRefresh
    // below for why this page must not reload itself on the way back.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(dashboardProvider).hasContinueRows) return;
      _refreshHome();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabsRouter = AutoTabsRouter.of(context);
    if (tabsRouter != _tabsRouter) {
      _tabsRouter?.removeListener(_onTabChanged);
      _tabsRouter = tabsRouter..addListener(_onTabChanged);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _tabsRouter?.removeListener(_onTabChanged);
    super.dispose();
  }

  /// Whether this screen is what is on screen: its tab is the active one and
  /// nothing is pushed over Home.
  bool get _isVisible =>
      (_tabsRouter?.activeIndex ?? HomeTabs.dashboard.index) == HomeTabs.dashboard.index &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  /// The tab stays alive once it has been shown, so this used to fire every
  /// two minutes for as long as the app was open - a dozen requests a time,
  /// for a screen that was behind the library or a details page. Now it only
  /// refreshes what can be seen, and catches up once when the tab comes back.
  void _tick() {
    if (!mounted) return;
    if (_isVisible) {
      _refreshIndicatorKey.currentState?.show();
    } else {
      _refreshOwed = true;
    }
  }

  void _onTabChanged() {
    if (!_refreshOwed || !mounted || !_isVisible) return;
    _refreshOwed = false;
    _refreshIndicatorKey.currentState?.show();
  }

  Future<void> _refreshHome() async {
    if (!mounted) return;
    final dashboard = ref.read(dashboardProvider.notifier);
    final bannerSource = ref.read(homeSettingsProvider).carouselSettings;
    // Favourites change with what you mark; a random pick stays for the session.
    dashboard.fetchBannerItems(bannerSource, force: bannerSource == HomeCarouselSettings.favourites).ignore();
    await dashboard.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(musicDashboardModeProvider)) {
      return const MusicDashboardScreen();
    }

    ref.listen(
      homeSettingsProvider.select((value) => value.carouselSettings),
      (_, next) => ref.read(dashboardProvider.notifier).fetchBannerItems(next),
    );
    final padding = AdaptiveLayout.adaptivePadding(context);
    final bannerType = ref.watch(homeSettingsProvider.select((value) => value.homeBanner));
    final dashboardData = ref.watch(dashboardProvider);
    // Only the rows this screen draws. The full views model also carries the
    // list the drawer shows, and changes to that used to rebuild everything
    // here.
    final dashboardViews = ref.watch(viewsProvider.select((value) => value.dashboardViews));
    final homeSettings = ref.watch(homeSettingsProvider);
    final homeBanner = bannerType != HomeBanner.hide;
    final resumeVideo = dashboardData.resumeVideo;
    final resumeAudio = dashboardData.resumeAudio;
    final resumeBooks = dashboardData.resumeBooks;
    final tvChannels = dashboardData.activePrograms;

    final allResume = [...resumeVideo, ...resumeAudio, ...resumeBooks];
    // One entry per thing and in the order it was last played - see
    // [DashboardNotifier]. It used to be the resume lists and the next-up list
    // simply laid end to end, which put everything you are part-way through
    // ahead of everything you finished, however long ago, and let a show you
    // are watching appear in both halves.
    final combined = dashboardData.continueWatching;

    final combinedMode = homeSettings.nextUp == HomeNextUp.combined;
    final bannerSource = homeSettings.carouselSettings;
    // Continue watching, however the rows are set: the combined row, or what
    // is part-way through.
    final continueItems = combinedMode ? combined : (resumeVideo.isNotEmpty ? resumeVideo : allResume);
    final homeCarouselItems = switch (bannerSource) {
      HomeCarouselSettings.cont || HomeCarouselSettings.combined => continueItems,
      HomeCarouselSettings.nextUp => dashboardData.nextUp,
      HomeCarouselSettings.recentlyAdded => _recentlyAdded(dashboardViews),
      HomeCarouselSettings.random ||
      HomeCarouselSettings.favourites =>
        dashboardData.bannerSource == bannerSource ? dashboardData.bannerItems : const <ItemBaseModel>[],
    };

    // The detailed banner is a row of cards itself. Showing what a row further
    // down shows, it takes that row's place rather than standing over a copy.
    final detailedBanner = homeBanner && bannerType == HomeBanner.detailedBanner && homeCarouselItems.isNotEmpty;
    final bannerIsCombinedRow = detailedBanner && bannerSource.isContinue && combinedMode;
    final bannerIsResumeRow = detailedBanner && bannerSource.isContinue && !combinedMode;
    final bannerIsNextUpRow = detailedBanner && bannerSource == HomeCarouselSettings.nextUp && !combinedMode;

    final viewSize = AdaptiveLayout.viewSizeOf(context);

    final useTVExpandedLayout = ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));
    // Only the rows of things to carry on with. Music and books keep their
    // covers in rows of their own.
    final continueWide = homeSettings.continueArt == HomeContinueArt.screenshots;
    final showResumeRows = homeSettings.nextUp == HomeNextUp.cont || homeSettings.nextUp == HomeNextUp.separate;
    // Beside a Continue watching row, the episodes you are part-way through
    // are already in it.
    final nextUpRow = showResumeRows ? nextUpBesideResume(dashboardData.nextUp, resumeVideo) : dashboardData.nextUp;

    return NestedScaffold(
      background: ValueListenableBuilder<ItemBaseModel?>(
        valueListenable: selectedPoster,
        builder: (_, value, __) {
          return BackgroundImage(
            images: (value != null
                    ? [value]
                    : [
                        ...homeCarouselItems,
                        ...dashboardData.nextUp,
                        ...allResume,
                      ])
                .map((e) => e.images)
                .nonNulls
                .toList(),
          );
        },
      ),
      body: PullToRefresh(
        // Never on its own, and never on behalf of what is drawn inside it.
        //
        // Reloading here is what moved the selection about. Coming back from a
        // film this page fetched itself again: its rows emptied for a moment,
        // the scroll offset clamped towards the top because there was briefly
        // nothing to scroll, and the lazy list threw away every row that had
        // gone out of view - the one holding the selection among them. What came
        // back was new rows, scrolled to their first item (see
        // [HorizontalList._measureFirstItem]), and the selection landed wherever
        // that left it. The first load is in [initState]; a pull, F5 or the
        // catch-up on a tab change still refresh.
        refreshOnStart: false,
        contextRefresh: false,
        refreshKey: _refreshIndicatorKey,
        displacement: 80 + MediaQuery.of(context).viewPadding.top,
        onRefresh: () async => await _refreshHome(),
        child: (context) => PinchPosterZoom(
          scaleDifference: (difference) => ref.read(clientSettingsProvider.notifier).addPosterSize(difference),
          child: CustomScrollView(
            scrollCacheExtent: kPosterCacheExtent,
            controller: AdaptiveLayout.scrollOf(context, HomeTabs.dashboard),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (bannerType != HomeBanner.detailedBanner) const DefaultSliverTopBadding(),
              if (viewSize == ViewSize.phone)
                NestedSliverAppBar(
                  route: LibrarySearchRoute(),
                  parent: context,
                ),
              if (homeBanner && homeCarouselItems.isNotEmpty) ...{
                SliverToBoxAdapter(
                  child: Padding(
                    padding: AdaptiveLayout.adaptivePadding(
                      context,
                      horizontalPadding: 0,
                    ),
                    child: HomeBannerWidget(
                      posters: homeCarouselItems,
                      label: bannerSource.rowLabel(context),
                      onSelect: (poster) => selectedPoster.value = poster,
                    ),
                  ),
                ),
              },
              if (AdaptiveLayout.of(context).isDesktop)
                const SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PosterSizeWidget(),
                    ],
                  ),
                ),
              DashboardRows(
                autoFocusFirst: homeCarouselItems.isEmpty,
                // Each row already carries its own label spacing; 16 on top of
                // that reads as a gap between rows rather than a list.
                spacing: 8,
                rows: [
                  if (tvChannels.isNotEmpty)
                    PosterRow(
                      key: const ValueKey('row-live-tv'),
                      contentPadding: padding,
                      tvMode: useTVExpandedLayout,
                      label: context.localized.activeTvChannels,
                      collectionAspectRatio: 0.55,
                      onLabelClick: () {
                        return LiveTvRoute().navigate(context);
                      },
                      posters: tvChannels,
                    ),
                  if (showResumeRows && resumeVideo.isNotEmpty && !bannerIsResumeRow)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      key: const ValueKey('row-resume-video'),
                      wideArt: continueWide,
                      label: context.localized.dashboardContinueWatching,
                      posters: resumeVideo,
                    ),
                  if (showResumeRows && resumeAudio.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      key: const ValueKey('row-resume-audio'),
                      label: context.localized.dashboardContinueListening,
                      posters: resumeAudio,
                    ),
                  if (showResumeRows && resumeBooks.isNotEmpty)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      key: const ValueKey('row-resume-books'),
                      label: context.localized.dashboardContinueReading,
                      posters: resumeBooks,
                    ),
                  if (nextUpRow.isNotEmpty &&
                      !bannerIsNextUpRow &&
                      (homeSettings.nextUp == HomeNextUp.nextUp || homeSettings.nextUp == HomeNextUp.separate))
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      key: const ValueKey('row-next-up'),
                      wideArt: continueWide,
                      label: context.localized.nextUp,
                      posters: nextUpRow,
                    ),
                  if (combined.isNotEmpty && combinedMode && !bannerIsCombinedRow)
                    PosterRow(
                      tvMode: useTVExpandedLayout,
                      contentPadding: padding,
                      key: const ValueKey('row-continue'),
                      wideArt: continueWide,
                      // What you left at the end of an episode is something to
                      // continue with too; "Next up" needs no row name of its own.
                      label: context.localized.dashboardContinueWatching,
                      posters: combined,
                    ),
                  // Server data, cached from when there was a server. Offline
                  // these are posters that cannot be opened, so the row is
                  // dropped rather than shown alongside the downloads.
                  if (!ref.watch(offlineStateProvider))
                    ...dashboardViews
                        .where(
                          (element) =>
                              element.recentlyAdded.isNotEmpty && element.collectionType != CollectionType.livetv,
                        )
                        .map(
                          (view) => PosterRow(
                            key: ValueKey('row-recent-${view.id}'),
                            tvMode: useTVExpandedLayout,
                            contentPadding: padding,
                            label: context.localized.dashboardRecentlyAdded(view.name),
                            collectionAspectRatio: view.collectionType.aspectRatio,
                            onLabelClick: () {
                              if (view.collectionType == CollectionType.livetv) {
                                return LiveTvRoute().navigate(context);
                              }
                              return context.router.push(
                                LibrarySearchRoute(
                                  parentId: [view.id],
                                  // Shows, not episodes: the row collapses new
                                  // episodes to their series, so "see more" lands
                                  // on the same thing — series, newest content
                                  // first. Flip the type filter to episodes
                                  // yourself if that's what you're after.
                                  types: switch (view.collectionType) {
                                    CollectionType.tvshows => {
                                        FladderItemType.series: true,
                                      },
                                    _ => {},
                                  },
                                  sortingOptions: switch (view.collectionType) {
                                    CollectionType.tvshows ||
                                    CollectionType.books ||
                                    CollectionType.boxsets ||
                                    CollectionType.folders ||
                                    CollectionType.music =>
                                      SortingOptions.dateLastContentAdded,
                                    _ => SortingOptions.dateAdded,
                                  },
                                  sortOrder: SortingOrder.descending,
                                  recursive: true,
                                ),
                              );
                            },
                            posters: view.recentlyAdded,
                          ),
                        ),
                  // Something to browse once there is nothing left to carry on
                  // with: the dashboard was three rows long on a well-watched
                  // account. Filled in once rather than on every refresh - see
                  // [DashboardNotifier.fetchBrowseRows] - and empty offline, so
                  // the rows simply are not there.
                  if (!ref.watch(offlineStateProvider)) ...[
                    ...dashboardData.suggestions.map(
                      (row) => PosterRow(
                        key: ValueKey('row-suggestion-${row.name.label(context.localized)}-${row.type}'),
                        tvMode: useTVExpandedLayout,
                        contentPadding: padding,
                        // The category says what the row is for; the film it was
                        // drawn from says which one it is.
                        label: row.type != null
                            ? "${row.type!.label(context.localized)} - ${row.name.label(context.localized)}"
                            : row.name.label(context.localized),
                        posters: row.posters,
                      ),
                    ),
                    ...dashboardData.genres.map(
                      (row) => PosterRow(
                        key: ValueKey('row-genre-${row.name.label(context.localized)}'),
                        tvMode: useTVExpandedLayout,
                        contentPadding: padding,
                        label: row.name.label(context.localized),
                        onLabelClick: row.name is Other
                            ? () => context.router.push(
                                  LibrarySearchRoute().withFilter(
                                    LibraryFilterModel(
                                      recursive: true,
                                      genres: {(row.name as Other).customLabel: true},
                                    ),
                                  ),
                                )
                            : null,
                        posters: row.posters,
                      ),
                    ),
                  ],
                ],
              ),
              const DefaultSliverBottomPadding(),
            ],
          ),
        ),
      ),
    );
  }
}

/// What was added last across the libraries on the home page, newest first:
/// what their Recently added rows hold, as one list.
List<ItemBaseModel> _recentlyAdded(List<ViewModel> views) {
  final items = views
      .where((view) => view.collectionType != CollectionType.livetv)
      .expand((view) => view.recentlyAdded)
      .toList()
    ..sort((a, b) => (b.overview.dateAdded ?? DateTime(0)).compareTo(a.overview.dateAdded ?? DateTime(0)));
  return items.take(20).toList();
}

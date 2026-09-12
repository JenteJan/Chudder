import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/seerr_dashboard_provider.dart';
import 'package:fladder/providers/seerr_user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/seerr/widgets/seerr_request_banner_row.dart';
import 'package:fladder/screens/seerr/widgets/seerr_request_popup.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/screens/shared/nested_sliver_appbar.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/sliver_list_padding.dart';
import 'package:fladder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class SeerrScreen extends ConsumerStatefulWidget {
  const SeerrScreen({super.key});

  @override
  ConsumerState<SeerrScreen> createState() => _SeerrScreenState();
}

class _SeerrScreenState extends ConsumerState<SeerrScreen> {
  // Nothing fetches here. The PullToRefresh below refreshes on start, which
  // fills the dashboard as the tab appears and shows the indicator while it
  // does; doing it here as well sent the whole fan-out - seven requests - twice
  // over on every visit to the tab.

  Future<void> openRequest(BuildContext context, SeerrDashboardPosterModel poster) async {
    await openSeerrRequestPopup(context, poster);
    await ref.read(seerrDashboardProvider.notifier).fetchDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdaptiveLayout.adaptivePadding(context);
    final dashboardState = ref.watch(seerrDashboardProvider);
    final canViewRecent = ref.watch(seerrUserProvider.select((state) => state?.canViewRecent ?? false));
    final backgroundImages = [
      ...dashboardState.recentlyAdded,
      ...dashboardState.recentRequests,
      ...dashboardState.trending,
      ...dashboardState.popularMovies,
      ...dashboardState.popularSeries,
      ...dashboardState.expectedMovies,
      ...dashboardState.expectedSeries,
    ].map((e) => e.images).toList(growable: false);

    return MediaQuery.removeViewInsets(
      context: context,
      child: NestedScaffold(
        background: BackgroundImage(
          images: backgroundImages,
        ),
        body: PullToRefresh(
          onRefresh: () => ref.read(seerrDashboardProvider.notifier).fetchDashboard(),
          child: (context) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: AdaptiveLayout.scrollOf(context, HomeTabs.seerr),
            slivers: [
              if (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
                NestedSliverAppBar(parent: context)
              else
                const DefaultSliverTopBadding(),
              // Each row keyed by which row it is, not by where it sits. The
              // seven rows arrive one request at a time, in whatever order the
              // server answers, and a sliver list matches the children it is
              // given: a row appearing above the one you were on used to hand
              // that row's whole state - scroll offset, remembered card, the
              // selection - to the next row down's posters. The selection went
              // with it, onto a card in the wrong row, and the page followed.
              // It looked random because the order the answers came in was.
              if (canViewRecent && dashboardState.recentlyAdded.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-recently-added'),
                  child: SeerrPosterRow(
                    label: context.localized.recentlyAdded,
                    posters: dashboardState.recentlyAdded,
                    contentPadding: padding,
                  ),
                ),
              if (dashboardState.recentRequests.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-recent-requests'),
                  child: SeerrRequestBannerRow(
                    label: context.localized.recentRequests,
                    posters: dashboardState.recentRequests,
                    contentPadding: padding,
                    onRequestAddTap: (poster) => openRequest(context, poster),
                  ),
                ),
              if (dashboardState.trending.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-trending'),
                  child: SeerrPosterRow(
                    label: context.localized.trending,
                    posters: dashboardState.trending,
                    contentPadding: padding,
                    onLabelClick: () => context.pushRoute(SeerrSearchRoute(mode: SeerrSearchMode.trending)),
                  ),
                ),
              if (dashboardState.popularMovies.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-popular-movies'),
                  child: SeerrPosterRow(
                    label: context.localized.popularMovies,
                    posters: dashboardState.popularMovies,
                    contentPadding: padding,
                    onLabelClick: () => context.pushRoute(SeerrSearchRoute(mode: SeerrSearchMode.discoverMovies)),
                  ),
                ),
              if (dashboardState.popularSeries.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-popular-series'),
                  child: SeerrPosterRow(
                    label: context.localized.popularSeries,
                    posters: dashboardState.popularSeries,
                    contentPadding: padding,
                    onLabelClick: () => context.pushRoute(SeerrSearchRoute(mode: SeerrSearchMode.discoverTv)),
                  ),
                ),
              if (dashboardState.expectedMovies.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-expected-movies'),
                  child: SeerrPosterRow(
                    label: context.localized.expectedMovies,
                    posters: dashboardState.expectedMovies,
                    contentPadding: padding,
                    onLabelClick: () => context.pushRoute(
                      SeerrSearchRoute(
                        mode: SeerrSearchMode.discoverMovies,
                        yearGte: DateTime.now().year,
                      ),
                    ),
                  ),
                ),
              if (dashboardState.expectedSeries.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('seerr-expected-series'),
                  child: SeerrPosterRow(
                    label: context.localized.expectedSeries,
                    posters: dashboardState.expectedSeries,
                    contentPadding: padding,
                    onLabelClick: () => context.pushRoute(
                      SeerrSearchRoute(
                        mode: SeerrSearchMode.discoverTv,
                        yearGte: DateTime.now().year,
                      ),
                    ),
                  ),
                ),
              const DefaultSliverBottomPadding(),
            ],
          ),
        ),
      ),
    );
  }
}

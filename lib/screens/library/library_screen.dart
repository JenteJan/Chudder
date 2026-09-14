import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';


import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/library_filter_model.dart';
import 'package:chudder/models/recommended_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/providers/library_screen_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/dashboard/dashboard_rows.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/metadata/refresh_metadata.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/screens/shared/nested_scaffold.dart';
import 'package:chudder/screens/shared/nested_sliver_appbar.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/sliver_list_padding.dart';
import 'package:chudder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:chudder/widgets/shared/button_group.dart';
import 'package:chudder/widgets/shared/horizontal_list.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  final GlobalKey<RefreshIndicatorState>? refreshKey = GlobalKey();

  bool refreshing = false;

  @override
  void initState() {
    super.initState();
    // The first load runs here rather than through the refresh indicator.
    //
    // It used to be [PullToRefresh]'s refreshOnStart, which shows the spinner
    // and dims the page whatever the reason for it. Coming back from a film -
    // where the provider is keepAlive and every row is still in memory - that
    // meant a spinner, a dimmed page, every row replaced, the genre rows
    // re-rolled and the scroll position thrown away, to arrive at what was
    // already on screen. A pull, F5 or turning on a new filter still shows the
    // indicator, because those are somebody asking for one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final views = ref.read(libraryScreenProvider).views;
      if (views.isNotEmpty) return;
      ref.read(libraryScreenProvider.notifier).fetchAllLibraries(reuseKnownViews: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(libraryScreenProvider, (previous, next) {
      if ((previous?.viewType.length ?? 0) < next.viewType.length) {
        refreshKey?.currentState?.show();
      }
    });
    final libraryScreenState = ref.watch(libraryScreenProvider);
    final views = libraryScreenState.views;
    final recommendations = libraryScreenState.recommendations;
    final favourites = libraryScreenState.favourites;
    final selectedView = libraryScreenState.selectedViewModel;
    final viewTypes = libraryScreenState.viewType;
    final genres = libraryScreenState.genres;
    final padding = AdaptiveLayout.adaptivePadding(context);

    final useTVExpandedLayout = ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));

    return NestedScaffold(
      background: BackgroundImage(
        items: [
          ...recommendations.expand((e) => e.posters),
          ...favourites,
        ],
      ),
      body: PullToRefresh(
        // Never automatically: the indicator is for somebody who asked for one.
        // The first load is in [initState].
        refreshOnStart: false,
        // And not on behalf of whatever is drawn inside this page either.
        // `context.refreshData()` walks up the tree and fires the nearest
        // indicator, so anything on the page - a poster's menu marking an
        // episode watched, a sheet closing - could make the whole library
        // fetch itself again: every row replaced, the genre rows re-rolled and
        // the scroll position gone, for a change to one card. What the server
        // says about an item now arrives on its own, over the socket - see
        // [userDataUpdatesProvider] - so nothing here needs a page reload to
        // notice it. A pull, F5 or a new filter still refreshes.
        contextRefresh: false,
        refreshKey: refreshKey,
        onRefresh: () async {
          if (refreshing) return;
          setState(() => refreshing = true);
          try {
            await ref.read(libraryScreenProvider.notifier).fetchAllLibraries();
          } finally {
            if (mounted) {
              setState(() => refreshing = false);
            }
          }
        },
        child: (context) => AnimatedOpacity(
          opacity: refreshing ? 0.75 : 1.0,
          duration: const Duration(milliseconds: 175),
          child: SizedBox.expand(
            child: CustomScrollView(
              scrollCacheExtent: kPosterCacheExtent,
              controller: AdaptiveLayout.scrollOf(context, HomeTabs.library),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const DefaultSliverTopBadding(),
                if (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
                  NestedSliverAppBar(
                    route: LibrarySearchRoute(),
                    parent: context,
                  ),
                if (views.isNotEmpty)
                  SliverToBoxAdapter(
                    child: LibraryRow(
                      padding: padding,
                      views: views,
                      selectedView: libraryScreenState.selectedViewModel,
                      onSelected: (view) {
                        if (refreshing) return;
                        ref.read(libraryScreenProvider.notifier).selectLibrary(view);
                        refreshKey?.currentState?.show();
                      },
                    ),
                  ),
                if (selectedView != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 16),
                      child: SizedBox(
                        height: 40,
                        child: ListView(
                          padding: padding,
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => context.pushRoute(LibrarySearchRoute(parentId: [selectedView.id])),
                              label: Text("${context.localized.search} ${selectedView.name}..."),
                              icon: const Icon(IconsaxPlusLinear.search_normal_1),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: VerticalDivider(),
                            ),
                            ExpressiveButtonGroup(
                              multiSelection: true,
                              options: LibraryViewType.values
                                  .map((element) => ButtonGroupOption(
                                      value: element,
                                      icon: Icon(element.icon),
                                      selected: Icon(element.iconSelected),
                                      child: Text(
                                        element.label(context),
                                      )))
                                  .toList(),
                              selectedValues: viewTypes,
                              onSelected: (value) => ref.read(libraryScreenProvider.notifier).setViewType(value),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4.0),
                              child: VerticalDivider(),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => showRefreshPopup(context, selectedView.id, selectedView.name),
                              label: Text(context.localized.scanLibrary),
                              icon: const Icon(IconsaxPlusLinear.refresh),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (viewTypes.isEmpty)
                  SliverFillRemaining(
                    child: Center(child: Text(context.localized.noResults)),
                  )
                else
                  // Built as they come into view. Each row was its own
                  // SliverToBoxAdapter, which is not lazy: a library with forty
                  // genres laid all forty out on the first frame and set every
                  // one of their pictures loading. The rows carry a hundred
                  // items now, so it counts for more than it did.
                  DashboardRows(
                    spacing: 8,
                    // The picker above holds the selection; a row taking it
                    // would drop the pad down the page on arrival.
                    autoFocusFirst: false,
                    rows: [
                      if (viewTypes.contains(LibraryViewType.recommended))
                        ...recommendations.where((element) => element.posters.isNotEmpty).map(
                              (element) => PosterRow(
                                key: ValueKey('lib-rec-${element.name.label(context.localized)}-${element.type}'),
                                tvMode: useTVExpandedLayout,
                                contentPadding: padding,
                                posters: element.posters,
                                // Not primaryPosters: that swaps each poster for
                                // the item's own image, which for an episode is a
                                // wide still, so the Continue row came out as short
                                // wide tiles among rows of posters. The dashboard's
                                // Continue row has always used posters.
                                label: element.type != null
                                    ? "${element.name.label(context.localized)} - ${element.type?.label(context.localized)}"
                                    : element.name.label(context.localized),
                              ),
                            ),
                      if (viewTypes.contains(LibraryViewType.favourites) && favourites.isNotEmpty)
                        PosterRow(
                          key: const ValueKey('lib-favourites'),
                          tvMode: useTVExpandedLayout,
                          contentPadding: padding,
                          onLabelClick: () => context.pushRoute(
                            LibrarySearchRoute(
                              parentId: [libraryScreenState.selectedViewModel?.id ?? ""],
                            ).withFilter(
                              const LibraryFilterModel(
                                favourites: true,
                                recursive: true,
                              ),
                            ),
                          ),
                          posters: favourites,
                          label: context.localized.favorites,
                        ),
                      if (viewTypes.contains(LibraryViewType.genres))
                        ...genres.where((element) => element.posters.isNotEmpty).map(
                              (element) => PosterRow(
                                key: ValueKey('lib-genre-${element.name.label(context.localized)}'),
                                tvMode: useTVExpandedLayout,
                                contentPadding: padding,
                                posters: element.posters,
                                onLabelClick: () => context.pushRoute(
                                  LibrarySearchRoute(
                                    parentId: [libraryScreenState.selectedViewModel?.id ?? ""],
                                  ).withFilter(
                                    LibraryFilterModel(
                                      recursive: true,
                                      genres: {(element.name as Other).customLabel: true},
                                    ),
                                  ),
                                ),
                                label: element.type != null
                                    ? "${element.name.label(context.localized)} - ${element.type?.label(context.localized)}"
                                    : element.name.label(context.localized),
                              ),
                            ),
                    ],
                  ),
                const DefaultSliverBottomPadding(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryRow extends ConsumerWidget {
  const LibraryRow({
    super.key,
    required this.views,
    this.selectedView,
    required this.padding,
    this.onSelected,
    this.onLongPress,
    this.viewActions,
    this.enableImageCache = true,
  });

  final List<ViewModel> views;
  final ViewModel? selectedView;
  final EdgeInsets padding;
  final FutureOr Function(ViewModel selected)? onSelected;
  final FutureOr Function(ViewModel selected)? onLongPress;
  final List<ItemActionButton> Function(ViewModel item)? viewActions;
  final bool enableImageCache;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HorizontalList(
      label: context.localized.library(views.length),
      items: views,
      height: 155,
      // This row is the top of the screen, where the arrows and the
      // jump-to-current dot sit under the SyncPlay and Cast buttons. The row
      // scrolls by drag and wheel regardless.
      showScrollControls: false,
      autoFocus: true,
      startIndex: selectedView != null ? views.indexOf(selectedView!) : null,
      contentPadding: padding,
      itemBuilder: (context, index) {
        final view = views[index];
        final isSelected = selectedView == view;
        final List<ItemActionButton> combinedViewActions = [
          ItemActionButton(
            label: Text(context.localized.search),
            icon: const Icon(IconsaxPlusLinear.search_normal_1),
            action: () => context.pushRoute(LibrarySearchRoute(parentId: [view.id])),
          ),
          ItemActionButton(
            label: Text(context.localized.scanLibrary),
            icon: const Icon(IconsaxPlusLinear.refresh),
            action: () => showRefreshPopup(context, view.id, view.name),
          ),
          ...?viewActions?.call(view),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FocusButton(
              key: Key(view.id),
              onTap: isSelected ? null : () => onSelected?.call(view),
              onLongPress: onLongPress != null
                  ? () => onLongPress?.call(view)
                  : () => context.pushRoute(LibrarySearchRoute(parentId: [view.id])),
              onSecondaryTapDown: (details) async {
                Offset localPosition = details.globalPosition;
                RelativeRect position =
                    RelativeRect.fromLTRB(localPosition.dx, localPosition.dy, localPosition.dx, localPosition.dy);
                await showMenu(
                  context: context,
                  position: position,
                  items: combinedViewActions.popupMenuItems(useIcons: true),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: FladderTheme.smallShape.borderRadius,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: isSelected ? 1.0 : 0.0),
                    width: isSelected ? 3 : 0,
                  ),
                ),
                clipBehavior: Clip.hardEdge,
                width: 200,
                child: ClipRRect(
                  borderRadius: FladderTheme.smallShape.borderRadius,
                  child: AspectRatio(
                    aspectRatio: 1.60,
                    child: FladderImage(
                      image: view.imageData?.primary,
                      fit: BoxFit.cover,
                      cachedImage: enableImageCache,
                      placeHolder: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Icon(view.collectionType.icon),
                            Text(
                              view.name,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSelected)
                  Container(
                    height: 12,
                    width: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                Text(
                  view.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.start,
                )
              ],
            )
          ],
        );
      },
    );
  }
}

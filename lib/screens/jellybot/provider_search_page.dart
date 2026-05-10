import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/jellybot/jellybot_search_state.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/providers/jellybot_search_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/jellybot/dialogs/confirm_crawl_link_dialog.dart';
import 'package:fladder/screens/jellybot/dialogs/existing_media_dialog.dart';
import 'package:fladder/screens/jellybot/dialogs/season_picker_dialog.dart';
import 'package:fladder/screens/jellybot/widgets/adaptive_results_view.dart';
import 'package:fladder/screens/jellybot/widgets/search_advanced_controls.dart';
import 'package:fladder/screens/jellybot/widgets/search_empty_state.dart';
import 'package:fladder/screens/jellybot/widgets/search_error_state.dart';
import 'package:fladder/screens/jellybot/widgets/search_no_results_state.dart';
import 'package:fladder/screens/jellybot/widgets/search_skeleton_card.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/button_group.dart';
import 'package:fladder/widgets/shared/fladder_scrollbar.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class JellybotProviderSearchPage extends ConsumerStatefulWidget {
  const JellybotProviderSearchPage({super.key});

  @override
  ConsumerState<JellybotProviderSearchPage> createState() =>
      _JellybotProviderSearchPageState();
}

class _JellybotProviderSearchPageState
    extends ConsumerState<JellybotProviderSearchPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  String? _addingItemUrl;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onCategoryQuickPick(MediaCategory cat) {
    ref.read(jellybotSearchControllerProvider.notifier).setCategory(cat);
    setState(() {});
  }

  void _clearFilters() {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    ctrl.setSelectedFilters(const {});
    ctrl.toggleExactMatch(false);
    ctrl.setMinScore(null);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final floatingAppBar =
        AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;

    final providersAsync = ref.watch(jellybotProvidersProvider);
    final searchState = ref.watch(jellybotSearchControllerProvider);
    final controllerState =
        ref.read(jellybotSearchControllerProvider.notifier).searchState;
    final filtersAsync = controllerState.provider == null
        ? const AsyncValue<List<ISearchFilter>>.data(<ISearchFilter>[])
        : ref.watch(
            jellybotSearchFiltersProvider(
              controllerState.provider!.id!,
              controllerState.category,
            ),
          );

    return NestedScaffold(
      body: Padding(
        padding: EdgeInsets.only(left: AdaptiveLayout.of(context).sideBarWidth),
        child: Scaffold(
          backgroundColor: null,
          body: FladderScrollbar(
            controller: _scrollController,
            child: PullToRefresh(
              refreshKey: _refreshKey,
              onRefresh: () async {
                ref.invalidate(jellybotProvidersProvider);
                ref.invalidate(addedCrawlLinkUrlsProvider);
                await ref
                    .read(jellybotSearchControllerProvider.notifier)
                    .search();
              },
              child: (context) => CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildAppBar(
                    context,
                    floatingAppBar,
                    surfaceColor,
                    providersAsync,
                    filtersAsync,
                  ),
                  if (_showAdvanced)
                    const SliverToBoxAdapter(child: SearchAdvancedControls()),
                  ..._buildResultsSlivers(searchState, controllerState),
                  SliverPadding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).padding.bottom + 80,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildResultsSlivers(
    AsyncValue<PaginatedResponseOfProviderSearchItemDto?> searchState,
    JellybotSearchState controllerState,
  ) {
    return [
      searchState.when(
        data: (response) {
          if (response == null) {
            if (_searchController.text.isEmpty) {
              return SliverFillRemaining(
                child: SearchEmptyState(onCategoryTap: _onCategoryQuickPick),
              );
            }
            return SliverFillRemaining(
              child: SearchNoResultsState(
                onClearFilters: _clearFilters,
                hasActiveFilters: controllerState.activeFilterCount > 0,
              ),
            );
          }
          final items = response.items ?? const <ProviderSearchItemDto>[];
          if (items.isEmpty) {
            return SliverFillRemaining(
              child: SearchNoResultsState(
                onClearFilters: _clearFilters,
                hasActiveFilters: controllerState.activeFilterCount > 0,
              ),
            );
          }
          return SliverMainAxisGroup(
            slivers: [
              AdaptiveResultsView(
                items: items,
                provider: controllerState.provider,
                addingItemUrl: _addingItemUrl,
                onAdd: _addToCrawlLinks,
              ),
              if ((response.totalPages ?? 0) > 1)
                SliverToBoxAdapter(
                  child: _PaginationBar(
                    currentPage: response.currentPage ?? 0,
                    totalPages: response.totalPages ?? 0,
                    totalCount: response.totalCount ?? 0,
                    onJump: (p) => ref
                        .read(jellybotSearchControllerProvider.notifier)
                        .search(page: p),
                  ),
                ),
            ],
          );
        },
        loading: () => SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, _) => const SearchSkeletonCard(),
            childCount: 6,
          ),
        ),
        error: (e, _) => SliverFillRemaining(
          child: SearchErrorState(
            message: e.toString(),
            onRetry: () => ref
                .read(jellybotSearchControllerProvider.notifier)
                .search(),
          ),
        ),
      ),
    ];
  }

  Widget _buildAppBar(
    BuildContext context,
    bool floatingAppBar,
    Color surfaceColor,
    AsyncValue<List<IProvider>> providersAsync,
    AsyncValue<List<ISearchFilter>> filtersAsync,
  ) {
    return SliverAppBar(
      floating: !floatingAppBar,
      collapsedHeight: 80,
      automaticallyImplyLeading: false,
      leading: AdaptiveLayout.layoutModeOf(context) == LayoutMode.single
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.router.maybePop(),
            )
          : null,
      pinned: floatingAppBar,
      elevation: 5,
      surfaceTintColor: null,
      shadowColor: Colors.transparent,
      backgroundColor: null,
      titleSpacing: 4,
      flexibleSpace: AdaptiveLayout.layoutModeOf(context) != LayoutMode.dual
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    surfaceColor.withValues(alpha: 0.8),
                    surfaceColor.withValues(alpha: 0.75),
                    surfaceColor.withValues(alpha: 0.5),
                    surfaceColor.withValues(alpha: 0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            )
          : null,
      title: _buildSearchBar(context),
      bottom: PreferredSize(
        preferredSize: const Size(0, 50),
        child: Transform.translate(
          offset: Offset(0, AdaptiveLayout.of(context).isDesktop ? -20 : -15),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            scrollDirection: Axis.horizontal,
            child: _buildFilterChips(context, providersAsync, filtersAsync),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: FladderTheme.smallShape.borderRadius,
      ),
      shadowColor: Colors.transparent,
      child: OutlinedTextField(
        controller: _searchController,
        placeHolder: '${context.localized.search}...',
        onSubmitted: (_) {
          final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
          ctrl.setQuery(_searchController.text);
          ctrl.search();
        },
        decoration: InputDecoration(
          hintText: '${context.localized.search}...',
          prefixIcon: const Icon(IconsaxPlusLinear.search_normal),
          contentPadding: const EdgeInsets.only(top: 13),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    ref.read(jellybotSearchControllerProvider.notifier)
                      ..setQuery('')
                      ..clearResults();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear),
                )
              : IconButton(
                  onPressed: () {
                    final ctrl =
                        ref.read(jellybotSearchControllerProvider.notifier);
                    ctrl.setQuery(_searchController.text);
                    ctrl.search();
                  },
                  icon: const Icon(IconsaxPlusLinear.arrow_right_3),
                ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    AsyncValue<List<IProvider>> providersAsync,
    AsyncValue<List<ISearchFilter>> filtersAsync,
  ) {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    final state = ctrl.searchState;
    final providers = providersAsync.valueOrNull ?? const <IProvider>[];
    final filters = filtersAsync.valueOrNull ?? const <ISearchFilter>[];

    if (state.provider == null && providers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ctrl.setProvider(providers.first);
        setState(() {});
      });
    }

    return Row(
      spacing: 4,
      children: [
        if (providers.isNotEmpty)
          PositionProvider(
            position: PositionContext.first,
            child: ExpressiveButton(
              isSelected: state.provider != null,
              icon: const Icon(IconsaxPlusLinear.global),
              label: Row(
                spacing: 6,
                children: [
                  Text(state.provider?.displayName ??
                      state.provider?.name ??
                      context.localized.jellybotProvider),
                  const Icon(IconsaxPlusLinear.arrow_down, size: 16),
                ],
              ),
              onPressed: () => _showProviderPicker(context, providers),
            ),
          ),
        ..._buildCategoryChips(context, providers.isEmpty),
        ...filters.map((filter) => _buildFilterChip(context, filter)),
        PositionProvider(
          position: PositionContext.last,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ExpressiveButton(
                isSelected: _showAdvanced || state.activeFilterCount > 0,
                icon: const Icon(IconsaxPlusLinear.setting_4),
                label: Text(context.localized.jellybotAdvancedSearch),
                onPressed: () =>
                    setState(() => _showAdvanced = !_showAdvanced),
              ),
              if (state.activeFilterCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: _CountBadge(count: state.activeFilterCount),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCategoryChips(BuildContext context, bool noProviders) {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    final state = ctrl.searchState;
    final defs = [
      (
        MediaCategory.movie,
        context.localized.jellybotMovie,
        IconsaxPlusBold.video_play,
      ),
      (
        MediaCategory.show,
        context.localized.jellybotShow,
        IconsaxPlusBold.monitor,
      ),
      (
        MediaCategory.anime,
        context.localized.jellybotAnime,
        IconsaxPlusBold.star,
      ),
    ];
    return defs.asMap().entries.map((e) {
      final i = e.key;
      final (category, label, selectedIcon) = e.value;
      final isSelected = state.category == category;
      final position = noProviders && i == 0
          ? PositionContext.first
          : PositionContext.middle;
      return PositionProvider(
        position: position,
        child: ExpressiveButton(
          isSelected: isSelected,
          icon: isSelected ? Icon(selectedIcon) : null,
          label: Text(label),
          onPressed: () {
            // setCategory triggers _maybeAutoSearch internally.
            ctrl.setCategory(category);
            setState(() {});
          },
        ),
      );
    }).toList();
  }

  Widget _buildFilterChip(BuildContext context, ISearchFilter filter) {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    final state = ctrl.searchState;
    final isSelected = state.selectedFilters.containsKey(filter.name);
    return PositionProvider(
      position: PositionContext.middle,
      child: ExpressiveButton(
        isSelected: isSelected,
        icon: isSelected ? const Icon(IconsaxPlusBold.filter_tick) : null,
        label: Row(
          spacing: 6,
          children: [
            Text(isSelected
                ? state.selectedFilters[filter.name] ??
                    filter.label ??
                    filter.name ??
                    ''
                : filter.label ?? filter.name ?? ''),
            const Icon(IconsaxPlusLinear.arrow_down, size: 16),
          ],
        ),
        onPressed: () => _showFilterPicker(context, filter),
      ),
    );
  }

  void _showProviderPicker(BuildContext context, List<IProvider> providers) {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    final state = ctrl.searchState;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotProvider),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: providers.length,
            itemBuilder: (context, index) {
              final provider = providers[index];
              final isSelected = state.provider?.id == provider.id;
              return ListTile(
                leading: isSelected
                    ? Icon(
                        IconsaxPlusBold.tick_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : const Icon(IconsaxPlusLinear.global),
                title: Text(
                  provider.displayName ?? provider.name ?? 'Unknown',
                ),
                selected: isSelected,
                onTap: () {
                  Navigator.pop(context);
                  // setProvider auto-searches if there is a query; otherwise no-op.
                  ctrl.setProvider(provider);
                  setState(() {});
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showFilterPicker(BuildContext context, ISearchFilter filter) {
    final ctrl = ref.read(jellybotSearchControllerProvider.notifier);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(filter.label ?? filter.name ?? ''),
        content: SizedBox(
          width: 300,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: !ctrl.searchState.selectedFilters
                        .containsKey(filter.name)
                    ? Icon(
                        IconsaxPlusBold.tick_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : const Icon(IconsaxPlusLinear.filter_remove),
                title: Text(context.localized.all),
                selected:
                    !ctrl.searchState.selectedFilters.containsKey(filter.name),
                onTap: () {
                  Navigator.pop(context);
                  final next = Map<String, String>.from(
                      ctrl.searchState.selectedFilters)
                    ..remove(filter.name);
                  ctrl.setSelectedFilters(next);
                  setState(() {});
                },
              ),
              const Divider(),
              ...?filter.options?.map((option) {
                final isSelected =
                    ctrl.searchState.selectedFilters[filter.name] ==
                        option.$value;
                return ListTile(
                  leading: isSelected
                      ? Icon(
                          IconsaxPlusBold.tick_circle,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  title: Text(option.label ?? option.$value ?? ''),
                  selected: isSelected,
                  onTap: () {
                    Navigator.pop(context);
                    final next = Map<String, String>.from(
                        ctrl.searchState.selectedFilters);
                    next[filter.name ?? ''] = option.$value ?? '';
                    ctrl.setSelectedFilters(next);
                    setState(() {});
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToCrawlLinks(ProviderSearchItemDto item) async {
    if (_addingItemUrl != null) return;
    setState(() => _addingItemUrl = item.url);
    try {
      final api = ref.read(jellybotApiProvider);
      final user = ref.read(userProvider);
      final category =
          ref.read(jellybotSearchControllerProvider.notifier).searchState.category;

      final response = await api.apiCrawlLinksPost(
        body: ExtractMediaRequest(
          url: item.url,
          mediaCategory: category,
          userId: user?.id,
          userName: user?.name,
        ),
      );

      if (!mounted) return;
      if (response.statusCode == 400) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotLinkAlreadyExists)),
        );
        return;
      }
      if (!response.isSuccessful || response.body == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotErrorAddingLink)),
        );
        return;
      }

      var responseToCheck = response.body!;
      CrawlLinkDto? crawlLink;

      if (responseToCheck.requiresSeasonSelection == true &&
          responseToCheck.availableSeasons != null &&
          responseToCheck.availableSeasons! > 0) {
        final selectedSeason = await showDialog<int>(
          context: context,
          builder: (context) => SeasonPickerDialog(
            mediaTitle: responseToCheck.mediaTitle ?? item.title ?? '',
            availableSeasons: responseToCheck.availableSeasons!,
            thumbnailUrl: item.thumbnailUrl,
          ),
        );
        if (selectedSeason == null || !mounted) return;

        final seasonResponse = await api.apiCrawlLinksSelectSeasonPost(
          body: SelectSeasonRequest(
            url: responseToCheck.originalUrl ?? item.url,
            season: selectedSeason,
            userName: user?.name,
            userId: user?.id,
            mediaCategory: category,
          ),
        );
        if (!seasonResponse.isSuccessful || seasonResponse.body == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.localized.jellybotErrorAddingLink)),
            );
          }
          return;
        }
        responseToCheck = seasonResponse.body!;
      }

      if (responseToCheck.crawlLink != null) {
        crawlLink = CrawlLinkDto.fromJson(
          responseToCheck.crawlLink as Map<String, dynamic>,
        );
      }

      if (responseToCheck.mediaExistsOnServer == true &&
          responseToCheck.existingMedia != null) {
        final existingMedia = MediaSearchResultDto.fromJson(
          responseToCheck.existingMedia as Map<String, dynamic>,
        );
        final isDifferent = await showDialog<bool>(
          context: context,
          builder: (context) => ExistingMediaDialog(
            existingMedia: existingMedia,
            addedLinkTitle: responseToCheck.mediaTitle ?? item.title ?? '',
          ),
        );
        if (isDifferent == null) {
          await _deleteCrawlLink(api, crawlLink?.id);
          return;
        }
        if (isDifferent == false) {
          await _deleteCrawlLink(api, crawlLink?.id);
          if (mounted) {
            _navigateToExistingMedia(existingMedia);
          }
          return;
        }
      }

      if (crawlLink == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotErrorAddingLink)),
          );
        }
        return;
      }

      final result = await showDialog<ConfirmDialogResult>(
        context: context,
        builder: (context) => ConfirmCrawlLinkDialog(crawlLink: crawlLink!),
      );
      if (result != null && result.confirmed) {
        await api.apiCrawlLinksConfirmAddPost(
          body: ExtractMediaConfirmationRequest(
            crawlLinkId: crawlLink.id,
            mediaTitle: result.editedName,
          ),
        );
        ref.invalidate(addedCrawlLinkUrlsProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotLinkAdded)),
          );
        }
      } else {
        await _deleteCrawlLink(api, crawlLink.id);
      }
    } catch (e) {
      debugPrint('Error adding to crawl links: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotErrorAddingLink)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _addingItemUrl = null);
      }
    }
  }

  void _navigateToExistingMedia(MediaSearchResultDto existingMedia) {
    if (existingMedia.id == null) return;
    context.router.push(DetailsRoute(id: existingMedia.id!.replaceAll('-', '')));
  }

  Future<void> _deleteCrawlLink(Jellybot api, String? crawlLinkId) async {
    if (crawlLinkId == null) return;
    try {
      await api.apiCrawlLinksDelete(id: crawlLinkId);
    } catch (e) {
      debugPrint('Error deleting crawl link: $e');
    }
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final void Function(int) onJump;

  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                icon: const Icon(Icons.chevron_left),
                onPressed:
                    currentPage > 0 ? () => onJump(currentPage - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${currentPage + 1} / $totalPages',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton.filled(
                icon: const Icon(Icons.chevron_right),
                onPressed: currentPage < totalPages - 1
                    ? () => onJump(currentPage + 1)
                    : null,
              ),
            ],
          ),
          if (totalCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.localized.jellybotResultsCount(totalCount),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

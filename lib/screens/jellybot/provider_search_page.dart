import 'package:auto_route/auto_route.dart';
import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/button_group.dart';
import 'package:fladder/widgets/shared/fladder_scrollbar.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

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

  List<IProvider> _providers = [];
  IProvider? _selectedProvider;
  MediaCategory _selectedCategory = MediaCategory.movie;
  List<ISearchFilter> _filters = [];
  Map<String, String> _selectedFilters = {};
  List<ProviderSearchItemDto> _searchResults = [];
  bool _isLoading = false;
  bool _isSearching = false;
  int _currentPage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProviders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiProvidersGet(searchEnabled: true);
      if (response.isSuccessful && response.body != null) {
        setState(() {
          _providers = response.body!;
          if (_providers.isNotEmpty) {
            _selectedProvider = _providers.first;
            _loadFilters();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading providers: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFilters() async {
    if (_selectedProvider == null) return;
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiProvidersProviderIdSearchFiltersGet(
        providerId: _selectedProvider!.id,
        mediaCategory: _selectedCategory,
      );
      if (response.isSuccessful && response.body != null) {
        setState(() {
          _filters = response.body!;
          _selectedFilters = {};
        });
      }
    } catch (e) {
      debugPrint('Error loading filters: $e');
    }
  }

  Future<void> _search({int page = 0}) async {
    if (_selectedProvider == null || _searchController.text.isEmpty) return;
    setState(() => _isSearching = true);
    try {
      final api = ref.read(jellybotApiProvider);
      final filters = _selectedFilters.entries
          .map((e) => SearchFilter(name: e.key, $value: e.value))
          .toList();

      final response = await api.apiProvidersProviderIdSearchPost(
        providerId: _selectedProvider!.id,
        body: ApiMediaSearchRequest(
          query: _searchController.text,
          category: _selectedCategory,
          page: page,
          pageSize: 20,
          filters: filters,
        ),
      );
      if (response.isSuccessful && response.body != null) {
        setState(() {
          _searchResults = response.body!.items ?? [];
          _currentPage = response.body!.currentPage ?? 0;
          _totalPages = response.body!.totalPages ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error searching: $e');
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final floatingAppBar =
        AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;

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
                await _loadProviders();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: !floatingAppBar,
                    collapsedHeight: 80,
                    automaticallyImplyLeading: false,
                    leading: AdaptiveLayout.layoutModeOf(context) == LayoutMode.single
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.router.maybePop(),
                          )
                        : null,
                    primary: true,
                    pinned: floatingAppBar,
                    elevation: 5,
                    surfaceTintColor: null,
                    shadowColor: Colors.transparent,
                    backgroundColor: null,
                    titleSpacing: 4,
                    flexibleSpace:
                        AdaptiveLayout.layoutModeOf(context) != LayoutMode.dual
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
                        offset: Offset(0,
                            AdaptiveLayout.of(context).isDesktop ? -20 : -15),
                        child: IgnorePointer(
                          ignoring: _isLoading,
                          child: Opacity(
                            opacity: _isLoading ? 0.5 : 1,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              scrollDirection: Axis.horizontal,
                              child: _buildFilterChips(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Loading indicator
                  if (_isLoading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  // Search results
                  else if (_isSearching)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_searchResults.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = _searchResults[index];
                            return _SearchResultCard(
                              item: item,
                              onAdd: () => _addToCrawlLinks(item),
                            );
                          },
                          childCount: _searchResults.length,
                        ),
                      ),
                    ),
                    // Pagination
                    if (_totalPages > 1)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton.filled(
                                icon: const Icon(Icons.chevron_left),
                                onPressed: _currentPage > 0
                                    ? () => _search(page: _currentPage - 1)
                                    : null,
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  '${_currentPage + 1} / $_totalPages',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton.filled(
                                icon: const Icon(Icons.chevron_right),
                                onPressed: _currentPage < _totalPages - 1
                                    ? () => _search(page: _currentPage + 1)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ] else if (_searchController.text.isNotEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              IconsaxPlusLinear.search_status,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.localized.noResultsFound,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              IconsaxPlusLinear.search_normal,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.localized.search,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 80),
                  ),
                ],
              ),
            ),
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
        onSubmitted: (_) => _search(),
        decoration: InputDecoration(
          hintText: '${context.localized.search}...',
          prefixIcon: const Icon(IconsaxPlusLinear.search_normal),
          contentPadding: const EdgeInsets.only(top: 13),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                    });
                  },
                  icon: const Icon(Icons.clear),
                )
              : IconButton(
                  onPressed: () => _search(),
                  icon: const Icon(IconsaxPlusLinear.arrow_right_3),
                ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final categoryChips = [
      _FilterChipData(
        label: context.localized.jellybotMovie,
        icon: IconsaxPlusLinear.video_play,
        selectedIcon: IconsaxPlusBold.video_play,
        value: MediaCategory.movie,
      ),
      _FilterChipData(
        label: context.localized.jellybotShow,
        icon: IconsaxPlusLinear.monitor,
        selectedIcon: IconsaxPlusBold.monitor,
        value: MediaCategory.show,
      ),
      _FilterChipData(
        label: context.localized.jellybotAnime,
        icon: IconsaxPlusLinear.star,
        selectedIcon: IconsaxPlusBold.star,
        value: MediaCategory.anime,
      ),
    ];

    return Row(
      spacing: 4,
      children: [
        // Provider selector
        if (_providers.isNotEmpty)
          PositionProvider(
            position: PositionContext.first,
            child: ExpressiveButton(
              isSelected: _selectedProvider != null,
              icon: const Icon(IconsaxPlusLinear.global),
              label: Row(
                spacing: 6,
                children: [
                  Text(_selectedProvider?.displayName ??
                      _selectedProvider?.name ??
                      context.localized.jellybotProvider),
                  const Icon(IconsaxPlusLinear.arrow_down, size: 16),
                ],
              ),
              onPressed: () => _showProviderPicker(context),
            ),
          ),
        // Category chips
        ...categoryChips.asMap().entries.map((entry) {
          final index = entry.key;
          final chip = entry.value;
          final isSelected = _selectedCategory == chip.value;
          final position = _providers.isEmpty && index == 0
              ? PositionContext.first
              : (index == categoryChips.length - 1 && _filters.isEmpty
                  ? PositionContext.last
                  : PositionContext.middle);

          return PositionProvider(
            position: position,
            child: ExpressiveButton(
              isSelected: isSelected,
              icon: isSelected ? Icon(chip.selectedIcon) : null,
              label: Text(chip.label),
              onPressed: () {
                setState(() {
                  _selectedCategory = chip.value;
                  _searchResults = [];
                });
                _loadFilters();
              },
            ),
          );
        }),
        // Dynamic filters
        ..._filters.asMap().entries.map((entry) {
          final index = entry.key;
          final filter = entry.value;
          final isSelected = _selectedFilters.containsKey(filter.name);
          final position = index == _filters.length - 1
              ? PositionContext.last
              : PositionContext.middle;

          return PositionProvider(
            position: position,
            child: ExpressiveButton(
              isSelected: isSelected,
              icon: isSelected ? const Icon(IconsaxPlusBold.filter_tick) : null,
              label: Row(
                spacing: 6,
                children: [
                  Text(isSelected
                      ? _selectedFilters[filter.name] ??
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
        }),
      ],
    );
  }

  void _showProviderPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotProvider),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _providers.length,
            itemBuilder: (context, index) {
              final provider = _providers[index];
              final isSelected = _selectedProvider?.id == provider.id;
              return ListTile(
                leading: isSelected
                    ? Icon(IconsaxPlusBold.tick_circle,
                        color: Theme.of(context).colorScheme.primary)
                    : const Icon(IconsaxPlusLinear.global),
                title: Text(provider.displayName ?? provider.name ?? 'Unknown'),
                selected: isSelected,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedProvider = provider;
                    _searchResults = [];
                  });
                  _loadFilters();
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showFilterPicker(BuildContext context, ISearchFilter filter) {
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
                leading: !_selectedFilters.containsKey(filter.name)
                    ? Icon(IconsaxPlusBold.tick_circle,
                        color: Theme.of(context).colorScheme.primary)
                    : const Icon(IconsaxPlusLinear.filter_remove),
                title: Text(context.localized.all),
                selected: !_selectedFilters.containsKey(filter.name),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedFilters.remove(filter.name);
                  });
                },
              ),
              const Divider(),
              ...?filter.options?.map((option) {
                final isSelected =
                    _selectedFilters[filter.name] == option.$value;
                return ListTile(
                  leading: isSelected
                      ? Icon(IconsaxPlusBold.tick_circle,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  title: Text(option.label ?? option.$value ?? ''),
                  selected: isSelected,
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedFilters[filter.name ?? ''] = option.$value ?? '';
                    });
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
    try {
      final api = ref.read(jellybotApiProvider);
      final user = ref.read(userProvider);
      final response = await api.apiCrawlLinksPost(
        body: ExtractMediaRequest(
          url: item.url,
          mediaCategory: _selectedCategory,
          userId: user?.id,
          userName: user?.name,
        ),
      );

      if (response.isSuccessful && response.body != null && mounted) {
        final extractResponse = response.body!;
        CrawlLinkDto? crawlLink;

        // Check if season selection is required
        if (extractResponse.requiresSeasonSelection == true &&
            extractResponse.availableSeasons != null &&
            extractResponse.availableSeasons! > 0) {
          final selectedSeason = await showDialog<int>(
            context: context,
            builder: (context) => _SeasonPickerDialog(
              mediaTitle: extractResponse.mediaTitle ?? item.title ?? '',
              availableSeasons: extractResponse.availableSeasons!,
            ),
          );

          if (selectedSeason == null || !mounted) return;

          final seasonResponse = await api.apiCrawlLinksSelectSeasonPost(
            body: SelectSeasonRequest(
              url: extractResponse.originalUrl ?? item.url,
              season: selectedSeason,
              userName: user?.name,
              userId: user?.id,
              mediaCategory: _selectedCategory,
            ),
          );

          if (seasonResponse.isSuccessful && seasonResponse.body != null) {
            crawlLink = seasonResponse.body!;
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(context.localized.jellybotErrorAddingLink)),
              );
            }
            return;
          }
        } else {
          // crawlLink comes as dynamic (Map) from the API, need to deserialize
          if (extractResponse.crawlLink != null) {
            crawlLink = CrawlLinkDto.fromJson(
                extractResponse.crawlLink as Map<String, dynamic>);
          }
        }

        if (crawlLink == null || !mounted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(context.localized.jellybotErrorAddingLink)),
            );
          }
          return;
        }

        final result = await showDialog<_ConfirmDialogResult>(
          context: context,
          builder: (context) => _ConfirmCrawlLinkDialog(crawlLink: crawlLink!),
        );
        if (result != null && result.confirmed) {
          await api.apiCrawlLinksConfirmAddPost(
            body: ExtractMediaConfirmationRequest(
              crawlLinkId: crawlLink.id,
              mediaTitle: result.editedName,
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.localized.jellybotLinkAdded)),
            );
          }
        }
      } else if (response.statusCode == 400 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotLinkAlreadyExists)),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotErrorAddingLink)),
        );
      }
    } catch (e) {
      debugPrint('Error adding to crawl links: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotErrorAddingLink)),
        );
      }
    }
  }
}

class _SeasonPickerDialog extends StatelessWidget {
  final String mediaTitle;
  final int availableSeasons;

  const _SeasonPickerDialog({
    required this.mediaTitle,
    required this.availableSeasons,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.localized.jellybotSelectSeason),
      content: SizedBox(
        width: 300,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: availableSeasons,
          itemBuilder: (context, index) {
            final season = index + 1;
            return ListTile(
              leading: const Icon(IconsaxPlusLinear.video_play),
              title: Text('${context.localized.season(1)} $season'),
              onTap: () => Navigator.pop(context, season),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.localized.cancel),
        ),
      ],
    );
  }
}

class _FilterChipData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final MediaCategory value;

  const _FilterChipData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.value,
  });
}

class _SearchResultCard extends StatelessWidget {
  final ProviderSearchItemDto item;
  final VoidCallback onAdd;

  const _SearchResultCard({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.thumbnailUrl != null
                    ? Image.network(
                        item.thumbnailUrl!,
                        width: 80,
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 80,
                          height: 120,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: const Icon(IconsaxPlusLinear.video_play,
                              size: 32),
                        ),
                      )
                    : Container(
                        width: 80,
                        height: 120,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child:
                            const Icon(IconsaxPlusLinear.video_play, size: 32),
                      ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? 'Unknown',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Add button
              IconButton.filled(
                onPressed: onAdd,
                icon: const Icon(IconsaxPlusLinear.add),
                tooltip: context.localized.add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialogResult {
  final bool confirmed;
  final String? editedName;

  const _ConfirmDialogResult({required this.confirmed, this.editedName});
}

class _ConfirmCrawlLinkDialog extends StatefulWidget {
  final CrawlLinkDto crawlLink;

  const _ConfirmCrawlLinkDialog({required this.crawlLink});

  @override
  State<_ConfirmCrawlLinkDialog> createState() =>
      _ConfirmCrawlLinkDialogState();
}

class _ConfirmCrawlLinkDialogState extends State<_ConfirmCrawlLinkDialog> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.crawlLink.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final originalName = widget.crawlLink.name ?? '';
    final editedName = _nameController.text.trim();
    Navigator.pop(
      context,
      _ConfirmDialogResult(
        confirmed: true,
        editedName: editedName != originalName ? editedName : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.localized.jellybotConfirmAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: context.localized.name,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.crawlLink.season != null)
            Text('${context.localized.season(1)}: ${widget.crawlLink.season}'),
          if (widget.crawlLink.quality != null)
            Text('${context.localized.quality}: ${widget.crawlLink.quality}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(context.localized.cancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(context.localized.confirm),
        ),
      ],
    );
  }
}

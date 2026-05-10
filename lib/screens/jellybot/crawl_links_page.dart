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

enum _CrawlLinkFilter { all, pending, downloaded, hasError }

/// `CrawlLinkDto.provider` is typed as `dynamic` in the generated swagger
/// client (the OpenAPI `oneOf` shape doesn't yield a strong type), so at
/// runtime it comes back as a `Map<String, dynamic>` from JSON
/// deserialization. Reaching for `.displayName` directly on a `Map` throws
/// `NoSuchMethodError`. This helper handles both shapes defensively.
String? _providerDisplayName(CrawlLinkDto link) {
  final raw = link.provider;
  if (raw == null) return null;
  if (raw is Map) {
    final name = raw['displayName'] ?? raw['name'];
    return name is String && name.isNotEmpty ? name : null;
  }
  if (raw is ProviderDto) {
    return raw.displayName ?? raw.name;
  }
  return null;
}

@RoutePage()
class JellybotCrawlLinksPage extends ConsumerStatefulWidget {
  const JellybotCrawlLinksPage({super.key});

  @override
  ConsumerState<JellybotCrawlLinksPage> createState() =>
      _JellybotCrawlLinksPageState();
}

class _JellybotCrawlLinksPageState
    extends ConsumerState<JellybotCrawlLinksPage> {
  final _scrollController = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  final _searchController = TextEditingController();

  List<CrawlLinkDto> _crawlLinks = [];
  bool _isLoading = false;
  int _currentPage = 0;
  int _totalPages = 0;
  _CrawlLinkFilter _selectedFilter = _CrawlLinkFilter.all;
  static const int _pageSize = 25;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCrawlLinks();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<CrawlLinkDto> get _filteredLinks {
    var links = _crawlLinks;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      links = links
          .where((l) => (l.name ?? '').toLowerCase().contains(query))
          .toList();
    }

    // Apply status filter
    switch (_selectedFilter) {
      case _CrawlLinkFilter.pending:
        return links
            .where((l) => l.downloaded != true && l.hasError != true)
            .toList();
      case _CrawlLinkFilter.downloaded:
        return links.where((l) => l.downloaded == true).toList();
      case _CrawlLinkFilter.hasError:
        return links.where((l) => l.hasError == true).toList();
      case _CrawlLinkFilter.all:
        return links;
    }
  }

  Future<void> _loadCrawlLinks({int page = 0}) async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksGet(page: page, limit: _pageSize);
      if (response.isSuccessful && response.body != null) {
        setState(() {
          _crawlLinks = response.body!.items ?? [];
          _currentPage = response.body!.currentPage ?? 0;
          _totalPages = response.body!.totalPages ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading crawl links: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCrawlLink(CrawlLinkDto link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotDeleteLink),
        content: Text(context.localized
            .jellybotDeleteLinkConfirm(link.name ?? 'Unknown')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.localized.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksDelete(id: link.mediaId);
      if (response.isSuccessful) {
        _loadCrawlLinks(page: _currentPage);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotLinkDeleted)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting crawl link: $e');
    }
  }

  Future<void> _renameCrawlLink(CrawlLinkDto link) async {
    final controller = TextEditingController(text: link.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotRenameLink),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: context.localized.name,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(context.localized.save),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newName == null || newName.isEmpty || newName == link.name) return;

    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiCrawlLinksCrawlLinkIdRenamePut(
        crawlLinkId: link.mediaId,
        body: RenameCrawlLinkRequest(newName: newName),
      );
      if (response.isSuccessful) {
        _loadCrawlLinks(page: _currentPage);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotLinkRenamed)),
          );
        }
      }
    } catch (e) {
      debugPrint('Error renaming crawl link: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(userProvider
        .select((value) => value?.policy?.isAdministrator ?? false));

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.lock,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                context.localized.adminOnly,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final floatingAppBar =
        AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;
    final filteredLinks = _filteredLinks;

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
                await _loadCrawlLinks();
              },
              child: (context) => CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: !floatingAppBar,
                    collapsedHeight: 80,
                    automaticallyImplyLeading: false,
                    leading: AdaptiveLayout.layoutModeOf(context) ==
                            LayoutMode.single
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.router.maybePop(),
                          )
                        : null,
                    primary: true,
                    pinned: floatingAppBar,
                    elevation: 5,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
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
                  else if (filteredLinks.isNotEmpty) ...[
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final link = filteredLinks[index];
                            return _CrawlLinkCard(
                              link: link,
                              onDelete: () => _deleteCrawlLink(link),
                              onRename: () => _renameCrawlLink(link),
                            );
                          },
                          childCount: filteredLinks.length,
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
                                    ? () =>
                                        _loadCrawlLinks(page: _currentPage - 1)
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
                                    ? () =>
                                        _loadCrawlLinks(page: _currentPage + 1)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ] else
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              IconsaxPlusLinear.link_21,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.localized.jellybotNoCrawlLinks,
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
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '${context.localized.search}...',
          prefixIcon: const Icon(IconsaxPlusLinear.search_normal),
          contentPadding: const EdgeInsets.only(top: 13),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.clear),
                )
              : null,
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final filterChips = [
      _FilterChipData(
        label: context.localized.all,
        icon: IconsaxPlusLinear.category,
        selectedIcon: IconsaxPlusBold.category,
        value: _CrawlLinkFilter.all,
      ),
      _FilterChipData(
        label: context.localized.jellybotPending,
        icon: IconsaxPlusLinear.timer_1,
        selectedIcon: IconsaxPlusBold.timer_1,
        value: _CrawlLinkFilter.pending,
      ),
      _FilterChipData(
        label: context.localized.jellybotCompleted,
        icon: IconsaxPlusLinear.tick_circle,
        selectedIcon: IconsaxPlusBold.tick_circle,
        value: _CrawlLinkFilter.downloaded,
      ),
      _FilterChipData(
        label: context.localized.jellybotError,
        icon: IconsaxPlusLinear.danger,
        selectedIcon: IconsaxPlusBold.danger,
        value: _CrawlLinkFilter.hasError,
      ),
    ];

    return Row(
      spacing: 4,
      children: filterChips.asMap().entries.map((entry) {
        final index = entry.key;
        final chip = entry.value;
        final isSelected = _selectedFilter == chip.value;
        final position = index == 0
            ? PositionContext.first
            : (index == filterChips.length - 1
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
                _selectedFilter = chip.value;
              });
            },
          ),
        );
      }).toList(),
    );
  }
}

class _FilterChipData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final _CrawlLinkFilter value;

  const _FilterChipData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.value,
  });
}

class _CrawlLinkCard extends StatelessWidget {
  final CrawlLinkDto link;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  const _CrawlLinkCard({
    required this.link,
    required this.onDelete,
    required this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = link.hasError ?? false;
    final downloaded = link.downloaded ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Could navigate to details
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: link.thumbnailUrl != null
                    ? Image.network(
                        link.thumbnailUrl!,
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
                      link.name ?? 'Unknown',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (_providerDisplayName(link) != null)
                      Text(
                        _providerDisplayName(link)!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (link.season != null)
                          Chip(
                            label: Text('S${link.season}'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        if (link.quality != null)
                          Chip(
                            label: Text(link.quality!),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: downloaded
                                ? Colors.green.withValues(alpha: 0.2)
                                : (hasError
                                    ? Colors.red.withValues(alpha: 0.2)
                                    : Colors.orange.withValues(alpha: 0.2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                downloaded
                                    ? IconsaxPlusBold.tick_circle
                                    : (hasError
                                        ? IconsaxPlusBold.danger
                                        : IconsaxPlusBold.timer_1),
                                size: 14,
                                color: downloaded
                                    ? Colors.green
                                    : (hasError ? Colors.red : Colors.orange),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                downloaded
                                    ? context.localized.jellybotCompleted
                                    : (hasError
                                        ? context.localized.jellybotError
                                        : context.localized.jellybotPending),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: downloaded
                                      ? Colors.green
                                      : (hasError ? Colors.red : Colors.orange),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: onRename,
                    child: Row(
                      children: [
                        const Icon(IconsaxPlusLinear.edit),
                        const SizedBox(width: 8),
                        Text(context.localized.rename),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: onDelete,
                    child: Row(
                      children: [
                        Icon(IconsaxPlusLinear.trash,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Text(context.localized.delete,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

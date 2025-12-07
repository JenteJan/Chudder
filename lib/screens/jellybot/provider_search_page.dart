import 'package:auto_route/annotations.dart';
import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    _loadProviders();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    return SettingsScaffold(
      label: context.localized.jellybotProviderSearch,
      items: [
        if (_isLoading)
          const Center(
              child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else ...[
          // Provider selection
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<IProvider>(
              value: _selectedProvider,
              decoration: InputDecoration(
                labelText: context.localized.jellybotProvider,
                border: const OutlineInputBorder(),
              ),
              items: _providers
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.displayName ?? p.name ?? 'Unknown'),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedProvider = value;
                  _searchResults = [];
                });
                _loadFilters();
              },
            ),
          ),
          // Category selection
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<MediaCategory>(
              segments: [
                ButtonSegment(
                    value: MediaCategory.movie,
                    label: Text(context.localized.jellybotMovie)),
                ButtonSegment(
                    value: MediaCategory.show,
                    label: Text(context.localized.jellybotShow)),
                ButtonSegment(
                    value: MediaCategory.anime,
                    label: Text(context.localized.jellybotAnime)),
              ],
              selected: {_selectedCategory},
              onSelectionChanged: (value) {
                setState(() {
                  _selectedCategory = value.first;
                  _searchResults = [];
                });
                _loadFilters();
              },
            ),
          ),
          const SizedBox(height: 16),
          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: context.localized.search,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _search(),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          // Filters
          if (_filters.isNotEmpty) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _filters
                    .map((filter) => SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            value: _selectedFilters[filter.name],
                            decoration: InputDecoration(
                              labelText: filter.label,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem(
                                  value: null,
                                  child: Text(context.localized.all)),
                              ...?filter.options?.map((o) => DropdownMenuItem(
                                    value: o.$value,
                                    child: Text(o.label ?? o.$value ?? ''),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                if (value == null) {
                                  _selectedFilters.remove(filter.name);
                                } else {
                                  _selectedFilters[filter.name ?? ''] = value;
                                }
                              });
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Results
          if (_isSearching)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else if (_searchResults.isNotEmpty) ...[
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                return _SearchResultTile(
                  item: item,
                  onAdd: () => _addToCrawlLinks(item),
                );
              },
            ),
            // Pagination
            if (_totalPages > 1)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _currentPage > 0
                          ? () => _search(page: _currentPage - 1)
                          : null,
                    ),
                    Text('${_currentPage + 1} / $_totalPages'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _currentPage < _totalPages - 1
                          ? () => _search(page: _currentPage + 1)
                          : null,
                    ),
                  ],
                ),
              ),
          ] else if (_searchController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(child: Text(context.localized.noResultsFound)),
            ),
        ],
      ],
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
        // Show confirmation dialog to confirm the crawl link
        final result = await showDialog<_ConfirmDialogResult>(
          context: context,
          builder: (context) =>
              _ConfirmCrawlLinkDialog(crawlLink: response.body!),
        );
        if (result != null && result.confirmed) {
          await api.apiCrawlLinksConfirmAddPost(
            body: ExtractMediaConfirmationRequest(
              crawlLinkId: response.body!.id,
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
        // Link already exists
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

class _SearchResultTile extends StatelessWidget {
  final ProviderSearchItemDto item;
  final VoidCallback onAdd;

  const _SearchResultTile({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: item.thumbnailUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.thumbnailUrl!,
                width: 50,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 50),
              ),
            )
          : const Icon(Icons.movie, size: 50),
      title: Text(item.title ?? 'Unknown'),
      subtitle: item.description != null
          ? Text(item.description!,
              maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: IconButton(
        icon: const Icon(Icons.add),
        onPressed: onAdd,
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
          onPressed: () {
            final originalName = widget.crawlLink.name ?? '';
            final editedName = _nameController.text.trim();
            Navigator.pop(
              context,
              _ConfirmDialogResult(
                confirmed: true,
                editedName: editedName != originalName ? editedName : null,
              ),
            );
          },
          child: Text(context.localized.confirm),
        ),
      ],
    );
  }
}

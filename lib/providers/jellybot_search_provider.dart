import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/jellybot/jellybot_search_state.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';

part 'jellybot_search_provider.g.dart';

@riverpod
Future<List<IProvider>> jellybotProviders(Ref ref) async {
  final api = ref.watch(jellybotApiProvider);
  final response = await api.apiProvidersGet(searchEnabled: true);
  if (!response.isSuccessful || response.body == null) {
    return const <IProvider>[];
  }
  return response.body!;
}

@riverpod
Future<List<ISearchFilter>> jellybotSearchFilters(
  Ref ref,
  String providerId,
  MediaCategory category,
) async {
  final api = ref.watch(jellybotApiProvider);
  final response = await api.apiProvidersProviderIdSearchFiltersGet(
    providerId: providerId,
    mediaCategory: category,
  );
  if (!response.isSuccessful || response.body == null) {
    return const <ISearchFilter>[];
  }
  return response.body!;
}

/// Set of crawl-link `fullUrl` values currently added by the user — backs the
/// "Already in your library" badge on search-result cards. Paginated through
/// in pages of 200 to avoid huge payloads on libraries with many links.
/// Invalidate after a successful add to refresh the badging.
@Riverpod(keepAlive: true)
Future<Set<String>> addedCrawlLinkUrls(Ref ref) async {
  final api = ref.watch(jellybotApiProvider);
  final urls = <String>{};
  var page = 0;
  while (true) {
    final response = await api.apiCrawlLinksGet(page: page, limit: 200);
    if (!response.isSuccessful || response.body == null) {
      break;
    }
    final body = response.body!;
    for (final item in body.items ?? const <CrawlLinkDto>[]) {
      final url = item.fullUrl;
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    if ((body.currentPage ?? 0) + 1 >= (body.totalPages ?? 0)) break;
    page++;
  }
  return urls;
}

/// Notifier holding the current search-request params (in `_state`) and the
/// search response in its `AsyncValue<PaginatedResponseOfProviderSearchItemDto?>`.
///
/// Filter setters (provider/category/selectedFilters/exactMatch/minScore) call
/// `_maybeAutoSearch` which re-runs the search whenever the query is non-empty.
/// `setQuery` deliberately does NOT auto-search — the search bar uses an
/// explicit submit so we don't fire on every keystroke.
@riverpod
class JellybotSearchController extends _$JellybotSearchController {
  JellybotSearchState _state = const JellybotSearchState();

  JellybotSearchState get searchState => _state;

  @override
  Future<PaginatedResponseOfProviderSearchItemDto?> build() async => null;

  void setProvider(IProvider? provider) {
    _state = _state.copyWith(
      provider: provider,
      page: 0,
      selectedFilters: const {},
    );
    _maybeAutoSearch();
  }

  void setCategory(MediaCategory category) {
    _state = _state.copyWith(
      category: category,
      page: 0,
      selectedFilters: const {},
    );
    _maybeAutoSearch();
  }

  /// No auto-search on query changes — wait for explicit submit so we don't
  /// fire on every keystroke. The page wires `setQuery` immediately followed
  /// by `search()` from its onSubmitted handler.
  void setQuery(String query) {
    _state = _state.copyWith(query: query, page: 0);
  }

  void setSelectedFilters(Map<String, String> filters) {
    _state = _state.copyWith(selectedFilters: filters, page: 0);
    _maybeAutoSearch();
  }

  void toggleExactMatch(bool value) {
    _state = _state.copyWith(exactMatch: value, page: 0);
    _maybeAutoSearch();
  }

  void setMinScore(double? value) {
    _state = _state.copyWith(minScore: value, page: 0);
    _maybeAutoSearch();
  }

  void setPage(int page) {
    _state = _state.copyWith(page: page);
  }

  void clearResults() {
    state = const AsyncValue.data(null);
  }

  /// Re-runs the search when a filter changes, but only if there is a real
  /// query to run. Without this guard we would fire empty searches on
  /// initial mount (when `setProvider` is called from the page's
  /// post-frame callback) and on category/filter pre-selection.
  void _maybeAutoSearch() {
    if (_state.provider == null) return;
    if (_state.query.trim().isEmpty) return;
    search();
  }

  Future<void> search({int? page}) async {
    if (_state.provider == null || _state.query.trim().isEmpty) {
      return;
    }
    if (page != null) {
      _state = _state.copyWith(page: page);
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final api = ref.read(jellybotApiProvider);
      final providerId = _state.provider!.id;
      if (providerId == null) {
        throw StateError('Selected provider has no id');
      }
      final response = await api.apiProvidersProviderIdSearchPost(
        providerId: providerId,
        body: _state.toRequest(),
      );
      if (!response.isSuccessful) {
        throw StateError('Search failed (${response.statusCode})');
      }
      return response.body;
    });
  }
}

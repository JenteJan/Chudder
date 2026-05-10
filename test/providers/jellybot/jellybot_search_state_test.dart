import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/jellybot/jellybot_search_state.dart';
import 'package:fladder/providers/jellybot_search_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure-logic tests for the Jellybot search state and controller mutations.
// HTTP-dependent paths (the actual search() call, the auto-search firing a
// network request) are covered by the manual smoke checklist in the plan,
// matching the convention in test/providers/syncplay/ and test/providers/update_alist/.

void main() {
  group('JellybotSearchState', () {
    test('activeFilterCount counts selectedFilters, exactMatch, minScore', () {
      const empty = JellybotSearchState();
      expect(empty.activeFilterCount, 0);

      final withFilter = empty.copyWith(selectedFilters: {'quality': '1080p'});
      expect(withFilter.activeFilterCount, 1);

      final withExact = withFilter.copyWith(exactMatch: true);
      expect(withExact.activeFilterCount, 2);

      final withScore = withExact.copyWith(minScore: 0.5);
      expect(withScore.activeFilterCount, 3);
    });

    test('toRequest() maps state into ApiMediaSearchRequest', () {
      const state = JellybotSearchState(
        query: 'inception',
        category: MediaCategory.movie,
        exactMatch: true,
        minScore: 0.5,
        page: 2,
        pageSize: 20,
        selectedFilters: {'quality': '1080p'},
      );
      final req = state.toRequest();
      expect(req.query, 'inception');
      expect(req.category, MediaCategory.movie);
      expect(req.exactMatch, true);
      expect(req.minScore, 0.5);
      expect(req.page, 2);
      expect(req.pageSize, 20);
      expect(req.filters, isNotNull);
      expect(req.filters!.length, 1);
      expect(req.filters!.first.name, 'quality');
      expect(req.filters!.first.$value, '1080p');
    });
  });

  group('JellybotSearchController mutations', () {
    test('setCategory resets page and clears selectedFilters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller =
          container.read(jellybotSearchControllerProvider.notifier);

      controller.setSelectedFilters({'quality': '1080p'});
      controller.setPage(3);
      controller.setCategory(MediaCategory.show);

      final s = controller.searchState;
      expect(s.category, MediaCategory.show);
      expect(s.selectedFilters, isEmpty);
      expect(s.page, 0);
    });

    test('setProvider clears selectedFilters and resets page', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller =
          container.read(jellybotSearchControllerProvider.notifier);

      controller.setSelectedFilters({'quality': '1080p'});
      controller.setPage(2);
      controller.setProvider(
        const IProvider(id: 'p1', displayName: 'P', searchEnabled: true),
      );

      final s = controller.searchState;
      expect(s.provider?.id, 'p1');
      expect(s.selectedFilters, isEmpty);
      expect(s.page, 0);
    });

    test('setQuery only updates query and resets page (does not clear filters)',
        () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller =
          container.read(jellybotSearchControllerProvider.notifier);

      controller.setSelectedFilters({'quality': '1080p'});
      controller.setPage(3);
      controller.setQuery('matrix');

      final s = controller.searchState;
      expect(s.query, 'matrix');
      expect(s.page, 0);
      expect(s.selectedFilters, {'quality': '1080p'});
    });

    test(
        'changing a filter with empty query keeps state at AsyncData(null) '
        '(auto-search guard)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller =
          container.read(jellybotSearchControllerProvider.notifier);

      // Await build() to settle to AsyncData(null).
      final initialValue =
          await container.read(jellybotSearchControllerProvider.future);
      expect(initialValue, isNull);

      controller.setProvider(
        const IProvider(id: 'p1', displayName: 'P', searchEnabled: true),
      );
      controller.toggleExactMatch(true);
      controller.setMinScore(0.5);
      controller.setSelectedFilters({'quality': '1080p'});
      controller.setCategory(MediaCategory.show);

      // No auto-search should have run because query is empty:
      // state must still be AsyncData(null) — not AsyncLoading or AsyncError.
      final after = container.read(jellybotSearchControllerProvider);
      expect(
        after,
        isA<AsyncData<PaginatedResponseOfProviderSearchItemDto?>>()
            .having((a) => a.value, 'value', isNull),
      );
    });
  });
}

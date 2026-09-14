import 'dart:developer';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/folder_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/photo_queue_source.dart';
import 'package:chudder/models/items/photos_model.dart';
import 'package:chudder/models/items/playlist_model.dart';
import 'package:chudder/models/library_filter_model.dart';
import 'package:chudder/models/library_filters_model.dart';
import 'package:chudder/models/library_search/library_search_model.dart';
import 'package:chudder/models/library_search/library_search_options.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/library_filters_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/user_data_updates_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/item_base_model/play_item_helpers.dart';
import 'package:chudder/util/list_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/map_bool_helper.dart';
import 'package:chudder/providers/library_index_provider.dart';
import 'package:chudder/util/search_relevance.dart';

final librarySearchProvider =
    StateNotifierProvider.family.autoDispose<LibrarySearchNotifier, LibrarySearchModel, Key>((ref, id) {
  return LibrarySearchNotifier(ref);
});

/// The paging key a Random library pages under: one shuffled list, however
/// many libraries or folders it was made from.
const _randomPagingKey = '__random__';

const _libraryMusicInitialQueueLimit = 5;
const _libraryMusicRefillLimit = 100;
const _libraryPhotoFetchLimit = 100;

class LibrarySearchNotifier extends StateNotifier<LibrarySearchModel> {
  LibrarySearchNotifier(this.ref) : super(const LibrarySearchModel()) {
    // Watched somewhere else, or watched from here and the player closed: the
    // grid marks the poster without asking the server for the page again.
    // See [userDataUpdatesProvider].
    ref.listen(userDataUpdatesProvider, (previous, next) {
      if (next == null) return;
      final onScreen = <String, UserData?>{};
      for (final poster in state.posters) {
        final data = next[poster.id];
        if (data != null) onScreen[poster.id] = data;
      }
      if (onScreen.isNotEmpty) updateMultiUserData(onScreen);
    });
  }

  final Ref ref;

  /// Left unset this used to be 500, and the server had to serialise all of
  /// them before the first poster could draw.
  int get pageSize => ref.read(clientSettingsProvider).libraryPageSize ?? 100;

  LibraryFiltersProvider get filterProvider => libraryFiltersProvider(state.currentIds);

  late final JellyService api = ref.read(jellyApiProvider);

  /// Only a change: nothing on screen reads it, and every write rebuilt the
  /// whole page - twice for nothing on every load, where the load and the page
  /// both said it again.
  set loading(bool loading) {
    if (state.loading != loading) state = state.copyWith(loading: loading);
  }

  bool loadedFilters = false;
  bool wasInitialized = false;

  /// The libraries and folders the page was opened on - what their chips'
  /// clear goes back to. Clearing them to nothing showed nothing at all.
  Map<ViewModel, bool> defaultViews = const {};
  Map<ItemBaseModel, bool> defaultFolderOverwrite = const {};

  /// The kinds the libraries now ticked start with: what the type chip's
  /// clear goes back to, the way the page starts out.
  Map<FladderItemType, bool> get defaultTypes {
    final kinds = state.views.included.expand((view) => view.collectionType.defaultTypes);
    return state.filters.types.setAll(false).setKeys(kinds, true);
  }

  /// Bumped by every refresh. A page that was asked for before the refresh
  /// and arrives after it belongs to a list that no longer exists; without
  /// this it was appended to the new one, with the old paging cursor.
  int _generation = 0;

  /// Every item a Random page shows, in the order it shows them - dealt
  /// once when the page loads and paged through from there.
  ///
  /// The server deals a new order for every request, so paging a Random
  /// sort a hundred at a time showed some titles twice and others never.
  List<String>? _randomOrder;

  bool get loading => state.loading;

  Future<void> initRefresh({
    required List<String> parentIds,
    LibraryFilterModel? filters,
  }) async {
    loading = true;
    _generation++;
    _randomOrder = null;
    state = state.resetLazyLoad();

    // The views round-trip is only needed once: after initialization the
    // result was thrown away, yet every filter toggle still paid for it
    // before a single poster could refresh.
    Future<Map<ViewModel, bool>>? viewsCheck;
    if (!wasInitialized) {
      // The libraries the app already has, when they settle what this page
      // is, rather than a round trip for the same list before the first
      // poster. The server's own list still comes, alongside the page - see
      // [_matchServerViews].
      final known = _knownViews(parentIds);
      if (known != null) viewsCheck = loadViews(parentIds);
      final views = known ?? await loadViews(parentIds);

      final isFolder = views.keys.map((e) => e.id).toList().containsAny(parentIds) == false && parentIds.isNotEmpty;

      if (isFolder) {
        await loadFolders(folderId: parentIds);
        defaultFolderOverwrite = state.folderOverwrite;
      } else {
        state = state.copyWith(views: views);
      }
      defaultViews = views;
    }

    final firstView = state.views.included.firstWhereOrNull((element) => parentIds.contains(element.id) == true);

    final findFavouriteFilter = ref.read(filterProvider).firstWhereOrNull((element) => element.isFavourite);

    final defaultOrFavourite =
        filters?.isDefault == true && findFavouriteFilter != null ? findFavouriteFilter.filter : filters;
    final activeFilter = defaultOrFavourite ?? firstView?.collectionType.defaultFilters ?? const LibraryFilterModel();

    // Don't hold the posters hostage to the genre/studio/year/tag lists:
    // only the very first load with no explicit types needs the filter
    // payload up front (it seeds the type map the item query uses).
    // Everything else can fetch concurrently — the chips appear when ready.
    Future<void> filtersLoad = Future.value();
    if (firstView != null && state.views.isNotEmpty) {
      filtersLoad = loadFilters(activeFilter);
      if (!wasInitialized && activeFilter.types.included.isEmpty && _firstPageNeedsFilterLists(activeFilter)) {
        await filtersLoad;
      }
    }

    if (!wasInitialized) {
      wasInitialized = true;
      state = state.copyWith(
        filters: state.filters.loadModel(activeFilter),
        initialized: true,
      );
    }

    try {
      await loadMore(init: true);
      await filtersLoad;
    } finally {
      // Even when the page or a filter list fails: the server's list is only
      // asked for once in the page's life, and a pull would not ask again.
      if (viewsCheck != null) await _matchServerViews(viewsCheck);
    }

    loading = false;
  }

  /// Whether the first page of [filter] comes out different once the filter
  /// lists are in. Only for three things: no type map at all, which the lists
  /// fill with the libraries' kinds, and a studio or an item filter picked
  /// before the page has the keys to hold it. A genre or favourites link has
  /// none of them, and its posters waited on four lists they never read.
  bool _firstPageNeedsFilterLists(LibraryFilterModel filter) =>
      filter.types.isEmpty ||
      filter.studios.included.isNotEmpty ||
      !filter.itemFilters.included.every(state.filters.itemFilters.containsKey);

  /// The libraries [viewsProvider] already holds, as this page's views, when
  /// they are enough to open it on: online, and either every library (the
  /// Search tab) or holding at least one of [parentIds] - which is also what
  /// tells a library from a folder below. Null when the server has to say.
  Map<ViewModel, bool>? _knownViews(List<String> parentIds) {
    if (ref.read(offlineStateProvider)) return null;
    final known = ref.read(viewsProvider).views;
    if (known.isEmpty) return null;
    if (parentIds.isNotEmpty && !known.any((view) => parentIds.contains(view.id))) return null;
    final selected = known.where((view) => parentIds.contains(view.id)).toSet();
    return {for (final view in known) view: selected.isEmpty || selected.contains(view)};
  }

  /// Brings the libraries the page opened on in line with the server's own
  /// list, once it is in. [viewsProvider] leaves out the kinds of library the
  /// app has no page for while the setting to show them all is off, and can
  /// hold a list remembered from an earlier visit. Nothing changes - and
  /// nothing is asked again - when the two agree, which is nearly always.
  Future<void> _matchServerViews(Future<Map<ViewModel, bool>> fetched) async {
    final server = await fetched;
    if (!mounted || server.isEmpty) return;
    final current = state.views;
    final gone = current.keys.where((view) => !server.containsKey(view)).toSet();
    final missing = {
      for (final entry in server.entries)
        if (!current.containsKey(entry.key)) entry.key: entry.value,
    };
    if (gone.isEmpty && missing.isEmpty) return;
    Map<ViewModel, bool> matched(Map<ViewModel, bool> views) => {
          for (final entry in views.entries)
            if (!gone.contains(entry.key)) entry.key: entry.value,
          ...missing,
        };
    defaultViews = matched(defaultViews);
    state = state.copyWith(views: matched(current));
  }

  Future<void> loadMore({bool? init}) async {
    if ((loading && init != true) || state.allDoneFetching) return;
    loading = true;
    final generation = _generation;

    final newLastIndices = Map<String, int>.from(state.lastIndices);
    final newLibraryItemCounts = Map<String, int>.from(state.libraryItemCounts);
    final isEmpty = newLastIndices.isEmpty;

    /// The next page of one library or folder.
    ///
    /// Only the first page asks the server to count. The count is what says
    /// when paging is done and what the item chip shows, and it does not
    /// change from page to page - but the server runs a count over the whole
    /// query every time it is asked for one.
    Future<ServerQueryResult?> loadPage(String id, int limit, {ViewModel? viewModel}) async {
      final lastIndex = newLastIndices[id];
      final knownCount = newLibraryItemCounts[id];
      if (knownCount != null && lastIndex != null && knownCount <= lastIndex) return null;

      final isFirstPage = lastIndex == null;
      final result = await _loadLibrary(
        viewModel: viewModel,
        id: viewModel == null ? id : null,
        startIndex: lastIndex,
        limit: limit,
        enableTotalRecordCount: isFirstPage,
      );
      if (result == null) return null;

      final fetched = (lastIndex ?? 0) + result.items.length;
      newLastIndices[id] = fetched;
      // A short page is the end, whatever the first count said: a library can
      // lose items while it is being scrolled, and a count nobody can reach
      // would keep asking for pages that come back empty.
      final reachedEnd = limit <= 0 || result.items.length < limit;
      newLibraryItemCounts[id] =
          reachedEnd ? fetched : (isFirstPage ? (result.totalRecordCount ?? 0) : (knownCount ?? fetched));
      return result;
    }

    Future<void> handleViewLoading() async {
      final limit = pageSize ~/ state.views.included.length;
      final results = await Future.wait(
        state.views.included.map((viewModel) => loadPage(viewModel.id, limit, viewModel: viewModel)),
      );

      List<ItemBaseModel> newPosters = _rankedForSearch(results.nonNulls.expand((element) => element.items).toList());
      if (!_rankingSearch && state.views.included.length > 1) {
        if (state.filters.sortingOption == SortingOptions.random) {
          newPosters = newPosters.random();
        } else {
          newPosters = newPosters.sorted(
            (a, b) => sortItems(a, b, state.filters.sortingOption, state.filters.sortOrder),
          );
        }
      }
      if (generation != _generation) return;
      state = state.copyWith(
        posters: isEmpty ? newPosters : [...state.posters, ...newPosters],
        lastIndices: newLastIndices,
        libraryItemCounts: newLibraryItemCounts,
      );
    }

    Future<void> handleFolderLoading() async {
      final limit = pageSize ~/ state.folderOverwrite.length;
      final results = await Future.wait(
        state.folderOverwrite.included.map((folder) => loadPage(folder.id, limit)),
      );

      List<ItemBaseModel> newPosters = _rankedForSearch(results.nonNulls.expand((element) => element.items).toList());
      if (!_rankingSearch && state.folderOverwrite.length > 1) {
        if (state.filters.sortingOption == SortingOptions.random) {
          newPosters = newPosters.random();
        } else {
          newPosters = newPosters.sorted(
            (a, b) => sortItems(a, b, state.filters.sortingOption, state.filters.sortOrder),
          );
        }
      }
      if (generation != _generation) return;
      state = state.copyWith(
        posters: isEmpty ? newPosters : [...state.posters, ...newPosters],
        lastIndices: newLastIndices,
        libraryItemCounts: newLibraryItemCounts,
      );
    }

    /// A page of the one shuffled order, dealing it first when the page is
    /// new: every id the filters match, from each library or folder, mixed
    /// together, then the items for the next stretch of it by id.
    Future<void> handleRandomLoading() async {
      var order = _randomOrder;
      if (isEmpty || order == null) {
        final results = state.folderOverwrite.isNotEmpty
            ? await Future.wait(
                state.folderOverwrite.included.map((folder) => _loadLibrary(id: folder.id, idsOnly: true)))
            : await Future.wait(state.views.included.map((view) => _loadLibrary(viewModel: view, idsOnly: true)));
        if (generation != _generation) return;
        order = results.nonNulls.expand((result) => result.items).map((item) => item.id).toSet().toList()..shuffle();
        _randomOrder = order;
      }
      final from = newLastIndices[_randomPagingKey] ?? 0;
      final ids = order.skip(from).take(pageSize).toList();
      final items = await _loadByIds(ids);
      if (generation != _generation) return;
      newLastIndices[_randomPagingKey] = from + ids.length;
      newLibraryItemCounts[_randomPagingKey] = order.length;
      state = state.copyWith(
        posters: isEmpty ? items : [...state.posters, ...items],
        lastIndices: newLastIndices,
        libraryItemCounts: newLibraryItemCounts,
      );
    }

    final random = state.filters.sortingOption == SortingOptions.random &&
        (state.folderOverwrite.isNotEmpty || state.views.hasEnabled);
    if (random) {
      await handleRandomLoading();
    } else if (state.folderOverwrite.isNotEmpty) {
      await handleFolderLoading();
    } else if (!state.views.hasEnabled) {
      if (state.filters.searchQuery.isEmpty && state.filters.favourites != true) {
        state = state.copyWith(posters: []);
      } else {
        final response = await _loadLibrary(recursive: true);
        state = state.copyWith(posters: _rankedForSearch(response?.items ?? []));
      }
    } else {
      await handleViewLoading();
    }

    loading = false;
  }

  Future<Map<ViewModel, bool>> loadViews(
    List<String>? viewModelId,
  ) async {
    try {
      final response = await api.usersUserIdViewsGet(includeHidden: false);
      final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref));

      Map<ViewModel, bool> mappedModels =
          createdViews?.isNotEmpty ?? false ? {for (var element in createdViews!) element: false} : {};

      final selectedModels = mappedModels.keys.where((element) => viewModelId?.contains(element.id) ?? false).toList();

      // No explicit library requested (e.g. a genre chip opening a whole-library
      // search): enable them all — an all-deselected picker just shows an empty
      // result list.
      final views = selectedModels.isEmpty && mappedModels.isNotEmpty
          ? mappedModels.setAll(true)
          : mappedModels.setKeys(selectedModels, true);

      return views;
    } catch (e) {
      log("Error loading views: $e");
      return {};
    }
  }

  Future<void> loadFolders({List<String>? folderId}) async {
    final response = await api.itemsGet(
      ids: folderId ?? state.folderOverwrite.keys.map((e) => e.id).toList(),
      sortBy: state.filters.sortingOption.toSortBy,
      sortOrder: [state.filters.sortOrder.sortOrder],
      fields: [
        ItemFields.parentid,
        ItemFields.primaryimageaspectratio,
      ],
    );

    state = state.copyWith(
      folderOverwrite: response.body?.items.toList().asMap().map((key, value) => MapEntry(value, true)) ?? {},
    );
  }

  Future<void> loadFilters(LibraryFilterModel filters) async {
    if (loadedFilters == true) return;
    loadedFilters = true;

    final disabledYearTypes = {
      FladderItemType.photo,
      FladderItemType.photoAlbum,
      FladderItemType.video,
    };

    final itemIds = state.currentIds;

    final enabledCollections = state.views.included.map((e) => e.collectionType.itemKinds).expand((element) => element);
    final disableYearFetching =
        state.folderOverwrite.isNotEmpty || enabledCollections.any((e) => disabledYearTypes.contains(e));

    final mappedListFuture = Future.wait(itemIds.map((id) => _loadFilters(id)));
    final studiosFuture = Future.wait(itemIds.map((id) => _loadStudios(id)));
    final genresFuture = Future.wait(itemIds.map((id) => _loadGenres(id)));
    final yearsFuture =
        disableYearFetching ? Future.value(<List<int>>[]) : Future.wait(itemIds.map((id) => _loadYears(id)));

    final mappedList = await mappedListFuture;
    final studiosRaw = await studiosFuture;
    final genresRaw = await genresFuture;
    final yearsRaw = await yearsFuture;

    final studios = studiosRaw.expand((element) => element).toSet().toList();
    final genres = genresRaw.expand((element) => element).toSet().toList();
    final years = yearsRaw.expand((element) => element).toSet().toList();

    final tags = mappedList
        .expand((element) => element?.tags ?? <String>[])
        .sorted((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    var tempState = state.copyWith();
    var tempFilters = tempState.filters;

    tempState = tempState.copyWith(
      filters: tempFilters.copyWith(
        searchQuery: filters.searchQuery,
        types: filters.types.isEmpty
            ? tempFilters.types
                .setAll(false)
                .setKeys(state.views.included.expand((view) => view.collectionType.defaultTypes), true)
            : tempFilters.types.replaceMap(filters.types),
        // Union: an incoming selection (genre chip) must survive even when
        // this view's own genre list doesn't contain it.
        genres: {for (var element in genres) element.name: false, ...filters.genres},
        studios: {for (var element in studios) element: false}.replaceMap(filters.studios),
        itemFilters: {
          for (var element in {
            ItemFilter.isplayed,
            ItemFilter.isunplayed,
            ItemFilter.isresumable,
          })
            element: false
        }.replaceMap(filters.itemFilters),
        years: {for (var element in years) element: false}.replaceMap(filters.years),
        tags: {for (var element in tags) element: false}.replaceMap(filters.tags),
      ),
    );

    state = tempState;
  }

  Future<QueryFilters?> _loadFilters(String id) async {
    final response = await api.itemsFilters2Get(parentId: id);
    return response.body;
  }

  Future<List<Studio>> _loadStudios(String id) async {
    // Names are all the chip needs; the default response carries full DTOs
    // with image and user data for every studio in the library.
    final response = await api.studiosGet(parentId: id, enableImages: false, enableUserData: false);
    return response.body?.items?.map((e) => Studio(id: e.id ?? "", name: e.name ?? "")).toList() ?? [];
  }

  Future<List<GenreItems>> _loadGenres(String id) async {
    final response = await api.genresGet(parentId: id);
    return response.body?.items?.map((e) => GenreItems(id: e.id ?? "", name: e.name ?? "")).toList() ?? [];
  }

  Future<List<int>> _loadYears(String id) async {
    final response = await api.yearsGet(
      parentId: id,
    );
    return response.body?.items?.map((e) => int.tryParse(e.name.toString())).whereType<int>().toList() ?? [];
  }

  /// While a search is running the user's sort choice is a tie-breaker at best -
  /// what they asked for is the thing they typed. Only the default sort gets
  /// reordered; picking a sort explicitly is the user asking for that order.
  bool get _rankingSearch =>
      state.filters.searchQuery.trim().isNotEmpty && state.filters.sortingOption == SortingOptions.sortName;

  List<ItemBaseModel> _rankedForSearch(List<ItemBaseModel> items) =>
      _rankingSearch ? items.rankedFor(state.filters.searchQuery) : items;

  Future<ServerQueryResult?> _loadLibrary(
      {ViewModel? viewModel,
      bool? recursive,
      bool? shuffle,
      String? id,
      int? limit,
      int? startIndex,
      String? searchTerm,
      List<BaseItemKind>? types,
      bool idsOnly = false,
      bool enableTotalRecordCount = true}) async {
    final searchString = searchTerm ?? (state.filters.searchQuery.isNotEmpty ? state.filters.searchQuery : null);
    // The letter strip: one letter narrows to titles starting with it, and
    // '#' to everything the server sorts ahead of A - digits and symbols.
    final letter = searchTerm == null ? state.filters.nameStartsWith : null;
    final sortBy = shuffle == true ? [ItemSortBy.random] : state.filters.sortingOption.toSortBy;
    final response = await api.itemsGet(
      // Only the ids, for dealing a Random order: no count, no images, no
      // user data, and no page - every match.
      enableTotalRecordCount: idsOnly ? false : enableTotalRecordCount,
      enableImages: idsOnly ? false : null,
      enableUserData: idsOnly ? false : null,
      // One of each kind is all a poster can use. Left to the default, every
      // item carries every backdrop it has, each with its tag and blurhash.
      imageTypeLimit: idsOnly ? 0 : 1,
      enableImageTypes: idsOnly ? null : _posterImageTypes,
      parentId: viewModel?.id ?? id,
      searchTerm: searchString,
      nameStartsWith: letter != null && letter != '#' ? letter : null,
      nameLessThan: letter == '#' ? 'A' : null,
      genres: state.filters.genres.included,
      tags: state.filters.tags.included,
      recursive: searchString?.isNotEmpty == true ? true : recursive ?? state.filters.recursive,
      officialRatings: state.filters.officialRatings.included,
      years: state.filters.years.included,
      isMissing: false,
      limit: !idsOnly && (limit ?? 0) > 0 ? limit : null,
      startIndex: !idsOnly && (limit ?? 0) > 0 ? startIndex : null,
      // Collections ticked: the server shows each collection in place of the
      // films it holds, which is the only way it lists collections among
      // films at all - asked not to fold them, it leaves the collections out.
      collapseBoxSetItems: state.filters.types[FladderItemType.boxset] == true ? null : false,
      studioIds: state.filters.studios.included.map((e) => e.id).toList(),
      sortBy: sortBy,
      sortOrder: [state.filters.sortOrder.sortOrder],
      fields: idsOnly ? const [] : _posterFields(childCount: viewModel?.collectionType == CollectionType.tvshows),
      isFavorite: state.filters.favourites,
      filters: state.filters.itemFilters.included,
      includeItemTypes: types ?? state.filters.types.included.map((e) => e.dtoKind).expand((e) => e).toList(),
    );
    return response.body;
  }

  static const _posterImageTypes = [ImageType.primary, ImageType.thumb, ImageType.backdrop, ImageType.logo];

  /// What a poster in the grid shows, and the count of episodes a show
  /// needs for its badge.
  static List<ItemFields> _posterFields({required bool childCount}) => [
        ItemFields.genres,
        ItemFields.parentid,
        ItemFields.tags,
        ItemFields.datecreated,
        ItemFields.datelastmediaadded,
        ItemFields.overview,
        ItemFields.originaltitle,
        ItemFields.customrating,
        ItemFields.primaryimageaspectratio,
        if (childCount) ItemFields.childcount,
      ];

  /// The items for [ids], as posters, in the order of [ids] - the server
  /// returns them in an order of its own.
  Future<List<ItemBaseModel>> _loadByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final response = await api.itemsGet(
      ids: ids,
      imageTypeLimit: 1,
      enableImageTypes: _posterImageTypes,
      enableTotalRecordCount: false,
      fields:
          _posterFields(childCount: state.views.included.any((view) => view.collectionType == CollectionType.tvshows)),
    );
    final byId = {for (final item in response.body?.items ?? const <ItemBaseModel>[]) item.id: item};
    return ids.map((id) => byId[id]).nonNulls.toList();
  }

  Future<ServerQueryResult?> _loadPlaylistItems({ViewModel? viewModel, String? id, int? startIndex, int? limit}) async {
    final response = await api.playlistsPlaylistIdItemsGet(
      playlistId: viewModel?.id ?? id,
      limit: (limit ?? 0) > 0 ? limit : null,
      startIndex: (limit ?? 0) > 0 ? startIndex : null,
      fields: {
        ItemFields.genres,
        ItemFields.parentid,
        ItemFields.tags,
        ItemFields.datecreated,
        ItemFields.datelastmediaadded,
        ItemFields.overview,
        ItemFields.originaltitle,
        ItemFields.customrating,
        ItemFields.primaryimageaspectratio,
        if (viewModel?.collectionType == CollectionType.tvshows) ItemFields.childcount,
      }.toList(),
    );
    return response.body;
  }

  Future<List<ItemBaseModel>> fetchSuggestions(String searchTerm, {int limit = 25}) async {
    if (searchTerm.trim().isEmpty) return [];

    // Ask for more than we show. The server orders matches by sort name, so the
    // first handful off the wire are whatever comes first in the alphabet, not
    // the best matches - we need a pool wide enough to rank.
    final poolLimit = (limit * 6).clamp(limit, 150);

    // Two pools, not one. The server sorts every kind of thing into a single
    // alphabet, so for a common letter the first hundred names back can be all
    // people and a film that matches never reaches the ranking at all - which
    // is how typing "j" returned nothing but actors. A second pass restricted
    // to the things you watch keeps them in the running. Not when the types
    // have been narrowed by hand: that is the user asking for one kind.
    final narrowedByHand = state.filters.types.included.isNotEmpty;
    final pools = await Future.wait([
      // People first, so the copy that knows how much of the library someone
      // is in wins the de-duplication below. /Items returns the same person
      // without those counts.
      if (!narrowedByHand) _peoplePool(searchTerm, limit),
      _suggestionPool(searchTerm, poolLimit, null),
      if (!narrowedByHand) _suggestionPool(searchTerm, poolLimit, _watchableKinds),
    ]);

    final seen = <String>{};
    final candidates = pools.expand((pool) => pool).where((item) => seen.add(item.id)).toList();

    if (candidates.isNotEmpty) return candidates.rankedFor(searchTerm).take(limit).toList();

    // Nothing contains what was typed, so either the library has not got it or
    // it is spelled differently to how you remember. Only now is the index
    // worth building.
    return _misspelledMatches(searchTerm, limit);
  }

  /// Titles close enough to the query to be what was meant, for a query the
  /// server's substring search could not answer.
  Future<List<ItemBaseModel>> _misspelledMatches(String searchTerm, int limit) async {
    try {
      final index = await ref.read(libraryIndexProvider.future);
      final ids = index.bestMatches(searchTerm, limit: limit);
      if (ids.isEmpty) return const [];

      // The index holds names; the row needs the whole item.
      final response = await api.itemsGet(ids: ids, recursive: true, fields: [ItemFields.primaryimageaspectratio]);
      final items = response.body?.items ?? const <ItemBaseModel>[];

      // Back into the order the scoring put them in — the server returns them
      // however it likes, and here that order is the whole answer.
      final byId = {for (final item in items) item.id: item};
      return ids.map((id) => byId[id]).nonNulls.toList();
    } catch (_) {
      return const [];
    }
  }

  /// The things a search is usually for, as the server names them.
  static const _watchableKinds = [
    BaseItemKind.movie,
    BaseItemKind.series,
    BaseItemKind.boxset,
    BaseItemKind.book,
  ];

  /// People, from the endpoint that can say what they are in. /Items returns
  /// them too but never with a count, and without one there is no telling the
  /// Jack with four films from the Jack with a single episode credit.
  Future<List<ItemBaseModel>> _peoplePool(String searchTerm, int limit) async {
    try {
      final response = await api.personsGet(searchTerm: searchTerm, limit: limit * 2);
      return response.body ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// One pass over whatever the search is scoped to - chosen folders, chosen
  /// libraries, or everything - optionally restricted to certain kinds.
  ///
  /// No counts: nothing reads them, and the server runs one over the whole
  /// match for each of these on every keystroke.
  Future<List<ItemBaseModel>> _suggestionPool(String searchTerm, int poolLimit, List<BaseItemKind>? types) async {
    if (state.folderOverwrite.isNotEmpty) {
      final results = await Future.wait(state.folderOverwrite.included.map((folder) => _loadLibrary(
          id: folder.id, limit: poolLimit, searchTerm: searchTerm, types: types, enableTotalRecordCount: false)));
      return results.expand((result) => result?.items ?? const <ItemBaseModel>[]).toList();
    }

    if (state.views.hasEnabled) {
      final results = await Future.wait(state.views.included.map((view) => _loadLibrary(
          viewModel: view, limit: poolLimit, searchTerm: searchTerm, types: types, enableTotalRecordCount: false)));
      return results.expand((result) => result?.items ?? const <ItemBaseModel>[]).toList();
    }

    final response = await _loadLibrary(
        limit: poolLimit, recursive: true, searchTerm: searchTerm, types: types, enableTotalRecordCount: false);
    return response?.items ?? const [];
  }

  void setSearch(String query) {
    state = state.copyWith(filters: state.filters.copyWith(searchQuery: query));
    ref.read(userProvider.notifier).addSearchQuery(query);
  }

  void setFavourites(bool? value) => state = state.copyWith(filters: state.filters.copyWith(favourites: value));
  void toggleRecursive() =>
      state = state.copyWith(filters: state.filters.copyWith(recursive: state.filters.recursive == false));
  void toggleType(FladderItemType type) =>
      state = state.copyWith(filters: state.filters.copyWith(types: state.filters.types.toggleKey(type)));
  void toggleView(ViewModel view) => state = state.copyWith(views: state.views.toggleKey(view));
  void toggleGenre(String genre) =>
      state = state.copyWith(filters: state.filters.copyWith(genres: state.filters.genres.toggleKey(genre)));
  void toggleStudio(Studio studio) =>
      state = state.copyWith(filters: state.filters.copyWith(studios: state.filters.studios.toggleKey(studio)));
  void toggleTag(String tag) =>
      state = state.copyWith(filters: state.filters.copyWith(tags: state.filters.tags.toggleKey(tag)));
  void toggleRatings(String officialRatings) => state = state.copyWith(
      filters: state.filters.copyWith(officialRatings: state.filters.officialRatings.toggleKey(officialRatings)));
  void toggleYears(int year) =>
      state = state.copyWith(filters: state.filters.copyWith(years: state.filters.years.toggleKey(year)));
  void toggleFilters(ItemFilter filter) =>
      state = state.copyWith(filters: state.filters.copyWith(itemFilters: state.filters.itemFilters.toggleKey(filter)));

  void setViews(Map<ViewModel, bool> views) {
    loadedFilters = false;
    state = state.copyWith(views: views);
  }

  void setGenres(Map<String, bool> genres) => state = state.copyWith(filters: state.filters.copyWith(genres: genres));
  void setStudios(Map<Studio, bool> studios) =>
      state = state.copyWith(filters: state.filters.copyWith(studios: studios));
  void setTags(Map<String, bool> tags) => state = state.copyWith(filters: state.filters.copyWith(tags: tags));
  void setTypes(Map<FladderItemType, bool> types) =>
      state = state.copyWith(filters: state.filters.copyWith(types: types));
  void setRatings(Map<String, bool> officialRatings) =>
      state = state.copyWith(filters: state.filters.copyWith(officialRatings: officialRatings));
  void setYears(Map<int, bool> years) => state = state.copyWith(filters: state.filters.copyWith(years: years));
  void setFilters(Map<ItemFilter, bool> filters) =>
      state = state.copyWith(filters: state.filters.copyWith(itemFilters: filters));

  void setSortBy(SortingOptions e) => state = state.copyWith(filters: state.filters.copyWith(sortingOption: e));

  void setNameStartsWith(String? letter) =>
      state = state.copyWith(filters: state.filters.copyWith(nameStartsWith: letter));

  void setSortOrder(SortingOrder e) => state = state.copyWith(filters: state.filters.copyWith(sortOrder: e));

  void toggleEmptyShows() =>
      state = state.copyWith(filters: state.filters.copyWith(hideEmptyShows: !state.filters.hideEmptyShows));
  void setGroupBy(GroupBy groupBy) => state = state.copyWith(filters: state.filters.copyWith(groupBy: groupBy));

  void clearAllFilters() {
    state = state.copyWith(
      filters: state.filters.clear(),
    );
  }

  void toggleSelectMode() =>
      state = state.copyWith(selecteMode: !state.selecteMode, selectedPosters: !state.selecteMode == false ? [] : []);

  void toggleSelection(ItemBaseModel item) {
    if (state.selectedPosters.contains(item)) {
      state = state.copyWith(selectedPosters: state.selectedPosters.where((element) => element != item).toList());
    } else {
      state = state.copyWith(selectedPosters: [...state.selectedPosters, item]);
    }
  }

  LibrarySearchModel selectAll(bool select) => state = state.copyWith(selectedPosters: select ? state.posters : []);

  Future<void> setSelectedAsFavorite(bool bool) async {
    final Map<String, UserData> updateInfo = {};
    for (var i = 0; i < state.selectedPosters.length; i++) {
      final response = await ref.read(userProvider.notifier).setAsFavorite(bool, state.selectedPosters[i].id);
      final userData = response?.bodyOrThrow;
      if (userData != null) {
        updateInfo.putIfAbsent(state.selectedPosters[i].id, () => userData);
      }
    }
    updateMultiUserData(updateInfo);
  }

  Future<void> setSelectedAsWatched(bool bool) async {
    final Map<String, UserData> updateInfo = {};
    for (var i = 0; i < state.selectedPosters.length; i++) {
      final response = await ref.read(userProvider.notifier).markAsPlayed(bool, state.selectedPosters[i].id);
      final userData = response?.bodyOrThrow;
      if (userData != null) {
        updateInfo.putIfAbsent(state.selectedPosters[i].id, () => userData);
      }
    }
    updateMultiUserData(updateInfo);
  }

  Future<Response> removeSelectedFromCollection() async {
    final response = await api.collectionsCollectionIdItemsDelete(
        collectionId: state.folderOverwrite.included.firstOrNull?.id,
        ids: state.selectedPosters.map((e) => e.id).toList());
    if (response.isSuccessful) {
      removeFromPosters([state.folderOverwrite.included.firstOrNull?.id].nonNulls.toList());
    }
    return response;
  }

  Future<Response> removeSelectedFromPlaylist() async {
    final response = await api.playlistsPlaylistIdItemsDelete(
        playlistId: state.folderOverwrite.included.firstOrNull?.id,
        entryIds: state.selectedPosters.map((e) => e.playlistId).nonNulls.toList());
    if (response.isSuccessful) {
      removeFromPosters([state.folderOverwrite.included.firstOrNull?.id].nonNulls.toList());
    }
    return response;
  }

  Future<Response> removeFromCollection({required List<ItemBaseModel> items}) async {
    final response = await api.collectionsCollectionIdItemsDelete(
        collectionId: state.folderOverwrite.included.firstOrNull?.id, ids: items.map((e) => e.id).toList());
    if (response.isSuccessful) {
      removeFromPosters(items.map((e) => e.id).toList());
    }
    return response;
  }

  Future<Response> removeFromPlaylist({required List<ItemBaseModel> items}) async {
    final response = await api.playlistsPlaylistIdItemsDelete(
        playlistId: state.folderOverwrite.included.firstOrNull?.id,
        entryIds: items.map((e) => e.playlistId).nonNulls.toList());
    if (response.isSuccessful) {
      removeFromPosters(items.map((e) => e.id).toList());
    }
    return response;
  }

  /// One pass and one state change for the lot. Marking fifty items on a
  /// library of two thousand used to be fifty copies of the list, each with a
  /// scan by id and then a scan by deep equality to find the same item again,
  /// and fifty rebuilds of the grid.
  Future<void> updateMultiUserData(Map<String, UserData?> newData) async {
    if (newData.isEmpty) return;
    var changed = false;
    final currentItems = state.posters.map((item) {
      if (!newData.containsKey(item.id)) return item;
      changed = true;
      return item.copyWith(userData: newData[item.id]);
    }).toList();
    if (changed) state = state.copyWith(posters: currentItems);
  }

  Future<void> updateUserData(String id, UserData? newData) => updateMultiUserData({id: newData});

  void updateUserDataMain(UserData? userData) {
    state = state.copyWith(
      folderOverwrite: state.folderOverwrite.map((key, value) {
        if (value == true) {
          return MapEntry(key.copyWith(userData: userData), value);
        }
        return MapEntry(key, value);
      }),
    );
  }

  void updateParentItem(ItemBaseModel item) {
    state = state.copyWith(folderOverwrite: state.folderOverwrite.map((key, value) {
      if (value == true) {
        return MapEntry(item, value);
      }
      return MapEntry(key, value);
    }));
  }

  void removeFromPosters(List<String> ids) {
    final newPosters = state.posters;
    state = state.copyWith(posters: newPosters..removeWhere((element) => ids.contains(element.id)));
  }

  void updateItems(List<ItemBaseModel> items) {}

  void updateItem(ItemBaseModel item) {
    state = state.copyWith(posters: state.posters.replace(item));
  }

  Future<List<ItemBaseModel>> _loadAllItems({bool shuffle = false, int? limit}) async {
    List<ItemBaseModel> itemsToPlay = [];

    Future<void> handleItemLoading(String itemId, ItemBaseModel currentModel) async {
      final result =
          currentModel is PlaylistModel ? await _loadPlaylistItems(id: itemId) : await _loadLibrary(id: itemId);

      itemsToPlay = result?.items ?? [];
    }

    Future<void> handleViewLoading() async {
      final results = await Future.wait(
        state.views.included.map((viewModel) async {
          final libraryItems = await _loadLibrary(
            shuffle: shuffle,
            viewModel: viewModel,
            limit: limit,
          );
          return libraryItems;
        }).nonNulls,
      );

      List<ItemBaseModel> newPosters = results.nonNulls.expand((element) => element.items).toList();
      if (state.views.included.length > 1) {
        if (shuffle || state.filters.sortingOption == SortingOptions.random) {
          newPosters = newPosters.random();
        } else {
          newPosters = newPosters.sorted(
            (a, b) => sortItems(a, b, state.filters.sortingOption, state.filters.sortOrder),
          );
        }
      }

      itemsToPlay = newPosters;
    }

    if (state.folderOverwrite.isNotEmpty) {
      await handleItemLoading(state.folderOverwrite.included.last.id, state.folderOverwrite.included.last);
    } else if (state.views.hasEnabled) {
      await handleViewLoading();
    } else {
      if (state.filters.searchQuery.isEmpty && state.filters.favourites == false) {
        itemsToPlay = [];
      } else {
        final response = await _loadLibrary(recursive: true, shuffle: shuffle);
        itemsToPlay = response?.items ?? [];
      }
    }

    return itemsToPlay;
  }

  Future<void> playLibraryItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    List<ItemBaseModel> itemsToPlay = [];

    if (state.selectedPosters.isNotEmpty) {
      itemsToPlay = shuffle ? state.selectedPosters.random() : state.selectedPosters;
    } else {
      itemsToPlay = await showLoadingOverlay(context, callBack: _loadAllItems(shuffle: shuffle));
    }

    //Only try to load video items
    itemsToPlay = itemsToPlay.where((element) => FladderItemType.playable.contains(element.type)).toList();

    if (itemsToPlay.isNotEmpty) {
      await itemsToPlay.playLibraryItems(context, ref, shuffle: shuffle);
    } else {
      FladderSnack.show(context.localized.libraryFetchNoItemsFound, context: context);
    }
  }

  Future<void> playMusicItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (state.selectedPosters.isEmpty) {
      final queueSource = _createMusicQueueSource(shuffle: shuffle);
      if (queueSource != null) {
        final started = await _playMusicFromQueueSource(context, ref, queueSource);
        if (started) {
          return;
        } else {
          FladderSnack.show(context.localized.libraryFetchNoItemsFound, context: context);
        }
      }
    } else {
      List<ItemBaseModel> itemsToPlay = [];

      if (state.selectedPosters.isNotEmpty) {
        itemsToPlay = shuffle ? state.selectedPosters.random() : state.selectedPosters;
      } else {
        itemsToPlay = await showLoadingOverlay(context, callBack: _loadAllItems(shuffle: shuffle));
      }

      itemsToPlay = itemsToPlay.where((element) => FladderItemType.musicPlayable.contains(element.type)).toList();

      if (itemsToPlay.isNotEmpty) {
        await itemsToPlay.playMusicItems(context, ref, shuffle: shuffle);
      } else {
        FladderSnack.show(context.localized.libraryFetchNoItemsFound, context: context);
      }
    }
  }

  PlaybackQueueSource? _createMusicQueueSource({required bool shuffle}) {
    if (state.folderOverwrite.isNotEmpty) {
      final currentItem = state.folderOverwrite.keys.last;
      if (currentItem is PlaylistModel) {
        return PlaylistAudioQueueSource(
          playlistId: currentItem.id,
          limit: _libraryMusicRefillLimit,
          shuffle: shuffle,
        );
      }

      return _buildLibraryMusicQueueSource(
        parentId: state.folderOverwrite.keys.map((e) => e.id).toList(),
        recursive: true,
        shuffle: shuffle,
      );
    }

    if (state.views.hasEnabled) {
      return _buildLibraryMusicQueueSource(
        parentId: state.views.included.map((e) => e.id).toList(),
        recursive: true,
        shuffle: shuffle,
      );
    }

    return _buildLibraryMusicQueueSource(
      parentId: [],
      recursive: true,
      shuffle: shuffle,
    );
  }

  LibraryMusicQueueSource _buildLibraryMusicQueueSource({
    required List<String> parentId,
    required bool? recursive,
    required bool shuffle,
  }) {
    return LibraryMusicQueueSource(
      libraryState: state,
      parentId: parentId,
      recursive: recursive,
      shuffle: shuffle,
      limit: _libraryMusicRefillLimit,
    );
  }

  PhotoQueueSource? createPhotoQueueSource({required bool shuffle}) {
    final recursive = state.filters.searchQuery.isNotEmpty ? true : state.filters.recursive;

    if (state.folderOverwrite.isNotEmpty) {
      return _buildPhotoQueueSource(
        parentId: state.folderOverwrite.included.map((e) => e.id).toList(),
        recursive: recursive,
        shuffle: shuffle,
      );
    }

    if (state.views.hasEnabled) {
      return _buildPhotoQueueSource(
        parentId: state.views.included.map((e) => e.id).toList(),
        recursive: recursive,
        shuffle: shuffle,
      );
    }

    if (state.filters.searchQuery.isEmpty && state.filters.favourites == false) {
      return null;
    }

    return _buildPhotoQueueSource(
      parentId: null,
      recursive: true,
      shuffle: shuffle,
    );
  }

  PhotoQueueSource _buildPhotoQueueSource({
    required List<String>? parentId,
    required bool? recursive,
    required bool shuffle,
  }) {
    return PhotoQueueSource(
      libraryState: state,
      parentIds: parentId,
      recursive: recursive,
      shuffle: shuffle,
      limit: _libraryPhotoFetchLimit,
    );
  }

  Future<bool> _playMusicFromQueueSource(
    BuildContext context,
    WidgetRef ref,
    PlaybackQueueSource queueSource,
  ) async {
    await ref.read(videoPlayerProvider.notifier).init();

    final result = await showLoadingOverlay(
      context,
      callBack: Future(() async {
        final initialQueue = await queueSource.fetchQueue(
          ref.read,
          limit: _libraryMusicInitialQueueLimit,
          startIndex: 0,
        );

        if (initialQueue.isEmpty) return null;

        final model = await ref.read(playbackModelHelper).createPlaybackModel(
              context,
              initialQueue.firstOrNull,
              libraryQueue: initialQueue,
              queueSource: queueSource,
            );
        if (model == null) return null;

        return (model, initialQueue);
      }),
    );

    if (result == null) {
      return false;
    }

    final model = result.$1;
    final queue = result.$2;
    final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
    final actualStartPosition = await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
    return true;
  }

  Future<List<PhotoModel>> fetchGallery({bool shuffle = false}) async {
    try {
      List<ItemBaseModel> itemsToPlay = [];

      if (state.selectedPosters.isNotEmpty) {
        itemsToPlay = shuffle ? state.selectedPosters.random() : state.selectedPosters;
      } else {
        itemsToPlay = await _loadAllItems(shuffle: shuffle);
      }

      List<PhotoModel> albumItems = [];

      if (!state.filters.types.included.containsAny([FladderItemType.video, FladderItemType.photo]) &&
          state.filters.recursive == true) {
        for (var album in itemsToPlay.where(
          (element) => element is PhotoAlbumModel || element is FolderModel,
        )) {
          try {
            final fetchedAlbumContent = await api.itemsGet(
              parentId: album.id,
              includeItemTypes: state.filters.types.included.map((e) => e.dtoKind).expand((e) => e).toList(),
              recursive: true,
              fields: {
                ItemFields.genres,
                ItemFields.parentid,
                ItemFields.tags,
                ItemFields.datecreated,
                ItemFields.datelastmediaadded,
                ItemFields.overview,
                ItemFields.originaltitle,
                ItemFields.customrating,
                ItemFields.primaryimageaspectratio,
              }.toList(),
              isFavorite: state.filters.favourites,
              filters: state.filters.itemFilters.included,
              sortBy: shuffle ? [ItemSortBy.random] : null,
            );
            albumItems.addAll(fetchedAlbumContent.body?.items.whereType<PhotoModel>() ?? []);
          } catch (e) {
            log("Error fetching ${e.toString()}");
          }
        }
      }

      final galleryItems = itemsToPlay.whereType<PhotoModel>().toList();

      if (shuffle) {
        albumItems = albumItems.random();
      }

      final allItems = {...albumItems.whereType<PhotoModel>(), ...galleryItems}.toList();

      return allItems;
    } catch (e) {
      log(e.toString());
    } finally {}
    return [];
  }

  Future<void> viewGallery(BuildContext context, WidgetRef ref, {PhotoModel? selected, bool shuffle = false}) async {
    List<PhotoModel> allItems = state.activePosters.whereType<PhotoModel>().toList();
    if (allItems.isNotEmpty) {
      final newItemList = shuffle ? allItems.shuffled() : allItems;
      final photoSource = state.selectedPosters.isEmpty ? createPhotoQueueSource(shuffle: shuffle) : null;
      final loadPhotos = shuffle ? (await photoSource?.fetchPhotos(ref.read))?.items : newItemList;
      await context.pushRoute(
        PhotoViewerRoute(
          items: loadPhotos,
          selected: selected?.id,
          photoQueueSource: photoSource,
        ),
      );
    } else {
      FladderSnack.show(context.localized.libraryFetchNoItemsFound, context: context);
    }
  }

  Future<T> showLoadingOverlay<T>(
    BuildContext context, {
    required Future<T> callBack,
  }) async {
    state = state.copyWith(fetchingItems: true);
    BuildContext? dialogContext;
    var cancelAble = CancelableOperation<T>.fromFuture(callBack);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
        return Center(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  const CircularProgressIndicator(),
                  Text(context.localized.fetchingLibrary, style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: () {
                      cancelAble.cancel();
                      context.pop();
                    },
                    icon: const Icon(IconsaxPlusLinear.close_square),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      return await cancelAble.value;
    } finally {
      state = state.copyWith(fetchingItems: false);
      if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
        Navigator.of(dialogContext!).pop();
      }
    }
  }

  Future<void> openRandom(BuildContext context) async {
    final items = await _loadAllItems(shuffle: true, limit: 1);
    if (items.isNotEmpty) {
      items.firstOrNull?.navigateTo(context);
    }
  }

  void updateEverything() {
    state = state.copyWith();
  }

  void loadModel(LibraryFiltersModel model) {
    state = state.copyWith(
      filters: state.filters.loadModel(model.filter),
    );
  }

  void saveFilter(LibraryFiltersModel model) => ref.read(filterProvider.notifier).saveFilter(
        model.copyWith(
          viewNames: state.folderOverwrite.isNotEmpty
              ? state.folderOverwrite.included.map((e) => e.name).toList()
              : state.views.included.map((e) => e.name).toList(),
        ),
      );

  void saveFiltersNew(String newName) => ref.read(filterProvider.notifier).saveFilter(
        LibraryFiltersModel.fromLibrarySearch(
          newName,
          state,
        ),
      );

  void updateFilterName(LibraryFiltersModel model) {
    ref.read(filterProvider.notifier).saveFilter(model);
  }

  void updateFilter(LibraryFiltersModel model) {
    ref.read(filterProvider.notifier).saveFilter(
          LibraryFiltersModel.fromLibrarySearch(
            model.name,
            state,
            isFavourite: model.isFavourite,
            id: model.id,
            showInSideBar: model.showInSideBar,
            viewNames: state.folderOverwrite.isNotEmpty
                ? state.folderOverwrite.included.map((e) => e.name).toList()
                : state.views.included.map((e) => e.name).toList(),
          ),
        );
  }

  void setYearsRange(int? first, int? last) {
    state = state.copyWith(
      filters: state.filters.copyWith(
        years: state.filters.years.replaceMap(
          {for (var i = first ?? 0; i <= (last ?? 0); i++) i: true},
        ),
      ),
    );
  }

  void setFolderOverwrite(Map<ItemBaseModel, bool> value) async {
    loadedFilters = false;
    state = state.copyWith(folderOverwrite: value);
  }
}

extension SimpleSorter on List<ItemBaseModel> {
  List<ItemBaseModel> hideEmptyChildren(bool hide) {
    if (hide) {
      return where((element) {
        if (element.childCount == null) {
          return true;
        }
        return (element.childCount ?? 0) > 0;
      }).toList();
    } else {
      return this;
    }
  }
}

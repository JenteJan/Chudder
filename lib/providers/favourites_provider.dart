import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/favourites_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';

final favouritesProvider = StateNotifierProvider<FavouritesNotifier, FavouritesModel>((ref) {
  return FavouritesNotifier(ref);
});

class FavouritesNotifier extends StateNotifier<FavouritesModel> {
  FavouritesNotifier(this.ref) : super(FavouritesModel()) {
    // Same reason as the dashboard: favourites are a server query, and the
    // cached answer is wrong the moment the server is gone.
    ref.listen(connectivityStatusProvider, (previous, next) {
      if (previous == next) return;
      state = state.copyWith(loading: false);
      fetchFavourites();
    });
  }

  final Ref ref;

  late final api = ref.read(jellyApiProvider);

  Future<void> fetchFavourites() async {
    try {
      if (state.loading) return;

      state = state.copyWith(loading: true);
      // Two separate rows of the page; neither waits for the other.
      await Future.wait([
        _fetchMoviesAndSeries(),
        _fetchPeople(),
      ]);
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> _fetchMoviesAndSeries() async {
    // No server: the favourites that still mean anything are the ones whose
    // file is on disk. Anything else would be a poster that cannot be opened.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      final downloaded = await ref.read(syncProvider.notifier).allDownloadedItems();
      state = state.copyWith(
        favourites: downloaded.where((item) => item.userData.isFavourite).toList().groupedItems,
      );
      return;
    }

    final views = ref.read(viewsProvider);

    final mappedList = await Future.wait([
      ...views.dashboardViews.map((viewModel) => _loadLibrary(viewModel: viewModel)),
      // Collections live in their own virtual library, not in any of the
      // dashboard views iterated above — fetch favorited ones globally or
      // they never show up here at all.
      fetchTypes(null, [BaseItemKind.boxset]),
    ]);

    state = state.copyWith(
        favourites: (mappedList
                .expand((innerList) => innerList ?? [])
                .where((item) => item != null)
                .cast<ItemBaseModel>()
                .toList())
            .groupedItems);
  }

  /// What a library's favourites are made of, in the order the page lists
  /// them.
  static const _kinds = [
    BaseItemKind.movie,
    BaseItemKind.episode,
    BaseItemKind.series,
    BaseItemKind.video,
    BaseItemKind.photo,
    BaseItemKind.book,
    BaseItemKind.photoalbum,
    BaseItemKind.musicalbum,
    BaseItemKind.audio,
  ];

  /// The same kinds as the page knows them, in the same order.
  static const _kindTypes = [
    FladderItemType.movie,
    FladderItemType.episode,
    FladderItemType.series,
    FladderItemType.video,
    FladderItemType.photo,
    FladderItemType.book,
    FladderItemType.photoAlbum,
    FladderItemType.musicAlbum,
    FladderItemType.audio,
  ];

  /// How many of each kind a library contributes.
  static const _perKind = 15;

  /// A library's favourites: up to [_perKind] of every kind, grouped by kind.
  ///
  /// This used to be a request per kind per library - nine for every library
  /// at once, all racing for connections to the same server. One request per
  /// library brings back the same answer whenever the library has no more
  /// favourites than nine full rows would hold, which is nearly always; a
  /// library that has more goes back to asking kind by kind, so no row is cut
  /// short by another kind that sorts ahead of it.
  Future<List<ItemBaseModel>?> _loadLibrary({ViewModel? viewModel}) async {
    final response = await _favouritesQuery(viewModel?.id, _kinds, limit: _perKind * _kinds.length);
    final result = response.body;
    final total = result?.totalRecordCount;
    if (result != null && total != null && total <= result.items.length) {
      return groupFavouritesByKind(result.items);
    }
    final futures = _kinds.map((kind) => fetchTypes(viewModel?.id, [kind])).toList();
    final results = await Future.wait(futures);
    return results.expand((list) => list).toList();
  }

  /// [items] in the order a request per kind would have returned them: kind
  /// by kind, at most [_perKind] of each, each kind in the server's order.
  static List<ItemBaseModel> groupFavouritesByKind(List<ItemBaseModel> items) {
    final byKind = <FladderItemType, List<ItemBaseModel>>{};
    for (final item in items) {
      final kind = byKind.putIfAbsent(item.type, () => []);
      if (kind.length < _perKind) kind.add(item);
    }
    return [
      for (final type in _kindTypes) ...?byKind.remove(type),
      // Nothing else is asked for; kept rather than lost if it ever comes.
      ...byKind.values.expand((list) => list),
    ];
  }

  Future<List<ItemBaseModel>> fetchTypes(String? id, List<BaseItemKind>? includeItemTypes) async {
    return (await _favouritesQuery(id, includeItemTypes, limit: _perKind)).body?.items ?? [];
  }

  Future<Response<ServerQueryResult>> _favouritesQuery(
    String? id,
    List<BaseItemKind>? includeItemTypes, {
    required int limit,
  }) =>
      api.itemsGet(
        parentId: id,
        isFavorite: true,
        recursive: true,
        limit: limit,
        fields: [
          ItemFields.overview,
          ItemFields.genres,
          ItemFields.parentid,
        ],
        includeItemTypes: includeItemTypes,
        sortOrder: [SortOrder.ascending],
        sortBy: [ItemSortBy.seriessortname, ItemSortBy.sortname, ItemSortBy.datelastcontentadded],
        enableTotalRecordCount: true,
      );

  Future<Response<List<ItemBaseModel>>?> _fetchPeople() async {
    // People are server-only - none of them are ever downloaded - so offline
    // this is a request that fails on its way to an empty list.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) return null;
    final response = await api.personsGet(
      limit: 20,
      isFavorite: true,
    );
    state = state.copyWith(people: response.body ?? []);
    return response;
  }

  void setSearch(String value) {
    state = state.copyWith(searchQuery: value);
  }

  void clear() {
    state = FavouritesModel();
  }
}

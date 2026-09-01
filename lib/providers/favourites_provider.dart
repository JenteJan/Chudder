import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/favourites_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

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
    if (state.loading) return;

    state = state.copyWith(loading: true);
    await _fetchMoviesAndSeries();
    await _fetchPeople();
    state = state.copyWith(loading: false);
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

  Future<List<ItemBaseModel>?> _loadLibrary({ViewModel? viewModel}) async {
    final kinds = [
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
    final futures = kinds.map((kind) => fetchTypes(viewModel?.id, [kind])).toList();
    final results = await Future.wait(futures);
    return results.expand((list) => list).toList();
  }

  Future<List<ItemBaseModel>> fetchTypes(String? id, List<BaseItemKind>? includeItemTypes) async {
    return (await api.itemsGet(
          parentId: id,
          isFavorite: true,
          recursive: true,
          limit: 15,
          fields: [
            ItemFields.overview,
            ItemFields.genres,
            ItemFields.parentid,
          ],
          includeItemTypes: includeItemTypes,
          sortOrder: [SortOrder.ascending],
          sortBy: [ItemSortBy.seriessortname, ItemSortBy.sortname, ItemSortBy.datelastcontentadded],
        ))
            .body
            ?.items ??
        [];
  }

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

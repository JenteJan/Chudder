import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';

/// What a studio page shows: the studio itself, and what of theirs is in the
/// library. Jellyfin only knows about the latter — it has no catalogue of
/// everything a studio ever made.
class StudioDetails {
  const StudioDetails({
    this.studio,
    this.movies = const [],
    this.series = const [],
    this.loading = true,
  });

  final ItemBaseModel? studio;
  final List<MovieModel> movies;
  final List<SeriesModel> series;
  final bool loading;

  bool get isEmpty => movies.isEmpty && series.isEmpty;

  StudioDetails copyWith({
    ItemBaseModel? studio,
    List<MovieModel>? movies,
    List<SeriesModel>? series,
    bool? loading,
  }) =>
      StudioDetails(
        studio: studio ?? this.studio,
        movies: movies ?? this.movies,
        series: series ?? this.series,
        loading: loading ?? this.loading,
      );
}

final studioDetailsProvider =
    StateNotifierProvider.autoDispose.family<StudioDetailsNotifier, StudioDetails, String>((ref, id) {
  return StudioDetailsNotifier(ref, id);
});

class StudioDetailsNotifier extends StateNotifier<StudioDetails> {
  StudioDetailsNotifier(this.ref, this.studioId) : super(const StudioDetails());

  final Ref ref;
  final String studioId;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> fetch(ItemBaseModel? known) async {
    state = state.copyWith(studio: known, loading: true);

    // The studio item itself carries the name and artwork; the caller only has
    // whatever the row it was tapped from happened to hold.
    final studio = await api.usersUserIdItemsItemIdGet(itemId: studioId);
    if (studio.isSuccessful && studio.body != null) {
      state = state.copyWith(studio: studio.bodyOrThrow);
    }

    final results = await Future.wait([
      _itemsOfType(BaseItemKind.movie),
      _itemsOfType(BaseItemKind.series),
    ]);

    state = state.copyWith(
      movies: results.first.whereType<MovieModel>().toList(),
      series: results.last.whereType<SeriesModel>().toList(),
      loading: false,
    );
  }

  Future<List<ItemBaseModel>> _itemsOfType(BaseItemKind type) async {
    final response = await api.itemsGet(
      studioIds: [studioId],
      recursive: true,
      sortBy: [ItemSortBy.premieredate, ItemSortBy.productionyear, ItemSortBy.sortname],
      sortOrder: [SortOrder.descending],
      fields: [ItemFields.primaryimageaspectratio],
      includeItemTypes: [type],
    );
    return response.body?.items ?? [];
  }
}

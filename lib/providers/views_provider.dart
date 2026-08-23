import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/models/views_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';

//Known supported collection types
const enableCollectionTypes = {
  CollectionType.movies,
  CollectionType.books,
  CollectionType.tvshows,
  CollectionType.homevideos,
  CollectionType.boxsets,
  CollectionType.playlists,
  CollectionType.photos,
  CollectionType.livetv,
  CollectionType.folders,
  CollectionType.music,
  CollectionType.musicvideos,
};

final viewsProvider = StateNotifierProvider<ViewsNotifier, ViewsModel>((ref) {
  return ViewsNotifier(ref);
});

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  /// The Latest endpoint returns a mix for TV libraries: a multi-episode drop
  /// groups into its series or season, but a single new episode comes back as
  /// that episode. A "recently added" row on a shows library should show
  /// SHOWS — collapse every episode and season entry to its series, hydrated
  /// with the real series poster, keeping the recency order and deduping
  /// repeats.
  Future<List<ItemBaseModel>> _collapseEpisodesToSeries(List<ItemBaseModel> items) async {
    String? seriesIdOf(ItemBaseModel item) => switch (item) {
          EpisodeModel episode => episode.parentId,
          SeasonModel season => season.seriesId.isNotEmpty ? season.seriesId : season.parentId,
          _ => null,
        };
    final orderedIds = <String>[];
    final bySeriesId = <String, ItemBaseModel>{};
    final seriesToFetch = <String>{};
    for (final item in items) {
      final seriesId = seriesIdOf(item);
      final id = seriesId ?? item.id;
      if (!orderedIds.contains(id)) orderedIds.add(id);
      if (seriesId != null) {
        seriesToFetch.add(seriesId);
      } else {
        bySeriesId.putIfAbsent(id, () => item);
      }
    }
    if (seriesToFetch.isNotEmpty) {
      try {
        final response = await api.itemsGet(
          ids: seriesToFetch.toList(),
          fields: [
            ItemFields.parentid,
            ItemFields.primaryimageaspectratio,
            ItemFields.overview,
          ],
        );
        for (final model in response.body?.items ?? <ItemBaseModel>[]) {
          bySeriesId[model.id] = model;
        }
      } catch (_) {
        // Hydration failing shouldn't empty the row — fall through to
        // whatever entries resolved.
      }
    }
    return orderedIds.map((id) => bySeriesId[id]).nonNulls.toList();
  }

  Future<ViewsModel?> fetchViews() async {
    if (state.loading) return null;
    final showAllCollections = ref.read(clientSettingsProvider.select((value) => value.showAllCollectionTypes));
    final response = await api.usersUserIdViewsGet();
    final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref)).where((element) {
      return showAllCollections ? true : enableCollectionTypes.contains(element.collectionType);
    });

    List<ViewModel> newList = [];

    if (createdViews != null) {
      newList = await Future.wait(createdViews.map((e) async {
        if (ref.read(userProvider)?.latestItemsExcludes.contains(e.id) == true) return e;
        final recents = await api.usersUserIdItemsLatestGet(
          parentId: e.id,
          imageTypeLimit: 1,
          limit: 16,
          includeItemTypes:
              (e.collectionType == CollectionType.books && !showAllCollections) ? [BaseItemKind.book] : null,
          enableImageTypes: [
            ImageType.primary,
            ImageType.backdrop,
            ImageType.thumb,
          ],
          fields: [
            ItemFields.parentid,
            ItemFields.mediastreams,
            ItemFields.mediasources,
            ItemFields.candelete,
            ItemFields.candownload,
            ItemFields.primaryimageaspectratio,
            ItemFields.overview,
          ],
        );
        var recentModels = recents.body?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
        if (e.collectionType == CollectionType.tvshows && recentModels != null) {
          recentModels = await _collapseEpisodesToSeries(recentModels);
        }
        return e.copyWith(recentlyAdded: recentModels);
      }));
    }

    state = state.copyWith(
        views: _applyLibraryOrdering(newList),
        dashboardViews: _applyLibraryOrdering(newList
            .where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true))
            .toList()),
        loading: false);
    return state;
  }

  List<ViewModel> _applyLibraryOrdering(List<ViewModel> views) {
    final orderedViews = ref.read(userProvider)?.userConfiguration?.orderedViews ?? [];
    if (orderedViews.isEmpty) return views;

    final viewMap = {for (var v in views) v.id: v};
    final ordered = <ViewModel>[];

    for (final id in orderedViews) {
      final view = viewMap.remove(id);
      if (view != null) ordered.add(view);
    }
    ordered.addAll(viewMap.values);
    return ordered;
  }

  void clear() {
    state = ViewsModel();
  }
}

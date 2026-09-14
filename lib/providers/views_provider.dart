import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/models/views_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/row_limits.dart';

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

/// A library, as far as asking for its rows goes.
typedef LibraryKey = ({String id, CollectionType type});

extension ViewModelLibraryKey on ViewModel {
  LibraryKey get libraryKey => (id: id, type: collectionType);
}

/// A library's Latest row, or why there is none.
typedef _LatestResult = (List<ItemBaseModel>? items, Object? error, StackTrace? stackTrace);

class ViewsNotifier extends StateNotifier<ViewsModel> {
  ViewsNotifier(this.ref) : super(ViewsModel()) {
    // The views can be written before a refresh of the account lands - when
    // the list came back first and no refresh was under way yet to wait for.
    // The order of the libraries and which of them have a row on the
    // dashboard come with that refresh, so they are applied again when it
    // changes them, from what is already here.
    ref.listen(
      userProvider.select((user) => (user?.userConfiguration?.orderedViews, user?.latestItemsExcludes)),
      (previous, next) {
        if (previous == null || state.views.isEmpty) return;
        if (listEquals(previous.$1, next.$1) && listEquals(previous.$2, next.$2)) return;
        final views = _applyLibraryOrdering(state.views);
        state = state.copyWith(views: views, dashboardViews: _dashboardViewsOf(views));
      },
    );
  }

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
    // The set is only to ask whether the list already holds an id: `contains`
    // on the list is a scan, once per item, and these rows are longer now.
    final seen = <String>{};
    final bySeriesId = <String, ItemBaseModel>{};
    final seriesToFetch = <String>{};
    for (final item in items) {
      final seriesId = seriesIdOf(item);
      final id = seriesId ?? item.id;
      if (seen.add(id)) orderedIds.add(id);
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

  /// The fetch that is under way, if one is.
  ///
  /// Three things ask for the views on the first frame - the scaffold, the
  /// drawer and the dashboard's own refresh - and each used to get its own
  /// round of requests: the views, then the latest items of every library,
  /// three times over. The `loading` flag was meant to stop that, but nothing
  /// ever set it. One fetch now serves every caller that arrives while it is
  /// in flight.
  Future<ViewsModel?>? _inFlight;

  Future<ViewsModel?> fetchViews() => _inFlight ??= _fetchViews().whenComplete(() => _inFlight = null);

  /// The libraries of the fetch under way, once the server has listed them.
  Completer<List<ViewModel>>? _listed;

  /// The libraries the dashboard draws, as soon as they are known.
  ///
  /// While a fetch is under way this is done when the list of libraries is
  /// back - one round trip - rather than when every library's Latest row is,
  /// and its views carry no rows. The dashboard only needs to know which
  /// libraries there are to decide what else to ask for, and waiting for the
  /// Latest rows as well kept the whole top of the page behind them. With no
  /// fetch under way it is what is already known. Never fails.
  Future<List<ViewModel>> dashboardViewList() => _listed?.future ?? Future.value(state.dashboardViews);

  bool _excludedFromLatest(String id) => ref.read(userProvider)?.latestItemsExcludes.contains(id) == true;

  Future<ViewsModel?> _fetchViews() async {
    final listed = _listed = Completer<List<ViewModel>>();
    try {
      final showAllCollections = ref.read(clientSettingsProvider.select((value) => value.showAllCollectionTypes));
      final response = await api.usersUserIdViewsGet();
      final createdViews = response.body?.items?.map((e) => ViewModel.fromBodyDto(e, ref)).where((element) {
        return showAllCollections ? true : enableCollectionTypes.contains(element.collectionType);
      }).toList();

      List<ViewModel> newList = [];

      if (createdViews != null) {
        // Every library's Latest row goes out now, before a refresh of the
        // account that may be under way has landed: which libraries are left
        // out comes from the stored account, and is checked again below.
        final latest = <String, Future<_LatestResult>>{
          for (final view in createdViews)
            if (!_excludedFromLatest(view.id)) view.id: _guarded(_fetchLatest(view.libraryKey, showAllCollections)),
        };

        // The order of the libraries is part of the user's configuration, which
        // is not stored between launches. Waiting for it here rather than before
        // the list is asked for costs nothing when it is already back.
        await ref.read(userProvider.notifier).informationSettled;
        if (!listed.isCompleted) listed.complete(_dashboardViewsOf(createdViews));

        newList = await Future.wait(createdViews.map((e) async {
          final pending = latest[e.id] ??
              (_excludedFromLatest(e.id) ? null : _guarded(_fetchLatest(e.libraryKey, showAllCollections)));
          if (pending == null) return e;
          final (recentModels, error, stackTrace) = await pending;
          if (error != null) Error.throwWithStackTrace(error, stackTrace ?? StackTrace.current);
          return e.copyWith(recentlyAdded: recentModels);
        }));
      } else {
        await ref.read(userProvider.notifier).informationSettled;
      }

      state = state.copyWith(
          views: _applyLibraryOrdering(newList), dashboardViews: _dashboardViewsOf(newList), loading: false);
      if (!listed.isCompleted) listed.complete(state.dashboardViews);
      return state;
    } catch (e) {
      if (!listed.isCompleted) listed.complete(state.dashboardViews);
      return state.copyWith(loading: false);
    } finally {
      if (identical(_listed, listed)) _listed = null;
    }
  }

  /// The libraries with a row on the dashboard, in the user's order.
  List<ViewModel> _dashboardViewsOf(List<ViewModel> views) => _applyLibraryOrdering(
      views.where((element) => !(ref.read(userProvider)?.latestItemsExcludes.contains(element.id) ?? true)).toList());

  /// Settles with the answer or the failure, so that a failing request that
  /// nobody is awaiting yet is not reported as unhandled.
  static Future<_LatestResult> _guarded(Future<List<ItemBaseModel>?> request) =>
      request.then((value) => (value, null, null),
          onError: (Object error, StackTrace stackTrace) => (null, error, stackTrace));

  Future<List<ItemBaseModel>?> _fetchLatest(LibraryKey e, bool showAllCollections) async {
    final recents = await api.usersUserIdItemsLatestGet(
      parentId: e.id,
      imageTypeLimit: 1,
      limit: kCategoryRowItemLimit,
      includeItemTypes: (e.type == CollectionType.books && !showAllCollections) ? [BaseItemKind.book] : null,
      enableImageTypes: [
        ImageType.primary,
        ImageType.backdrop,
        ImageType.thumb,
        // Without this the server returns no logo tag at all, and a detail
        // page opened from one of these cards has no logo to show. It draws
        // the name as text instead, then swaps the text for the logo when
        // its own request comes back - the largest thing on the page
        // changing shape a moment after it was read. The rows beside this
        // one have always asked for it.
        ImageType.logo,
      ],
      fields: [
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.candelete,
        ItemFields.candownload,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
        // Likewise: genres belong to the item, and a page opened from here
        // otherwise waits on a request for something the card could have
        // carried.
        ItemFields.genres,
      ],
    );
    var recentModels = recents.body?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList();
    if (e.type == CollectionType.tvshows && recentModels != null) {
      recentModels = await _collapseEpisodesToSeries(recentModels);
    }
    return recentModels;
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

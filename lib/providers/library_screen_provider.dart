import 'package:flutter/material.dart' hide ConnectionState;

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/models/collection_types.dart';
import 'package:chudder/models/book_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/recommended_model.dart';
import 'package:chudder/models/view_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/row_limits.dart';

part 'library_screen_provider.freezed.dart';
part 'library_screen_provider.g.dart';

enum LibraryViewType {
  recommended,
  favourites,
  genres;

  const LibraryViewType();

  String label(BuildContext context) => switch (this) {
        LibraryViewType.recommended => context.localized.recommended,
        LibraryViewType.favourites => context.localized.favorites,
        LibraryViewType.genres => context.localized.genre(2),
      };

  IconData get icon => switch (this) {
        LibraryViewType.recommended => IconsaxPlusLinear.star,
        LibraryViewType.favourites => IconsaxPlusLinear.heart,
        LibraryViewType.genres => IconsaxPlusLinear.hierarchy_3,
      };

  IconData get iconSelected => switch (this) {
        LibraryViewType.recommended => IconsaxPlusBold.star,
        LibraryViewType.favourites => IconsaxPlusBold.heart,
        LibraryViewType.genres => IconsaxPlusBold.hierarchy_3,
      };
}

@Freezed(fromJson: false, toJson: false, copyWith: true)
abstract class LibraryScreenModel with _$LibraryScreenModel {
  factory LibraryScreenModel({
    @Default([]) List<ViewModel> views,
    ViewModel? selectedViewModel,
    @Default({LibraryViewType.recommended, LibraryViewType.favourites, LibraryViewType.genres})
    Set<LibraryViewType> viewType,
    @Default([]) List<RecommendedModel> recommendations,
    @Default([]) List<RecommendedModel> genres,
    @Default([]) List<ItemBaseModel> favourites,
  }) = _LibraryScreenModel;
}

@Riverpod(keepAlive: true)
class LibraryScreen extends _$LibraryScreen {
  late final JellyService api = ref.read(jellyApiProvider);

  @override
  LibraryScreenModel build() => LibraryScreenModel();

  /// The library whose rows were last asked for online, so a refresh can tell
  /// another library picked from the row from somebody asking for this one
  /// again.
  String? _rowsLoadedFor;

  /// The libraries, then the rows of the one selected.
  ///
  /// [reuseKnownViews] takes the libraries the app already fetched at start -
  /// the dashboard and the sidebar use the same list - instead of asking for
  /// them, and every library's newest items, all over again before the first
  /// row could be asked for.
  Future<void> fetchAllLibraries({bool reuseKnownViews = false}) async {
    // The library is a list of server-side views, so offline there is nothing
    // to list and the screen came up blank. Stand in views built from what is
    // downloaded instead, so the tab still leads somewhere.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      _rowsLoadedFor = null;
      await _fetchOfflineLibraries();
      return;
    }

    // Another library picked from the row on screen: its rows are what
    // changed, not the list of libraries. Refetching that list - and the
    // newest items of every library with it - held the new rows back on
    // every switch. Asking again for the library already shown still does.
    final selected = state.selectedViewModel;
    if (_rowsLoadedFor != null && selected != null && selected.id != _rowsLoadedFor && state.views.contains(selected)) {
      await loadLibrary(selected);
      return;
    }

    final known = reuseKnownViews ? ref.read(viewsProvider).views : const <ViewModel>[];
    final views = known.isNotEmpty ? known : (await ref.read(viewsProvider.notifier).fetchViews())?.views ?? [];
    state = state.copyWith(
      views: views.toList(),
    );
    if (state.views.isEmpty) return;
    final viewModel = state.selectedViewModel ?? _defaultView(state.views);
    if (viewModel == null) return;
    selectLibrary(viewModel);
    await loadLibrary(viewModel);
  }

  /// The libraries that say least about what there is to watch, so the tab
  /// does not open on one of them.
  static const _lastResortTypes = {CollectionType.boxsets, CollectionType.playlists};

  /// Which library the tab opens on before anything has been chosen.
  ///
  /// It was the first of the server's own order, and that order puts
  /// Collections first often enough: a wall of boxsets is the least useful
  /// thing to land on, since it says nothing about what there is to watch.
  /// Prefer the first library that holds media of its own, and fall back to
  /// the server's order when every one of them is a collection.
  ViewModel? _defaultView(List<ViewModel> views) =>
      views.firstWhereOrNull((view) => !_lastResortTypes.contains(view.collectionType)) ?? views.firstOrNull;

  /// The library as the download folder sees it: one view per kind of thing
  /// actually on disk, each holding only what can be played right now.
  Future<void> _fetchOfflineLibraries() async {
    final downloaded = await ref.read(syncProvider.notifier).allDownloadedItems();

    ViewModel? viewFor(CollectionType type, String name, List<ItemBaseModel> items) {
      if (items.isEmpty) return null;
      return ViewModel(
        name: name,
        id: 'offline-${type.name}',
        serverId: '',
        dateCreated: DateTime.now(),
        canDelete: false,
        canDownload: false,
        parentId: '',
        collectionType: type,
        playAccess: PlayAccess.full,
        recentlyAdded: items,
        imageData: null,
        childCount: items.length,
        path: null,
      );
    }

    final episodes = downloaded.whereType<EpisodeModel>().cast<ItemBaseModel>().toList();
    final movies = downloaded.whereType<MovieModel>().cast<ItemBaseModel>().toList();
    final audio = downloaded.whereType<AudioModel>().cast<ItemBaseModel>().toList();
    final books = downloaded.whereType<BookModel>().cast<ItemBaseModel>().toList();

    final views = [
      viewFor(CollectionType.tvshows, 'Shows', episodes),
      viewFor(CollectionType.movies, 'Movies', movies),
      viewFor(CollectionType.music, 'Music', audio),
      viewFor(CollectionType.books, 'Books', books),
    ].nonNulls.toList();

    // Keep the chosen library across a connectivity change where it still
    // exists, so going offline does not silently jump the user elsewhere.
    final previous = state.selectedViewModel;
    final selected = views.firstWhereOrNull((view) => view.id == previous?.id) ?? views.firstOrNull;

    state = state.copyWith(views: views, selectedViewModel: selected, genres: []);

    if (selected == null) {
      state = state.copyWith(recommendations: [], favourites: []);
      return;
    }

    _buildOfflineRows(selected);
  }

  /// Rows for one offline view, from the items it already holds.
  void _buildOfflineRows(ViewModel view) {
    final items = view.recentlyAdded;
    bool started(ItemBaseModel item) => item.userData.progress > 0 && !item.userData.played;

    state = state.copyWith(
      recommendations: [
        RecommendedModel(name: const Continue(), posters: items.where(started).toList()),
        RecommendedModel(
          name: const Latest(),
          posters: items.where((item) => !started(item)).toList(),
        ),
      ]..removeWhere((element) => element.posters.isEmpty),
      favourites: items.where((item) => item.userData.isFavourite).toList(),
      genres: [],
    );
  }

  Future<void> selectLibrary(ViewModel viewModel) async {
    state = state.copyWith(selectedViewModel: viewModel);
  }

  Future<void> setViewType(Set<LibraryViewType> type) async {
    state = state.copyWith(viewType: type);
  }

  Future<Response?> loadLibrary(ViewModel viewModel) async {
    // Offline the views already carry their items in memory, so the rows are
    // rebuilt from those rather than going back to the database - re-reading
    // it here doubled the cost of every library switch.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      _buildOfflineRows(viewModel);
      return null;
    }
    _rowsLoadedFor = viewModel.id;
    // Each fills its own rows, so none needs to wait for another.
    await Future.wait<void>([
      if (state.viewType.contains(LibraryViewType.recommended)) loadRecommendations(viewModel),
      if (state.viewType.contains(LibraryViewType.favourites)) loadFavourites(viewModel).then<void>((_) {}),
      if (state.viewType.contains(LibraryViewType.genres)) loadGenres(viewModel).then<void>((_) {}),
    ]);
    return null;
  }

  Future<void> loadResume(ViewModel viewModel) async {}

  /// Whether rows asked for [viewModel] came in after another library was
  /// picked. A switch starts the new library's rows at once, so the old
  /// library's slowest row can land after them and show under the new name.
  bool _pickedOtherThan(ViewModel viewModel) {
    final selected = state.selectedViewModel;
    return selected != null && selected.id != viewModel.id;
  }

  Future<void> loadRecommendations(ViewModel viewModel) async {
    RecommendedModel continueRecommendations = RecommendedModel(name: const Continue(), posters: []);
    RecommendedModel nextUpRecommendations = RecommendedModel(name: const NextUp(), posters: []);
    RecommendedModel latestRecommendations = RecommendedModel(name: const Latest(), posters: []);
    List<RecommendedModel> otherRecommendations = [];

    // All four started before any is waited for, so they overlap instead
    // of queueing behind one another.
    final resumeRequest = api.usersUserIdItemsResumeGet(
      parentId: viewModel.id,
      limit: kRowItemLimit,
      enableUserData: true,
      // The same shape the dashboard's rows hand over: with streams, so the
      // page an episode opens has its language pickers on the first frame
      // instead of a request later. See [DashboardNotifier].
      fields: [
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.overview,
        ItemFields.primaryimageaspectratio,
      ],
      enableImageTypes: [
        ImageType.primary,
        ImageType.banner,
        ImageType.screenshot,
      ],
      mediaTypes: [MediaType.video],
      enableTotalRecordCount: false,
    );
    final moviesRequest = viewModel.collectionType == CollectionType.movies
        ? api.moviesRecommendationsGet(
            parentId: viewModel.id,
            categoryLimit: 6,
            fields: [
              ItemFields.overview,
              ItemFields.primaryimageaspectratio,
            ],
            itemLimit: kCategoryRowItemLimit,
          )
        : null;
    final nextUpRequest = api.showsNextUpGet(
      parentId: viewModel.id,
      limit: kRowItemLimit,
      imageTypeLimit: 1,
      // As above: the same shape as the dashboard's next-up row.
      fields: [
        ItemFields.parentid,
        ItemFields.mediastreams,
        ItemFields.mediasources,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
    );
    final latestRequest = api.usersUserIdItemsGet(
      parentId: viewModel.id,
      sortBy: [ItemSortBy.datelastcontentadded, ItemSortBy.datecreated, ItemSortBy.sortname],
      sortOrder: [SortOrder.descending],
      limit: kRowItemLimit,
      includeItemTypes: viewModel.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
    );

    final resume = await resumeRequest;
    continueRecommendations = RecommendedModel(
      name: const Continue(),
      posters: resume.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [],
      type: null,
    );

    if (moviesRequest != null) {
      final response = await moviesRequest;
      otherRecommendations = (response.body?.map(
                (e) => RecommendedModel.fromBaseDto(e, ref),
              ) ??
              [])
          .toList();
    }

    final nextUp = await nextUpRequest;
    final latest = await latestRequest;
    latestRecommendations = RecommendedModel(
      name: const Latest(),
      posters: latest.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [],
      type: null,
    );

    nextUpRecommendations = RecommendedModel(
      name: const NextUp(),
      posters: nextUp.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [],
      type: null,
    );

    if (_pickedOtherThan(viewModel)) return;
    state = state.copyWith(
      recommendations: [
        continueRecommendations,
        nextUpRecommendations,
        latestRecommendations,
        ...otherRecommendations,
      ]..removeWhere((element) => element.posters.isEmpty),
    );
  }

  Future<Response?> loadFavourites(ViewModel viewModel) async {
    final response = await api.itemsGet(
      parentId: viewModel.id,
      isFavorite: true,
      recursive: true,
      limit: kRowItemLimit,
      includeItemTypes: viewModel.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
      enableImageTypes: [ImageType.primary],
      fields: [
        ItemFields.mediasourcecount,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
      enableTotalRecordCount: false,
    );

    if (_pickedOtherThan(viewModel)) return response;
    state = state.copyWith(favourites: response.body?.items ?? []);
    return response;
  }

  /// The library whose genre rows are the ones in state, so they are not asked
  /// for again while you are still looking at them.
  String? _genresLoadedFor;

  Future<Response?> loadGenres(ViewModel viewModel, {bool force = false}) async {
    // These rows are asked for `sortBy: random`, so asking again deals a new
    // hand: a refresh meant only to catch up on what has been watched replaced
    // every genre row with a different set of films, which reads as the page
    // having been swapped for someone else's. It is also the most expensive
    // thing here - one request per genre, and a library can have forty. Once
    // per library until the library changes, or somebody asks for a new deal.
    if (!force && _genresLoadedFor == viewModel.id && state.genres.isNotEmpty) return null;

    final genres = await api.genresGet(
      sortBy: [ItemSortBy.sortname],
      sortOrder: [SortOrder.ascending],
      includeItemTypes:
          viewModel.collectionType == CollectionType.movies ? [BaseItemKind.movie] : [BaseItemKind.series],
      parentId: viewModel.id,
    );

    final filteredGenres = (genres.body?.items?.map(
              (item) => GenreItems(id: item.id ?? "", name: item.name ?? ""),
            ) ??
            [])
        .toList();

    if (filteredGenres.isEmpty) return null;

    final futures = filteredGenres.map((genre) {
      return api
          .itemsGet(
        parentId: viewModel.id,
        genreIds: [genre.id],
        limit: kCategoryRowItemLimit,
        recursive: true,
        includeItemTypes: viewModel.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
        enableImageTypes: [ImageType.primary],
        fields: [
          ItemFields.mediasourcecount,
          ItemFields.primaryimageaspectratio,
          ItemFields.overview,
        ],
        sortBy: [ItemSortBy.random],
        enableTotalRecordCount: false,
        imageTypeLimit: 1,
        sortOrder: [SortOrder.ascending],
      )
          .then((response) {
        final items = response.body?.items;
        if (items != null && items.isNotEmpty) {
          return RecommendedModel(name: Other(genre.name), posters: items);
        }
        return null;
      });
    }).toList();

    // A few at a time. A library can have forty genres, and forty requests
    // at once starved the rows above these of the connections they needed.
    final results = <RecommendedModel?>[];
    for (var i = 0; i < futures.length; i += 6) {
      results.addAll(await Future.wait(futures.sublist(i, (i + 6).clamp(0, futures.length))));
    }

    if (_pickedOtherThan(viewModel)) return null;
    state = state.copyWith(
      genres: results.whereType<RecommendedModel>().toList(),
    );
    _genresLoadedFor = viewModel.id;

    return null;
  }

  void clear() {
    state = LibraryScreenModel();
    _genresLoadedFor = null;
    _rowsLoadedFor = null;
  }
}

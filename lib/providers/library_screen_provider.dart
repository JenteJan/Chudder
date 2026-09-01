import 'package:flutter/material.dart' hide ConnectionState;

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/collection_types.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/recommended_model.dart';
import 'package:fladder/models/view_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/util/localization_helper.dart';

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
    @Default({LibraryViewType.recommended, LibraryViewType.favourites}) Set<LibraryViewType> viewType,
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

  Future<void> fetchAllLibraries() async {
    // The library is a list of server-side views, so offline there is nothing
    // to list and the screen came up blank. Stand in views built from what is
    // downloaded instead, so the tab still leads somewhere.
    if (ref.read(connectivityStatusProvider) == ConnectionState.offline) {
      await _fetchOfflineLibraries();
      return;
    }

    final views = await ref.read(viewsProvider.notifier).fetchViews();
    state = state.copyWith(
      views: views?.views.toList() ?? [],
    );
    if (state.views.isEmpty) return;
    final viewModel = state.selectedViewModel ?? state.views.firstOrNull;
    if (viewModel == null) return;
    selectLibrary(viewModel);
    await loadLibrary(viewModel);
  }

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
    if (state.viewType.contains(LibraryViewType.recommended)) {
      await loadRecommendations(viewModel);
    }
    if (state.viewType.contains(LibraryViewType.favourites)) {
      await loadFavourites(viewModel);
    }
    if (state.viewType.contains(LibraryViewType.genres)) {
      await loadGenres(viewModel);
    }
    return null;
  }

  Future<void> loadResume(ViewModel viewModel) async {}

  Future<void> loadRecommendations(ViewModel viewModel) async {
    RecommendedModel continueRecommendations = RecommendedModel(name: const Continue(), posters: []);
    RecommendedModel nextUpRecommendations = RecommendedModel(name: const NextUp(), posters: []);
    RecommendedModel latestRecommendations = RecommendedModel(name: const Latest(), posters: []);
    List<RecommendedModel> otherRecommendations = [];

    final resume = await api.usersUserIdItemsResumeGet(
      parentId: viewModel.id,
      limit: 9,
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
    continueRecommendations = RecommendedModel(
      name: const Continue(),
      posters: resume.body?.items?.map((e) => ItemBaseModel.fromBaseDto(e, ref)).toList() ?? [],
      type: null,
    );

    if (viewModel.collectionType == CollectionType.movies) {
      final response = await api.moviesRecommendationsGet(
        parentId: viewModel.id,
        categoryLimit: 6,
        fields: [
          ItemFields.overview,
          ItemFields.primaryimageaspectratio,
        ],
        itemLimit: 9,
      );
      otherRecommendations = (response.body?.map(
                (e) => RecommendedModel.fromBaseDto(e, ref),
              ) ??
              [])
          .toList();
    }

    final nextUp = await api.showsNextUpGet(
      parentId: viewModel.id,
      limit: 9,
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
    final latest = await api.usersUserIdItemsGet(
      parentId: viewModel.id,
      sortBy: [ItemSortBy.datelastcontentadded, ItemSortBy.datecreated, ItemSortBy.sortname],
      sortOrder: [SortOrder.descending],
      limit: 9,
      includeItemTypes: viewModel.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
    );
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
      limit: 9,
      includeItemTypes: viewModel.collectionType.itemKinds.expand((e) => e.dtoKind).toList(),
      enableImageTypes: [ImageType.primary],
      fields: [
        ItemFields.mediasourcecount,
        ItemFields.primaryimageaspectratio,
        ItemFields.overview,
      ],
      enableTotalRecordCount: false,
    );

    state = state.copyWith(favourites: response.body?.items ?? []);
    return response;
  }

  Future<Response?> loadGenres(ViewModel viewModel) async {
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
        limit: 9,
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

    final results = await Future.wait(futures);

    state = state.copyWith(
      genres: results.whereType<RecommendedModel>().toList(),
    );

    return null;
  }

  void clear() {
    state = LibraryScreenModel();
  }
}

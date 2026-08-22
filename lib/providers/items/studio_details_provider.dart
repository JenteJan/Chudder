import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/items/remote_item_image_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/seerr_service_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';

/// What a studio page shows: the studio itself, what of theirs is in the
/// library, and — when Jellyseerr is set up — what of theirs is not.
///
/// Jellyfin has no catalogue of everything a studio ever made, only what it has
/// indexed, so the second list is what turns this from a shelf into something
/// closer to a filmography.
class StudioDetails {
  const StudioDetails({
    this.studio,
    this.movies = const [],
    this.series = const [],
    this.discoverMovies = const [],
    this.logoUrl,
    this.loading = true,
  });

  final ItemBaseModel? studio;
  final List<MovieModel> movies;
  final List<SeriesModel> series;

  /// Films by this studio that the server does not have.
  final List<SeerrDashboardPosterModel> discoverMovies;

  /// A logo from somewhere other than the library, for when Jellyfin holds no
  /// artwork of its own — which, for a studio, is most of the time.
  final String? logoUrl;

  final bool loading;

  bool get isEmpty => movies.isEmpty && series.isEmpty && discoverMovies.isEmpty;

  StudioDetails copyWith({
    ItemBaseModel? studio,
    List<MovieModel>? movies,
    List<SeriesModel>? series,
    List<SeerrDashboardPosterModel>? discoverMovies,
    String? logoUrl,
    bool? loading,
  }) =>
      StudioDetails(
        studio: studio ?? this.studio,
        movies: movies ?? this.movies,
        series: series ?? this.series,
        discoverMovies: discoverMovies ?? this.discoverMovies,
        logoUrl: logoUrl ?? this.logoUrl,
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
  late final SeerrService seerrApi = ref.read(seerrApiProvider);

  /// Two pages is around forty films — enough to be a filmography for all but
  /// the majors, without paging the whole of Warner Bros. into a phone.
  static const _discoverPages = 2;

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

    await _fetchRemoteLogo();
    await _fetchFromSeerr();
  }

  /// Ask the server what artwork its own metadata providers can see for this
  /// studio.
  ///
  /// This is how a logo arrives without the app holding a TMDB key of its own:
  /// the Jellyfin instance already has those providers configured, so it is the
  /// one that goes and looks. It needs an admin account and it may find
  /// nothing, in which case the page just carries the studio's name.
  /// The artwork the server's own metadata providers can see, when the library
  /// holds none. Shared with the search results, which ask the same question.
  Future<void> _fetchRemoteLogo() async {
    final images = state.studio?.images;
    if (images?.logo != null || images?.primary != null) return;

    final url = await ref.read(remoteItemImageProvider(studioId).future);
    if (!mounted || url == null) return;
    state = state.copyWith(logoUrl: url);
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

  /// TMDB knows studios by company id, and Jellyfin does not record one, so the
  /// name is the only way across. An exact match is required rather than the
  /// first hit: searching "A24" also returns companies that merely contain it.
  Future<void> _fetchFromSeerr() async {
    final name = state.studio?.name;
    if (name == null || name.isEmpty) return;
    if (ref.read(userProvider)?.seerrCredentials?.isConfigured != true) return;

    final SeerrCompany company;
    try {
      final response = await seerrApi.searchCompany(query: name);
      final companies = response.body?.results ?? const <SeerrCompany>[];
      if (companies.isEmpty) return;
      company = companies.firstWhere(
        (candidate) => candidate.name.toLowerCase() == name.toLowerCase(),
        orElse: () => companies.first,
      );
    } catch (_) {
      return;
    }

    // Only if the server could not name one itself.
    if (state.logoUrl == null && company.logoUrl != null) {
      state = state.copyWith(logoUrl: company.logoUrl);
    }

    final missing = <SeerrDashboardPosterModel>[];
    final seen = <String>{};
    for (var page = 1; page <= _discoverPages; page++) {
      final List<SeerrDiscoverItem> items;
      try {
        final response = await seerrApi.discoverMovies(
          studio: company.id,
          page: page,
          sortBy: 'popularity.desc',
        );
        items = response.body?.results ?? const [];
      } catch (_) {
        break;
      }
      if (items.isEmpty) break;

      for (final item in items) {
        // Anything the server already has is a row above this one.
        if (item.mediaInfo?.primaryJellyfinMediaId != null) continue;
        final poster = seerrApi.posterFromDiscoverItem(item);
        if (poster == null || !seen.add(poster.id)) continue;
        missing.add(poster);
      }
    }

    if (!mounted) return;
    state = state.copyWith(discoverMovies: missing);
  }
}

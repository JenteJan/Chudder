import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/seerr/seerr_dashboard_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/seerr_service_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/seerr/seerr_models.dart';

final personDetailsProvider =
    StateNotifierProvider.autoDispose.family<PersonDetailsNotifier, PersonModel?, String>((ref, id) {
  return PersonDetailsNotifier(ref);
});

class PersonDetailsNotifier extends StateNotifier<PersonModel?> {
  PersonDetailsNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);
  late final SeerrService seerrApi = ref.read(seerrApiProvider);

  Future<Response?> fetchPerson(Person person) async {
    // The credits are asked for by the person's id, which the page already
    // has, so they go out with the person rather than after it. They are
    // shown once the person has arrived, as before, and both at once: the
    // backdrop is picked from them together, and a second pick would swap it.
    final credits = Future.wait([
      _fetchCredits(person.id, BaseItemKind.movie),
      _fetchCredits(person.id, BaseItemKind.series),
    ])
      ..ignore();

    final response = await api.usersUserIdItemsItemIdGet(itemId: person.id);

    if (!mounted || !response.isSuccessful || response.body == null) {
      return response;
    }

    state = response.bodyOrThrow as PersonModel;

    await Future.wait([
      credits.then((results) {
        if (!mounted) return;
        state = state?.copyWith(
          movies: results.first?.whereType<MovieModel>().toList(),
          series: results.last?.whereType<SeriesModel>().toList(),
        );
      }),
      fetchSeerrCredits(),
    ]);

    return response;
  }

  Future<List<ItemBaseModel>?> _fetchCredits(String personId, BaseItemKind kind) async {
    final response = await api.itemsGet(
      personIds: [personId],
      limit: 25,
      sortBy: [ItemSortBy.premieredate, ItemSortBy.communityrating, ItemSortBy.sortname, ItemSortBy.productionyear],
      sortOrder: [SortOrder.descending],
      recursive: true,
      fields: [
        ItemFields.primaryimageaspectratio,
      ],
      includeItemTypes: [kind],
    );
    return response.body?.items;
  }

  int? _tmdbPersonId() {
    final ids = state?.providerIds;
    if (ids == null) return null;

    final dynamic rawId = ids['Tmdb'] ?? ids['tmdb'] ?? ids['TMDB'] ?? ids['tmdbId'];
    if (rawId == null) return null;
    if (rawId is int) return rawId;
    if (rawId is num) return rawId.toInt();
    if (rawId is String) return int.tryParse(rawId);
    return null;
  }

  Future<void> fetchSeerrCredits() async {
    if (state == null) return;

    final seerrCredentials = ref.read(userProvider)?.seerrCredentials;
    if (seerrCredentials?.isConfigured != true) {
      state = state?.copyWith(seerrMovies: const [], seerrSeries: const []);
      return;
    }

    final tmdbPersonId = _tmdbPersonId();
    if (tmdbPersonId == null) {
      state = state?.copyWith(seerrMovies: const [], seerrSeries: const []);
      return;
    }

    final response = await seerrApi.personCombinedCredits(personId: tmdbPersonId);
    if (!mounted) return;
    if (!response.isSuccessful || response.body == null) {
      state = state?.copyWith(seerrMovies: const [], seerrSeries: const []);
      return;
    }

    final credits = response.body!;
    final creditItems = <SeerrPersonCredit>[
      ...credits.cast ?? <SeerrPersonCredit>[],
      ...credits.crew ?? <SeerrPersonCredit>[],
    ];

    final posters = creditItems
        .where((credit) => credit.mediaInfo?.primaryJellyfinMediaId == null)
        .map((credit) => seerrApi.posterFromPersonCredit(credit))
        .whereType<SeerrDashboardPosterModel>()
        .toList();

    posters.sort(_sortPostersByNewestFirst);

    final seenIds = <String>{};
    final uniquePosters = posters.where((poster) => seenIds.add(poster.id)).toList();

    state = state?.copyWith(
      seerrMovies: uniquePosters.where((poster) => poster.type == SeerrMediaType.movie).toList(),
      seerrSeries: uniquePosters.where((poster) => poster.type == SeerrMediaType.tvshow).toList(),
    );
  }

  int _posterReleaseYear(SeerrDashboardPosterModel poster) {
    final year = poster.releaseYear;
    if (year == null) return 0;
    return int.tryParse(year) ?? 0;
  }

  int _sortPostersByNewestFirst(SeerrDashboardPosterModel a, SeerrDashboardPosterModel b) {
    final yearA = _posterReleaseYear(a);
    final yearB = _posterReleaseYear(b);
    final yearComparison = yearB.compareTo(yearA);
    if (yearComparison != 0) return yearComparison;
    return b.title.compareTo(a.title);
  }
}

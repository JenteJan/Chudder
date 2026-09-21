import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/models/items/person_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/seerr/seerr_dashboard_model.dart';
import 'package:chudder/providers/items/person_details_prefetch_provider.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/seerr_service_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/seerr/seerr_models.dart';

/// The id a person page is opened with for someone only Seerr knows: their
/// TMDB id, marked so it is never mistaken for one of the server's.
String seerrPersonId(String tmdbId) => 'tmdb:$tmdbId';

/// The TMDB id in a [seerrPersonId], or null for one of the server's people.
int? seerrPersonTmdbId(String id) => id.startsWith('tmdb:') ? int.tryParse(id.substring(5)) : null;

final personDetailsProvider =
    StateNotifierProvider.autoDispose.family<PersonDetailsNotifier, PersonModel?, String>((ref, id) {
  // Someone opened before is shown as they were straight away; the page's
  // own load asks again over it.
  return PersonDetailsNotifier(ref, ref.read(personDetailsPrefetchProvider).of(id));
});

class PersonDetailsNotifier extends StateNotifier<PersonModel?> {
  PersonDetailsNotifier(this.ref, [PersonModel? known]) : super(known);

  final Ref ref;

  late final SeerrService seerrApi = ref.read(seerrApiProvider);

  Future<Response?> fetchPerson(Person person) async {
    final tmdbId = seerrPersonTmdbId(person.id);
    if (tmdbId != null) return _fetchSeerrPerson(person, tmdbId);

    // Joined, if a hover or a focus on the person's face already sent them.
    // The credits go out with the person rather than after it, and are shown
    // once it has arrived, both at once: the backdrop is picked from them
    // together, and a second pick would swap it.
    final prefetch = ref.read(personDetailsPrefetchProvider);
    final requests = prefetch.request(person.id);
    final credits = Future.wait([requests.movies, requests.series])..ignore();

    final response = await requests.person;

    if (!mounted || !response.isSuccessful || response.body == null) {
      return response;
    }

    // What is already on screen stays until its replacement arrives: a page
    // opened from what we kept, or pulled to refresh, would otherwise empty
    // its rows and fill them again.
    final previous = state;
    state = (response.bodyOrThrow as PersonModel).copyWith(
      movies: previous?.movies,
      series: previous?.series,
      seerrMovies: previous?.seerrMovies,
      seerrSeries: previous?.seerrSeries,
    );

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

    final shown = state;
    if (mounted && shown != null) prefetch.remember(shown);

    return response;
  }

  /// Someone the library does not have, from Seerr: who they are, and
  /// everything they were in as posters to request.
  Future<Response?> _fetchSeerrPerson(Person person, int tmdbId) async {
    final response = await seerrApi.person(personId: tmdbId);
    if (!mounted || !response.isSuccessful || response.body == null) return response;

    final details = response.body!;
    final previous = state;
    final portrait = details.portraitUrl;
    state = PersonModel(
      id: person.id,
      name: details.name ?? person.name,
      overview: OverviewModel(summary: details.biography ?? ''),
      images: ImagesData(
        primary: portrait != null ? ImageData(path: portrait, key: 'seerr_person_$tmdbId') : person.image,
      ),
      dateOfBirth: DateTime.tryParse(details.birthday ?? ''),
      dateOfDeath: DateTime.tryParse(details.deathday ?? ''),
      birthPlace: [if (details.placeOfBirth?.isNotEmpty ?? false) details.placeOfBirth!],
      providerIds: {'Tmdb': tmdbId.toString(), if (details.imdbId != null) 'Imdb': details.imdbId},
      movies: const [],
      series: const [],
      seerrMovies: previous?.seerrMovies ?? const [],
      seerrSeries: previous?.seerrSeries ?? const [],
      parentId: null,
      playlistId: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
    );

    // Nothing of theirs is in the library, or they would be too - so no
    // credit is left out for being there.
    await fetchSeerrCredits(includeLibrary: true);
    final shown = state;
    if (mounted && shown != null) ref.read(personDetailsPrefetchProvider).remember(shown);
    return response;
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

  Future<void> fetchSeerrCredits({bool includeLibrary = false}) async {
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
        .where((credit) => includeLibrary || credit.mediaInfo?.primaryJellyfinMediaId == null)
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

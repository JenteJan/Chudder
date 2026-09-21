import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/models/external_ratings_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/seerr/seerr_dashboard_model.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/seerr_user_provider.dart';
import 'package:chudder/seerr/seerr_models.dart';
import 'package:chudder/util/external_links.dart';
import 'package:chudder/util/seerr_helpers.dart';

part 'seerr_details_provider.freezed.dart';
part 'seerr_details_provider.g.dart';

@riverpod
class SeerrDetails extends _$SeerrDetails {
  late final api = ref.read(seerrApiProvider);

  @override
  SeerrDetailsModel build({
    required int tmdbId,
    required SeerrMediaType mediaType,
    SeerrDashboardPosterModel? poster,
  }) {
    state = SeerrDetailsModel(
      tmdbId: tmdbId,
      mediaType: mediaType,
      poster: poster,
      recommended: const [],
      similar: const [],
    );

    fetch();

    return state;
  }

  Future<void> fetch() async {
    final currentTmdbId = state.tmdbId;
    final currentMediaType = state.mediaType;
    if (currentTmdbId == null || currentMediaType == null) return;

    SeerrDashboardPosterModel? poster = state.poster;

    final refreshedPoster = await api.fetchDashboardPosterFromIds(
      tmdbId: currentTmdbId,
      mediaType: currentMediaType,
    );

    poster = refreshedPoster ?? poster;
    if (poster == null) return;

    state = state.copyWith(poster: poster);

    final currentUserBody = await ref.read(seerrUserProvider.notifier).refreshUser();
    final isTv = currentMediaType == SeerrMediaType.tvshow;
    if (isTv) {
      final tvDetailsResponse = await api.tvDetails(tvId: poster.tmdbId);
      if (tvDetailsResponse.isSuccessful && tvDetailsResponse.body != null) {
        final details = tvDetailsResponse.body!;

        final seasonStatusMap = SeerrHelpers.buildSeasonStatusMap(details);

        final userRegion = currentUserBody?.settings?.discoverRegion ?? 'US';
        final contentRating = SeerrHelpers.extractContentRating(details.contentRatings, userRegion);

        final updatedPoster = poster.copyWith(
          seasons: details.seasons,
          seasonStatuses: seasonStatusMap.isEmpty ? poster.seasonStatuses : seasonStatusMap,
          mediaInfo: details.mediaInfo,
        );

        state = state.copyWith(
          poster: updatedPoster,
          genres: details.genres ?? [],
          relatedVideos: details.relatedVideos ?? const [],
          voteAverage: details.voteAverage,
          contentRating: contentRating,
          releaseDate: details.firstAirDate,
          originalTitle: details.originalName,
          runTime: _minutes(details.episodeRunTime?.firstOrNull),
          studios: [...?details.networks, ...?details.productionCompanies],
          people: _mapCredits(details.credits, createdBy: details.createdBy),
          seasonStatuses: updatedPoster.seasonStatuses ?? const {},
          externalIds: details.externalIds ?? state.externalIds,
          detailsLoaded: true,
        );
      }
    } else {
      final movieDetailsResponse = await api.movieDetails(tmdbId: poster.tmdbId);
      if (movieDetailsResponse.isSuccessful && movieDetailsResponse.body != null) {
        final details = movieDetailsResponse.body!;
        final userRegion = currentUserBody?.settings?.discoverRegion ?? 'US';
        final contentRating = SeerrHelpers.extractContentRating(details.contentRatings, userRegion);

        final updatedPoster = poster.copyWith(
          mediaInfo: details.mediaInfo,
        );

        state = state.copyWith(
          poster: updatedPoster,
          genres: details.genres ?? [],
          relatedVideos: details.relatedVideos ?? const [],
          voteAverage: details.voteAverage,
          contentRating: contentRating,
          releaseDate: details.releaseDate,
          originalTitle: details.originalTitle,
          runTime: _minutes(details.runtime),
          studios: details.productionCompanies ?? const [],
          people: _mapCredits(details.credits),
          externalIds: details.externalIds ?? state.externalIds,
          detailsLoaded: true,
        );
      }
    }

    final isMovie = currentMediaType == SeerrMediaType.movie;
    final rows = await Future.wait([
      isMovie
          ? api.discoverRecommendedMovies(tmdbId: poster.tmdbId)
          : api.discoverRecommendedSeries(tmdbId: poster.tmdbId),
      isMovie ? api.discoverRelatedMovies(tmdbId: poster.tmdbId) : api.discoverRelatedSeries(tmdbId: poster.tmdbId),
    ]);
    state = state.copyWith(recommended: rows[0], similar: rows[1]);

    state = state.copyWith(
      currentUser: currentUserBody,
      poster: poster.copyWith(
        mediaInfo: refreshedPoster?.mediaInfo == null ? null : poster.mediaInfo,
      ),
    );
  }

  static Duration? _minutes(int? minutes) => minutes == null || minutes <= 0 ? null : Duration(minutes: minutes);

  List<Person> _mapCredits(SeerrCredits? credits, {List<SeerrCrew>? createdBy}) {
    if (credits == null && (createdBy?.isEmpty ?? true)) return const [];

    final people = <Person>[];
    final seen = <String>{};

    void addPerson({
      int? id,
      required String name,
      String? role,
      String? profileUrl,
      PersonKind? type,
    }) {
      final safeName = name.trim();
      if (safeName.isEmpty) return;

      final dedupeKey = '${id ?? safeName}::${role ?? ''}';
      if (!seen.add(dedupeKey)) return;

      ImageData? image;
      if (profileUrl != null && profileUrl.isNotEmpty) {
        image = ImageData(path: profileUrl, key: 'seerr_person_${id ?? safeName.hashCode}');
      }

      people.add(
        Person(
          id: (id ?? safeName.hashCode).toString(),
          name: safeName,
          role: role ?? '',
          image: image,
          type: type,
        ),
      );
    }

    // A show's creators are not in its crew, and they are who the header's
    // "Created by" names.
    for (final creator in createdBy ?? const <SeerrCrew>[]) {
      addPerson(
        id: creator.id,
        name: creator.name ?? '',
        role: creator.job,
        profileUrl: creator.profileUrl,
        type: PersonKind.creator,
      );
    }

    for (final cast in credits?.cast ?? const <SeerrCast>[]) {
      addPerson(
        id: cast.id,
        name: cast.name ?? '',
        role: (cast.character?.trim().isEmpty ?? true) ? null : cast.character,
        profileUrl: cast.profileUrl,
        type: PersonKind.actor,
      );
    }

    for (final crew in credits?.crew ?? const <SeerrCrew>[]) {
      addPerson(
        id: crew.id,
        name: crew.name ?? '',
        role: (crew.job?.trim().isEmpty ?? true) ? crew.department : crew.job,
        profileUrl: crew.profileUrl,
        type: _mapCrewKind(crew.job),
      );
    }

    return people;
  }

  PersonKind _mapCrewKind(String? job) {
    final normalized = job?.toLowerCase().trim();
    if (normalized == null || normalized.isEmpty) return PersonKind.unknown;
    if (normalized.contains('director')) return PersonKind.director;
    if (normalized.contains('producer')) return PersonKind.producer;
    if (normalized.contains('writer') || normalized.contains('screenplay') || normalized.contains('story')) {
      return PersonKind.writer;
    }
    if (normalized.contains('composer') || normalized.contains('music')) return PersonKind.composer;
    return PersonKind.unknown;
  }

  Future<void> toggleSeasonExpanded(int seasonNumber) async {
    final currentExpanded = state.expandedSeasons[seasonNumber] ?? false;
    final newExpanded = !currentExpanded;

    final updatedExpanded = Map<int, bool>.from(state.expandedSeasons);
    updatedExpanded[seasonNumber] = newExpanded;
    state = state.copyWith(expandedSeasons: updatedExpanded);

    if (newExpanded && !state.episodesCache.containsKey(seasonNumber)) {
      await _fetchSeasonEpisodes(seasonNumber);
    }
  }

  Future<void> _fetchSeasonEpisodes(int seasonNumber) async {
    final poster = state.poster;
    if (poster == null) return;

    final response = await api.seasonDetails(
      tvId: poster.tmdbId,
      seasonNumber: seasonNumber,
    );

    if (response.isSuccessful && response.body != null) {
      final episodes = response.body!.episodes ?? [];
      final updatedCache = Map<int, List<SeerrEpisode>>.from(state.episodesCache);
      updatedCache[seasonNumber] = episodes;
      state = state.copyWith(episodesCache: updatedCache);
    }
  }

  Future<void> approveRequest(int requestId) async {
    final response = await api.approveRequest(requestId: requestId);
    if (response.isSuccessful) {
      await fetch();
    }
  }

  Future<void> declineRequest(int requestId) async {
    final response = await api.deleteRequest(requestId: requestId);
    if (response.isSuccessful) {
      await fetch();
    }
  }
}

@Freezed(copyWith: true)
abstract class SeerrDetailsModel with _$SeerrDetailsModel {
  const SeerrDetailsModel._();

  const factory SeerrDetailsModel({
    int? tmdbId,
    SeerrMediaType? mediaType,
    SeerrDashboardPosterModel? poster,
    @Default([]) List<SeerrGenre> genres,
    double? voteAverage,
    String? contentRating,
    String? releaseDate,
    @Default([]) List<SeerrDashboardPosterModel> recommended,
    @Default([]) List<SeerrDashboardPosterModel> similar,
    @Default([]) List<Person> people,
    @Default({}) Map<int, SeerrMediaStatus> seasonStatuses,
    SeerrUserModel? currentUser,
    @Default({}) Map<int, bool> expandedSeasons,
    @Default({}) Map<int, List<SeerrEpisode>> episodesCache,
    @Default([]) List<SeerrRelatedVideo> relatedVideos,
    SeerrExternalIds? externalIds,
    String? originalTitle,
    Duration? runTime,
    @Default([]) List<SeerrCompany> studios,

    /// Whether the full details have come back, not just the poster that
    /// opened the page - the ratings line waits for the IMDb id they carry.
    @Default(false) bool detailsLoaded,
  }) = _SeerrDetailsModel;

  bool get isTv => mediaType == SeerrMediaType.tvshow;

  bool? get hasRequestPermission {
    final user = currentUser;
    if (user == null) return null;

    final baseRequest = user.hasPermission(SeerrPermission.request);
    if (isTv) {
      return baseRequest || user.hasPermission(SeerrPermission.requestTv);
    }
    return baseRequest || user.hasPermission(SeerrPermission.requestMovie);
  }

  /// The lookup for the ratings line, once the details have said which IMDb
  /// title this is; asked for sooner, it would be asked twice.
  ExternalRatingsRequest? get ratingsRequest {
    final poster = this.poster;
    if (poster == null || !detailsLoaded) return null;
    return (
      tmdbId: poster.tmdbId,
      imdbId: externalIds?.imdbId,
      isSeries: isTv,
      title: poster.title,
      year: int.tryParse(poster.releaseYear ?? ''),
    );
  }

  /// Everywhere this can be opened on the web, the same sites a film in the
  /// library links to.
  List<ExternalLink> externalLinks({ExternalRatings? ratings}) {
    final poster = this.poster;
    if (poster == null) return const [];
    return externalLinksFor(
      imdbId: externalIds?.imdbId,
      tmdbId: poster.tmdbId.toString(),
      tvdbId: (externalIds?.tvdbId ?? poster.mediaInfo?.tvdbId)?.toString(),
      kind: isTv ? ExternalLinkKind.show : ExternalLinkKind.movie,
      ratings: ratings,
    );
  }

  SeerrRelatedVideo? get officialTrailer {
    if (relatedVideos.isEmpty) return null;

    final trailers = relatedVideos
        .where(
          (video) => (video.type ?? '').toLowerCase() == 'trailer',
        )
        .toList(growable: false);

    for (final trailer in trailers) {
      if ((trailer.name ?? '').toLowerCase().contains('official')) {
        return trailer;
      }
    }

    if (trailers.isNotEmpty) {
      return trailers.first;
    }

    return relatedVideos.first;
  }

  String? get officialTrailerUrl {
    final trailer = officialTrailer;
    final url = trailer?.url;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  bool get hasTrailerAction => (officialTrailerUrl ?? '').isNotEmpty;

  List<ExternalUrls> buildRelatedVideoUrls() {
    final urls = <ExternalUrls>[];

    for (var i = 0; i < relatedVideos.length; i++) {
      final video = relatedVideos[i];
      final url = video.url;
      if (url == null || url.isEmpty) continue;

      final videoName = video.name?.trim() ?? '';
      final videoType = video.type?.trim() ?? '';
      final label = videoName.isNotEmpty ? videoName : (videoType.isNotEmpty ? videoType : 'Video ${i + 1}');

      urls.add(ExternalUrls(name: label, url: url));
    }

    return urls;
  }

  bool isRequestedAlready(int seasonNumber) {
    final status = seasonStatuses[seasonNumber];
    return status != null && status.isKnown && status != SeerrMediaStatus.deleted;
  }
}

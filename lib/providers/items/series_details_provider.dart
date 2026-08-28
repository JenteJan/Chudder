import 'dart:developer';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/overview_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/special_feature_model.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/items/series_next_up_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

final seriesDetailsProvider =
    StateNotifierProvider.autoDispose.family<SeriesDetailViewNotifier, SeriesModel?, String>((ref, id) {
  return SeriesDetailViewNotifier(ref);
});

class SeriesDetailViewNotifier extends StateNotifier<SeriesModel?> {
  SeriesDetailViewNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  /// Episodes that have been filled in by [ensureEpisodeDetails], by id.
  ///
  /// Kept rather than merely remembered as a flag. The show's own episode list
  /// is fetched thin, so every time it arrives it would otherwise overwrite
  /// what had already been learned about an episode - and the guard against
  /// asking twice would then stop it ever being learned again.
  final Map<String, EpisodeModel> _detailedById = {};

  /// Requests in flight, so a rebuild does not ask for the same episode twice
  /// while the first answer is still coming.
  final Set<String> _detailsInFlight = {};

  /// The fetch in flight, so everything that asks for one while it runs - a
  /// page opening, its refresh indicator starting itself, a second State of
  /// the page taking over - joins it instead of starting another. The page
  /// dedups its own callers too, but two pages cannot see each other's.
  Future<Response?>? _fetchInFlight;

  /// [seed] paints something while the request is in flight; it is only ever
  /// used when there is nothing on screen yet.
  Future<Response?> fetchDetails(String seriesId, {SeriesModel? seed}) {
    return _fetchInFlight ??= _fetchDetails(seriesId, seed: seed).whenComplete(() => _fetchInFlight = null);
  }

  Future<Response?> _fetchDetails(String seriesId, {SeriesModel? seed}) async {
    try {
      if (seed != null && state == null) {
        // Called from a page's initState, which is mid-build - and Riverpod
        // refuses a write during build. One microtask later the frame is
        // done; the page paints its own copy of the seed until then.
        await Future<void>.microtask(() {});
        if (!mounted) return null;
        state ??= seed;
      }
      // Carried across the refetch and folded back in below, so a refresh does
      // not blank what is already on screen while it re-asks for it.
      final carried = Map<String, EpisodeModel>.from(_detailedById);
      _detailedById.clear();

      // All at once. These do not depend on each other, and run one after the
      // other they added up to about a second and a half of the page arriving
      // in pieces - the header, then the rows, then everything below them -
      // with the layout moving under the pointer at each step.
      late Response<ItemBaseModel> response;
      Response<BaseItemDtoQueryResult>? seasons;
      Response<BaseItemDtoQueryResult>? episodes;
      List<BaseItemDto> specialFeatures = const [];
      var related = const <ItemBaseModel>[];

      final itemRequest = api.usersUserIdItemsItemIdGet(itemId: seriesId);

      // Paint the show itself the moment it lands rather than holding a blank
      // page until the rows below it have been counted. The screen shows
      // placeholders the same size as the rows meanwhile, so this does not
      // move anything.
      itemRequest.then((value) {
        final model = value.body;
        if (mounted && state == null && model is SeriesModel) state = model;
      }).ignore();

      // Already here if the poster was hovered on the way in - see
      // [seriesNextUpProvider]. Taken before anything is awaited, so the header
      // has its episode on the frame the page is built rather than a request
      // later.
      final prefetched = ref.read(seriesNextUpProvider).of(seriesId);
      if (prefetched != null && state?.availableEpisodes?.isNotEmpty != true) {
        state = state?.copyWith(selectedEpisode: prefetched);
      }

      // Next-up on its own, ahead of the episode list.
      //
      // Opened from a show's own poster there is no episode in hand, and every
      // part of the header that names one - the play button, the language
      // pickers, the runtime - had to wait for all of them: a couple of hundred
      // episodes to fetch and, more to the point, to parse. This is one episode
      // and nine kilobytes, and it answers the same question.
      //
      // The same question a poster asks on hover, through the same cache - so
      // if the poster was hovered this is already answered, and if it was not
      // there is still only one request and one answer for the page to agree
      // with. See [SeriesNextUpCache].
      final nextUp = ref.read(seriesNextUpProvider);
      final standInRequest = nextUp.prefetch(seriesId).then((_) => nextUp.of(seriesId));

      standInRequest.then((episode) {
        // Only ever a stand-in: once the episode list is here it answers for
        // itself, and this is not consulted again.
        if (mounted && episode != null && state?.availableEpisodes?.isNotEmpty != true) {
          state = state?.copyWith(selectedEpisode: episode);
        }
      }).ignore();

      await Future.wait<void>([
        standInRequest.then<void>((_) {}),
        itemRequest.then((value) {
          response = value;
        }),
        api
            .showsSeriesIdSeasonsGet(
          seriesId: seriesId,
          enableUserData: false,
        )
            .then((value) {
          seasons = value;
        }),
        api.showsSeriesIdEpisodesGet(
          seriesId: seriesId,
          enableUserData: true,
          // Deliberately thin. Media sources are about ten kilobytes an
          // episode - on a 170-episode show that is one response of two
          // megabytes, nearly all of it describing episodes nobody has opened.
          // Without them the same response is under four hundred kilobytes.
          // What the one episode on screen needs is fetched for that episode,
          // by [ensureEpisodeDetails].
          fields: [
            ItemFields.overview,
            ItemFields.candownload,
          ],
        ).then((value) {
          episodes = value;
        }),
        _fetchSpecialFeatures(seriesId).then((value) {
          specialFeatures = value;
        }),
        ref.read(relatedUtilityProvider).relatedContent(seriesId).then<void>((value) {
          related = value.body ?? const [];
        }).catchError((Object _) {}),
      ]);

      // The page may have gone while these were in flight; there is nothing
      // left to fill in, and writing state now is an error.
      if (!mounted) return null;

      if (response.body == null) return null;
      SeriesModel newState = (response.bodyOrThrow as SeriesModel).copyWith(
        seerrRelated: state?.seerrRelated ?? const [],
        seerrRecommended: state?.seerrRecommended ?? const [],
        // Kept as a fallback for the moment between this landing and anything
        // reading the list; the list itself carries the same copy now.
        selectedEpisode: state?.selectedEpisode,
      );

      // Whatever is already known about one episode, folded into the list that
      // has just arrived.
      //
      // The list is fetched without streams, so it is thinner than the early
      // episode this page has been showing - and dropping that on the floor
      // does not merely lose it for a moment. Both guards against asking twice
      // have already seen this episode's id, so nothing would ever fetch its
      // streams again and the language buttons stayed empty until another
      // episode was picked.
      final early = state?.selectedEpisode;
      if (early != null) carried.putIfAbsent(early.id, () => early);

      final newEpisodes = EpisodeModel.episodesFromDto(
        episodes?.body?.items,
        ref,
      ).map((episode) {
        // The live map first: a detail that landed while this fetch was in
        // flight is only there, not in the snapshot taken before it started.
        // Folding from the snapshot alone left the list thin for an episode
        // both guards already counted as done - so the language pickers for
        // an episode handed over without its streams never arrived at all.
        final known = _detailedById[episode.id] ?? carried[episode.id];
        if (known == null) return episode;
        return episode.copyWith(
          mediaStreams: known.mediaStreams.versionStreams.isNotEmpty ? known.mediaStreams : episode.mediaStreams,
          chapters: known.chapters.isNotEmpty ? known.chapters : episode.chapters,
          overview: known.overview.people.isNotEmpty
              ? episode.overview.copyWith(people: known.overview.people)
              : episode.overview,
        );
      }).toList();

      final episodesCanDownload = newEpisodes.any((episode) => episode.canDownload == true);

      newState = newState.copyWith(
        related: related,
        canDownload: episodesCanDownload,
        availableEpisodes: newEpisodes,
        specialFeatures: SpecialFeatureModel.specialFeaturesFromDto(specialFeatures, ref),
        seasons: SeasonModel.seasonsFromDto(seasons?.body?.items, ref).map(
          (element) {
            final unPlayedCount = newEpisodes
                .where((episode) =>
                    episode.season == element.season &&
                    episode.status == EpisodeStatus.available &&
                    episode.userData.played == false)
                .length;
            return element.copyWith(
              canDownload: true,
              episodes: newEpisodes.where((episode) => episode.season == element.season).toList(),
              userData: UserData(
                unPlayedItemCount: unPlayedCount,
                played: unPlayedCount == 0,
              ),
            );
          },
        ).toList(),
      );

      // The whole page in one go, so nothing below the header moves twice.
      state = newState;
      // Seerr needs the show's tmdb id, so it can only start once the above
      // has arrived; it lands in its own rows at the very bottom.
      await _fetchSeerr(newState);

      return response;
    } catch (e) {
      log("Error fetching series details: $e");
      log("Error fetching series details: $e");
      await _tryToCreateOfflineState(seriesId);
      return null;
    }
  }

  Future<List<BaseItemDto>> _fetchSpecialFeatures(String seriesId) async {
    try {
      return (await api.itemsItemIdSpecialFeaturesGet(itemId: seriesId)).body ?? [];
    } on Exception catch (e, s) {
      log("Failed to get special features for series id $seriesId due to $e",
          level: logging.Level.WARNING.value, error: e, stackTrace: s);
      return const [];
    }
  }

  Future<void> _fetchSeerr(SeriesModel series) async {
    final seerrCreds = ref.read(userProvider)?.seerrCredentials;
    if (seerrCreds?.isConfigured != true) return;
    final tmdbId = series.tmdbId;
    if (tmdbId == null) return;

    final seerr = ref.read(seerrApiProvider);
    List<SeerrDashboardPosterModel> seerrRelated = const [];
    List<SeerrDashboardPosterModel> seerrRecommended = const [];
    SeerrDashboardPosterModel? seerrPoster;

    await Future.wait<void>([
      seerr.discoverRelatedSeries(tmdbId: tmdbId).then((value) => seerrRelated = value),
      seerr.discoverRecommendedSeries(tmdbId: tmdbId).then((value) => seerrRecommended = value),
      seerr
          .fetchDashboardPosterFromIds(
            tmdbId: tmdbId,
            mediaType: SeerrMediaType.tvshow,
          )
          .then((value) => seerrPoster = value),
    ]);

    final status = seerrPoster?.mediaInfo?.mediaStatus;
    final seerrUrl = status != SeerrMediaStatus.unknown
        ? '${ref.read(userProvider.select((value) => value?.seerrCredentials?.serverUrl))}tv/$tmdbId'
        : null;

    state = state?.copyWith(
      seerrRelated: seerrRelated,
      seerrRecommended: seerrRecommended,
      overview: state?.overview.copyWith(seerrUrl: seerrUrl),
    );
  }

  /// Everything the show-wide episode fetch leaves out, filled in for the one
  /// episode being looked at: its media sources, its chapters and its own cast.
  ///
  /// Asked for a whole show at once these are what a bulk fetch charges most
  /// for - together they took one response past three megabytes and a second
  /// and a half. Asked for a single episode they cost a few kilobytes, and the
  /// answer is kept, so a show only ever pays for the episodes actually opened.
  Future<void> ensureEpisodeDetails(String episodeId) async {
    if (_detailsInFlight.contains(episodeId)) return;
    // Judged on what the episode is missing rather than on whether it has been
    // asked for before: a thin copy arriving later leaves it needing the same
    // things again, and a flag would say it had already been dealt with.
    if (_detailedById.containsKey(episodeId)) return;

    _detailsInFlight.add(episodeId);
    try {
      final detailed = (await api.usersUserIdItemsItemIdGet(itemId: episodeId)).body;
      if (detailed is! EpisodeModel) return;

      final episodes = state?.availableEpisodes;
      final index = episodes?.indexWhere((element) => element.id == episodeId) ?? -1;
      if (episodes == null || index < 0) {
        // Asked for before the list arrived. Held until it does, and folded in
        // then - the old code dropped it here, which is why an episode opened
        // directly never got its chapters or its guest cast.
        _detailedById[episodeId] = detailed;
        state = state?.selectedEpisode?.id == episodeId ? state?.copyWith(selectedEpisode: detailed) : state;
        return;
      }

      final filled = episodes[index].copyWith(
        chapters: detailed.chapters,
        mediaStreams: detailed.mediaStreams,
        overview: episodes[index].overview.copyWith(people: detailed.overview.people),
      );
      _detailedById[episodeId] = filled;

      final newList = episodes.toList();
      newList[index] = filled;
      state = state?.copyWith(availableEpisodes: newList);
    } catch (e) {
      // Nothing to show for it; a later attempt is free to try again.
    } finally {
      _detailsInFlight.remove(episodeId);
    }
  }

  /// No server, so the show is whatever has been downloaded of it. Carries the
  /// same shape the online path builds, so the screen needs no second case.
  Future<void> _tryToCreateOfflineState(String seriesId) async {
    if (!mounted || state?.availableEpisodes?.isNotEmpty == true) return;
    final syncNotifier = ref.read(syncProvider.notifier);
    final seriesSyncedItem = await syncNotifier.getSyncedItem(seriesId);
    if (seriesSyncedItem == null) return;
    final seriesModel = seriesSyncedItem.itemModel as SeriesModel?;
    if (seriesModel == null) return;
    final episodes = (await syncNotifier.getNestedChildren(seriesSyncedItem))
        .map((e) => e.itemModel)
        .whereType<EpisodeModel>()
        .toList();
    if (!mounted) return;
    state = seriesModel.copyWith(
      availableEpisodes: episodes,
      seasons: episodes.episodesBySeason.entries
          .map(
            (entry) => SeasonModel(
              parentImages: seriesModel.images,
              seasonName: "",
              episodes: entry.value,
              episodeCount: entry.value.length,
              seriesId: seriesId,
              season: entry.key,
              seriesName: seriesModel.name,
              name: "",
              id: "$seriesId-season-${entry.key}",
              overview: const OverviewModel(),
              parentId: seriesId,
              playlistId: null,
              images: null,
              childCount: entry.value.length,
              primaryRatio: null,
              userData: UserData(
                unPlayedItemCount: entry.value.where((episode) => !episode.userData.played).length,
                played: entry.value.every((episode) => episode.userData.played),
              ),
              canDelete: false,
              canDownload: false,
            ),
          )
          .toList(),
    );
  }

  /// Puts a changed copy of an episode back, wherever this show is holding it.
  ///
  /// Both places, because the page can be reading either: the episode list once
  /// it has arrived, and the single early episode fetched before it. This used
  /// to write only into the list, and by index — and `indexWhere` answers -1
  /// for an episode that is not in it, which is every episode until the list
  /// lands. Assigning at -1 throws, so changing the audio or the subtitles on a
  /// show page did nothing at all.
  void updateEpisodeInfo(EpisodeModel episode) {
    final current = state;
    if (current == null) return;

    final episodes = current.availableEpisodes;
    final index = episodes?.indexWhere((element) => element.id == episode.id) ?? -1;

    state = current.copyWith(
      availableEpisodes: index >= 0 ? ([...episodes!]..[index] = episode) : episodes,
      selectedEpisode: current.selectedEpisode?.id == episode.id ? episode : current.selectedEpisode,
    );
  }
}

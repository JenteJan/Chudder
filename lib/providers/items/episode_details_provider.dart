import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/sync_provider.dart';

class EpisodeDetailModel {
  final SeriesModel? series;
  final List<EpisodeModel> episodes;
  final List<SeasonModel> seasons;
  final EpisodeModel? episode;
  final List<Person> guestActors;
  EpisodeDetailModel({
    this.series,
    this.episodes = const [],
    this.seasons = const [],
    this.episode,
    this.guestActors = const [],
  });

  EpisodeDetailModel copyWith({
    SeriesModel? series,
    List<EpisodeModel>? episodes,
    List<SeasonModel>? seasons,
    EpisodeModel? episode,
    List<Person>? guestActors,
  }) {
    return EpisodeDetailModel(
      series: series ?? this.series,
      episodes: episodes ?? this.episodes,
      seasons: seasons ?? this.seasons,
      episode: episode ?? this.episode,
      guestActors: guestActors ?? this.guestActors,
    );
  }
}

final episodeDetailsProvider =
    StateNotifierProvider.autoDispose.family<EpisodeDetailsProvider, EpisodeDetailModel, String>((ref, id) {
  return EpisodeDetailsProvider(ref);
});

class EpisodeDetailsProvider extends StateNotifier<EpisodeDetailModel> {
  EpisodeDetailsProvider(this.ref) : super(EpisodeDetailModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<Response?> fetchDetails(ItemBaseModel item) async {
    try {
      final seriesResponse = await api.usersUserIdItemsItemIdGet(itemId: item.parentBaseModel.id);
      if (seriesResponse.body == null) return null;
      final episodes = await api.showsSeriesIdEpisodesGet(seriesId: item.parentBaseModel.id);

      if (episodes.body == null) return null;

      final episode = (await api.usersUserIdItemsItemIdGet(itemId: item.id)).bodyOrThrow as EpisodeModel;

      final allEpisodes = EpisodeModel.episodesFromDto(episodes.bodyOrThrow.items, ref);

      state = state.copyWith(
        series: seriesResponse.bodyOrThrow as SeriesModel,
        episodes: allEpisodes,
        episode: episode,
        seasons: await _fetchSeasons(item.parentBaseModel.id, allEpisodes),
      );

      return seriesResponse;
    } catch (e) {
      _tryToCreateOfflineState(item);
      return null;
    }
  }

  /// The whole show's seasons, so an episode page can offer the same row a
  /// series page does. Unwatched counts come from the episodes already
  /// fetched rather than a second trip for user data.
  Future<List<SeasonModel>> _fetchSeasons(String seriesId, List<EpisodeModel> episodes) async {
    try {
      final seasons = await api.showsSeriesIdSeasonsGet(seriesId: seriesId, enableUserData: false);
      return SeasonModel.seasonsFromDto(seasons.body?.items, ref).map((season) {
        final seasonEpisodes = episodes.where((episode) => episode.season == season.season).toList();
        final unPlayed = seasonEpisodes
            .where((episode) => episode.status == EpisodeStatus.available && episode.userData.played == false)
            .length;
        return season.copyWith(
          episodes: seasonEpisodes,
          userData: UserData(unPlayedItemCount: unPlayed, played: unPlayed == 0),
        );
      }).toList();
    } catch (e) {
      return const [];
    }
  }

  Future<void> _tryToCreateOfflineState(ItemBaseModel item) async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final episodeModel = (await syncNotifier.getSyncedItem(item.id))?.itemModel as EpisodeModel?;
    if (episodeModel == null) return;
    final seriesSyncedItem = await syncNotifier.getSyncedItem(episodeModel.parentBaseModel.id);
    if (seriesSyncedItem == null) return;
    final seriesModel = seriesSyncedItem.itemModel as SeriesModel?;
    if (seriesModel == null) return;
    final episodes = (await syncNotifier.getNestedChildren(seriesSyncedItem))
        .map((e) => e.itemModel)
        .whereType<EpisodeModel>()
        .toList();
    state = state.copyWith(
      series: seriesModel,
      episode: episodes.firstWhereOrNull((element) => element.id == item.id),
      episodes: episodes,
    );
    return;
  }

  void updateEpisode(EpisodeModel episode) {
    state = state.copyWith(episode: episode);
  }
}

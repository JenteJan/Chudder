import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/service_provider.dart';

/// The episode a show's page will name on its play button, fetched ahead of
/// the page.
///
/// A show carries no episode of its own; the page has to ask which one comes
/// next, and until the answer is here the header cannot name one. This is a
/// small request, and asked for while the pointer is still on the poster the
/// answer is usually already here by the time the page has been pushed. Kept
/// afterwards, so opening the same show again asks nothing at all.
///
/// The page itself goes through here too - [prefetch] returns the request
/// already in flight - so there is one answer to the question, not two that
/// might disagree.
final seriesNextUpProvider = Provider<SeriesNextUpCache>(SeriesNextUpCache.new);

class SeriesNextUpCache {
  SeriesNextUpCache(this.ref);

  final Ref ref;

  final Map<String, EpisodeModel> _byShow = {};
  final Map<String, SeriesModel> _shows = {};
  final Map<String, Future<void>> _inFlight = {};

  /// What we already know, or null. Never waits.
  EpisodeModel? of(String? seriesId) => seriesId == null ? null : _byShow[seriesId];

  /// The show itself - name, genres, overview, artwork - or null. Never waits.
  ///
  /// So a page opened from an episode, which knows only the show's name and
  /// poster, does not have to wait a request for the rest of its header.
  SeriesModel? showOf(String? seriesId) => seriesId == null ? null : _shows[seriesId];

  /// Remembers an episode a show page has fetched for itself, so the next visit
  /// does not have to.
  void remember(String seriesId, EpisodeModel episode) => _byShow[seriesId] = episode;

  /// Fetches ahead of being asked. Completes at once if the answer is already
  /// here; joins the request already in flight if there is one.
  Future<void> prefetch(String? seriesId) {
    if (seriesId == null || seriesId.isEmpty) return Future.value();
    if (_byShow.containsKey(seriesId) && _shows.containsKey(seriesId)) return Future.value();
    return _inFlight[seriesId] ??= _fetch(seriesId).whenComplete(() => _inFlight.remove(seriesId));
  }

  static const _fields = [
    ItemFields.mediastreams,
    ItemFields.mediasources,
    ItemFields.overview,
    ItemFields.chapters,
  ];

  Future<void> _fetch(String seriesId) async {
    final api = ref.read(jellyApiProvider);
    await Future.wait<void>([
      if (!_shows.containsKey(seriesId)) _fetchShow(api, seriesId),
      if (!_byShow.containsKey(seriesId)) _fetchEpisode(api, seriesId),
    ]);
  }

  /// The show's own item, so its header can be complete before the page's own
  /// request has come back.
  Future<void> _fetchShow(JellyService api, String seriesId) async {
    try {
      final model = (await api.usersUserIdItemsItemIdGet(itemId: seriesId)).body;
      if (model is SeriesModel) _shows[seriesId] = model;
    } catch (_) {
      // As below: nothing lost, the page asks for the show itself anyway.
    }
  }

  Future<void> _fetchEpisode(JellyService api, String seriesId) async {
    try {
      final response = await api.showsNextUpGet(
        seriesId: seriesId,
        limit: 1,
        enableUserData: true,
        // The episode you are in the middle of, matching what the show page
        // itself asks for; otherwise the two would disagree.
        enableResumable: true,
        fields: _fields,
      );
      var episode = EpisodeModel.episodesFromDto(response.body?.items, ref).firstOrNull;

      // A show never started has no next-up. Its first episode is what the
      // page's list will settle on - see [SeriesModel.nextUp] - so hand that
      // over rather than let the button start as the show and then jump.
      // Season 1 first: the plain first item of a show with specials is a
      // special, which the list does not count, and the button would jump
      // once more.
      episode ??= await _firstEpisode(api, seriesId, season: 1);
      episode ??= await _firstEpisode(api, seriesId);

      if (episode != null) _byShow[seriesId] = episode;
    } catch (_) {
      // A prefetch that fails costs nothing; the page will ask again itself.
    }
  }

  Future<EpisodeModel?> _firstEpisode(JellyService api, String seriesId, {int? season}) async {
    final response = await api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      season: season,
      limit: 1,
      enableUserData: true,
      fields: _fields,
    );
    return EpisodeModel.episodesFromDto(response.body?.items, ref).firstOrNull;
  }
}

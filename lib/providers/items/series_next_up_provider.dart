import 'package:flutter/foundation.dart';

import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';

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
  final Map<String, Future<Response<ItemBaseModel>>> _showsInFlight = {};
  final Map<String, Future<EpisodeModel?>> _episodesInFlight = {};
  final Map<String, DateTime> _episodeFetchedAt = {};

  /// How long an answer counts as just fetched - see [recentEpisode].
  static const freshFor = Duration(seconds: 3);

  @visibleForTesting
  DateTime Function() now = DateTime.now;

  /// What we already know, or null. Never waits.
  EpisodeModel? of(String? seriesId) => seriesId == null ? null : _byShow[seriesId];

  /// The show itself - name, genres, overview, artwork - or null. Never waits.
  ///
  /// So a page opened from an episode, which knows only the show's name and
  /// poster, does not have to wait a request for the rest of its header.
  SeriesModel? showOf(String? seriesId) => seriesId == null ? null : _shows[seriesId];

  /// The request for the show itself that [prefetch] has on its way, or null.
  ///
  /// The show's page asks for the same item a frame after it was opened, and
  /// joining this is one request instead of two. Only ever a request still in
  /// flight - see [MovieDetailsPrefetchCache.inFlight] for why never an older
  /// answer.
  Future<Response<ItemBaseModel>>? showInFlight(String? seriesId) =>
      seriesId == null ? null : _showsInFlight[seriesId];

  /// The next-up request [prefetch] has on its way for [seriesId], or null.
  ///
  /// This, or a [recentEpisode], is the only answer that may stand in for the
  /// episode's own request, the one
  /// [SeriesDetailViewNotifier.ensureEpisodeDetails] sends. Next-up is fetched
  /// with the same streams, chapters and cast, but not all of that keeps: the
  /// default audio and subtitle tracks are what the server remembers this user
  /// picking last, on any client, and a subtitle can be added. An answer kept
  /// from earlier in the session only names the episode until the page asks
  /// again.
  Future<EpisodeModel?>? episodeInFlight(String? seriesId) =>
      seriesId == null ? null : _episodesInFlight[seriesId];

  /// The next-up episode if it was fetched within [freshFor], or null.
  ///
  /// The card that opens a page asks a moment before the page does - on its
  /// way out, or on hover just before the click - and that answer is as good
  /// as one the page would fetch itself.
  EpisodeModel? recentEpisode(String? seriesId) {
    if (seriesId == null) return null;
    final fetchedAt = _episodeFetchedAt[seriesId];
    if (fetchedAt == null || now().difference(fetchedAt) > freshFor) return null;
    return _byShow[seriesId];
  }

  /// Remembers an episode a show page has fetched for itself, so the next visit
  /// does not have to.
  void remember(String seriesId, EpisodeModel episode) => _byShow[seriesId] = episode;

  /// Fetches ahead of being asked. Completes at once if the answer is already
  /// here; joins the request already in flight if there is one.
  Future<void> prefetch(String? seriesId) {
    if (seriesId == null || seriesId.isEmpty) return Future.value();
    if (_byShow.containsKey(seriesId) && _shows.containsKey(seriesId)) {
      return Future.value();
    }
    return _inFlight[seriesId] ??= _fetch(seriesId).whenComplete(() {
      _inFlight.remove(seriesId);
    });
  }

  /// Everything [SeriesDetailViewNotifier.ensureEpisodeDetails] would fetch
  /// the episode again for, so a show page opened on its next-up episode does
  /// not have to. The cast is a few kilobytes; the request it saves is ten.
  static const _fields = [
    ItemFields.mediastreams,
    ItemFields.mediasources,
    ItemFields.overview,
    ItemFields.chapters,
    ItemFields.people,
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
    final request = api.usersUserIdItemsItemIdGet(itemId: seriesId);
    _showsInFlight[seriesId] = request;
    try {
      final model = (await request).body;
      if (model is SeriesModel) _shows[seriesId] = model;
    } catch (e) {
      // As below: nothing lost, the page asks for the show itself anyway.
    } finally {
      _showsInFlight.remove(seriesId);
    }
  }

  Future<void> _fetchEpisode(JellyService api, String seriesId) async {
    final request = _nextUp(api, seriesId);
    _episodesInFlight[seriesId] = request;
    try {
      final episode = await request;
      if (episode != null) {
        _byShow[seriesId] = episode;
        _episodeFetchedAt[seriesId] = now();
      }
    } finally {
      _episodesInFlight.remove(seriesId);
    }
  }

  Future<EpisodeModel?> _nextUp(JellyService api, String seriesId) async {
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
      return episode;
    } catch (e) {
      // A prefetch that fails costs nothing; the page will ask again itself.
      return null;
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

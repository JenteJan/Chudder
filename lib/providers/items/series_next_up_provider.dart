import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/providers/api_provider.dart';

/// The episode a show would play, fetched before anyone opens the show.
///
/// Pressing a next-up card is instant because the card *is* the episode, fetched
/// with its streams — the page it opens needs nothing. Pressing a show's poster
/// is not, because a show carries no episode, and every part of the header that
/// names one has to wait for a request that only starts once the page exists.
///
/// Asking while the pointer is still on the poster closes that gap: it is one
/// small request, and by the time the page has been pushed the answer is
/// usually already here. Kept afterwards, so opening the same show again asks
/// nothing at all.
final seriesNextUpProvider = Provider<SeriesNextUpCache>(SeriesNextUpCache.new);

class SeriesNextUpCache {
  SeriesNextUpCache(this.ref);

  final Ref ref;

  final Map<String, EpisodeModel> _byShow = {};
  final Set<String> _inFlight = {};

  /// What we already know, or null. Never waits.
  EpisodeModel? of(String? seriesId) => seriesId == null ? null : _byShow[seriesId];

  /// Remembers an episode a show page has fetched for itself, so the next visit
  /// does not have to.
  void remember(String seriesId, EpisodeModel episode) => _byShow[seriesId] = episode;

  /// Fetches ahead of being asked. Does nothing if the answer is already here
  /// or already on its way.
  Future<void> prefetch(String? seriesId) async {
    if (seriesId == null || seriesId.isEmpty) return;
    if (_byShow.containsKey(seriesId) || _inFlight.contains(seriesId)) return;

    _inFlight.add(seriesId);
    try {
      final response = await ref.read(jellyApiProvider).showsNextUpGet(
        seriesId: seriesId,
        limit: 1,
        enableUserData: true,
        // The episode you are in the middle of, matching what the show page
        // itself asks for; otherwise the two would disagree.
        enableResumable: true,
        fields: [
          ItemFields.mediastreams,
          ItemFields.mediasources,
          ItemFields.overview,
          ItemFields.chapters,
        ],
      );
      final episode = EpisodeModel.episodesFromDto(response.body?.items, ref).firstOrNull;
      if (episode != null) _byShow[seriesId] = episode;
    } catch (_) {
      // A prefetch that fails costs nothing; the page will ask again itself.
    } finally {
      _inFlight.remove(seriesId);
    }
  }
}

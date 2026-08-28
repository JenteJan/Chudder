import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/providers/api_provider.dart';

/// A film's full details, fetched while the pointer is still on its poster.
///
/// The counterpart of [seriesNextUpProvider] for films. A poster in a library
/// carries the film's name and artwork but not its streams, so the page it
/// opens has to ask for the rest - and the pickers beside the play button, and
/// the button's own resume state, arrive a request later than the header. Asked
/// for on hover, the answer is usually here by the time the page is pushed, and
/// the page opens complete. Kept afterwards, so opening the same film again
/// asks nothing at all.
final movieDetailsPrefetchProvider = Provider<MovieDetailsPrefetchCache>(MovieDetailsPrefetchCache.new);

class MovieDetailsPrefetchCache {
  MovieDetailsPrefetchCache(this.ref);

  final Ref ref;

  final Map<String, MovieModel> _byId = {};
  final Set<String> _inFlight = {};

  /// What we already know, or null. Never waits.
  MovieModel? of(String? id) => id == null ? null : _byId[id];

  /// Fetches ahead of being asked. Does nothing if the answer is already here
  /// or on its way.
  Future<void> prefetch(String? id) async {
    if (id == null || id.isEmpty) return;
    if (_byId.containsKey(id) || _inFlight.contains(id)) return;
    _inFlight.add(id);
    try {
      final response = await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: id);
      final model = response.body;
      if (model is MovieModel) _byId[id] = model;
    } catch (_) {
      // A prefetch that fails costs nothing; the page will ask again itself.
    } finally {
      _inFlight.remove(id);
    }
  }
}

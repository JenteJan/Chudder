import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/providers/api_provider.dart';

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
  final Map<String, Future<Response<ItemBaseModel>>> _inFlight = {};

  /// What we already know, or null. Never waits.
  MovieModel? of(String? id) => id == null ? null : _byId[id];

  /// The request [prefetch] has on its way for this film, or null.
  ///
  /// Opening a film prefetches it and the page asks for the same film a frame
  /// later; joining this is one request instead of two, answered sooner. Only
  /// ever a request still in flight, never an answer from earlier: the cache
  /// is kept for the whole session, and a page opened from it would show
  /// whatever progress the film had back then.
  Future<Response<ItemBaseModel>>? inFlight(String? id) => id == null ? null : _inFlight[id];

  /// Fetches ahead of being asked. Does nothing if the answer is already here
  /// or on its way.
  Future<void> prefetch(String? id) async {
    if (id == null || id.isEmpty) return;
    if (_byId.containsKey(id) || _inFlight.containsKey(id)) return;
    final request = ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: id);
    _inFlight[id] = request;
    try {
      final response = await request;
      final model = response.body;
      if (model is MovieModel) _byId[id] = model;
    } catch (_) {
      // A prefetch that fails costs nothing; the page will ask again itself.
    } finally {
      _inFlight.remove(id);
    }
  }
}

import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';

/// Which collections and playlists hold what, for the toggle buttons on a
/// detail page.
///
/// The server has no way to ask "which collections is this in?", so the
/// contents of every collection and playlist are fetched once and kept. A
/// library rarely has more than a few dozen of either; past [maxLookups] the
/// answer is simply "unknown" rather than a storm of requests.
///
/// The lookup goes out as a film page opens - a film outside any TMDB
/// collection is looked for in all of them, for its languages - so it is
/// kept light: ids only, [_parallel] at a time on connections that are
/// already open, and once known it is not waited on again. A page opened
/// after [maxAge] gets the answer it had and the refresh happens behind it.
/// The forty-odd full responses it used to be, each on a new connection,
/// all landed as the page's poster was settling, and stalled its last
/// frames.
class ItemMembership {
  /// Null while unknown - still loading, or too many to check.
  final bool? inCollection;
  final bool? inPlaylist;

  const ItemMembership({this.inCollection, this.inPlaylist});

  static const unknown = ItemMembership();
}

class MembershipCache {
  MembershipCache(this.ref, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final Ref ref;

  static const int maxLookups = 60;
  static const int _parallel = 6;
  static const Duration maxAge = Duration(minutes: 10);

  Map<String, Set<String>>? _collections;
  Map<String, String> _collectionNames = const {};
  Map<String, Set<String>>? _playlists;
  DateTime? _fetched;
  Future<void>? _inFlight;

  JellyService get _api => ref.read(jellyApiProvider);

  bool get _stale => _fetched == null || _now().difference(_fetched!) > maxAge;

  /// Forgets everything, so the next page asks again. Called after an item
  /// has been added to or taken out of anything.
  void invalidate() {
    _collections = null;
    _playlists = null;
    _fetched = null;
    _inFlight = null;
    _generation++;
  }

  /// Bumped by [invalidate], so a lookup that was already out when something
  /// changed does not write back what it saw before.
  int _generation = 0;

  /// [lookup] for each of [items], no more than [_parallel] at once.
  static Future<List<T>> _limited<S, T>(List<S> items, Future<T> Function(S item) lookup) async {
    final results = List<T?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final index = next++;
        results[index] = await lookup(items[index]);
      }
    }

    await Future.wait([for (var i = 0; i < _parallel && i < items.length; i++) worker()]);
    return results.cast<T>();
  }

  /// Brings the lookup up to date: waited on when nothing is known yet,
  /// behind the answer already known otherwise.
  Future<void> _fresh() async {
    if (!_stale) return;
    var load = _inFlight;
    if (load == null) {
      late final Future<void> started;
      started = _load().whenComplete(() {
        if (identical(_inFlight, started)) _inFlight = null;
      });
      load = _inFlight = started;
    }
    if (_fetched == null) await load;
  }

  Future<ItemMembership> membershipOf(String itemId) async {
    await _fresh();
    return ItemMembership(
      inCollection: _contains(_collections, itemId),
      inPlaylist: _contains(_playlists, itemId),
    );
  }

  /// The collections [itemId] is in, by id and name; empty when none or
  /// unknown.
  Future<List<({String id, String name})>> collectionsOf(String itemId) async {
    await _fresh();
    final collections = _collections;
    if (collections == null) return const [];
    return [
      for (final entry in collections.entries)
        if (entry.value.contains(itemId)) (id: entry.key, name: _collectionNames[entry.key] ?? ''),
    ];
  }

  /// What [collectionsOf] would answer, without asking: null when the
  /// collections have not been looked up (or are too many to).
  List<String>? knownCollectionsOf(String itemId) {
    final collections = _collections;
    if (collections == null || _fetched == null) return null;
    return [
      for (final entry in collections.entries)
        if (entry.value.contains(itemId)) entry.key,
    ];
  }

  bool? _contains(Map<String, Set<String>>? groups, String itemId) {
    if (groups == null) return null;
    return groups.values.any((ids) => ids.contains(itemId));
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final results = await Future.wait([_loadCollections(), _loadPlaylists()]);
      if (generation != _generation) return;
      _collections = results[0];
      _playlists = results[1];
      _fetched = _now();
    } catch (e) {
      log('Membership lookup failed: $e');
    }
  }

  Future<Map<String, Set<String>>?> _loadCollections() async {
    final response = await _api.usersUserIdItemsGet(recursive: true, includeItemTypes: [BaseItemKind.boxset]);
    final boxSets = response.body?.items ?? const <BaseItemDto>[];
    if (boxSets.length > maxLookups) return null;
    _collectionNames = {for (final boxSet in boxSets) boxSet.id ?? '': boxSet.name ?? ''};
    final entries = await _limited(boxSets, (boxSet) async {
      final children = await _api.usersUserIdItemsGet(
        parentId: boxSet.id,
        enableImages: false,
        enableUserData: false,
        fields: const [],
      );
      return MapEntry(boxSet.id ?? '', (children.body?.items ?? const <BaseItemDto>[]).map((e) => e.id ?? '').toSet());
    });
    return Map.fromEntries(entries);
  }

  Future<Map<String, Set<String>>?> _loadPlaylists() async {
    final response = await _api.usersUserIdItemsGet(recursive: true, includeItemTypes: [BaseItemKind.playlist]);
    final playlists = response.body?.items ?? const <BaseItemDto>[];
    if (playlists.length > maxLookups) return null;
    final entries = await _limited(playlists, (playlist) async {
      final children = await _api.playlistsPlaylistIdItemsGet(
        playlistId: playlist.id,
        enableImages: false,
        enableUserData: false,
        fields: [],
      );
      return MapEntry(playlist.id ?? '', (children.body?.items ?? const []).map((e) => e.id).toSet());
    });
    return Map.fromEntries(entries);
  }
}

final membershipCacheProvider = Provider<MembershipCache>((ref) => MembershipCache(ref));

/// Whether [itemId] is in any collection, and in any playlist.
final itemMembershipProvider = FutureProvider.autoDispose.family<ItemMembership, String>((ref, itemId) {
  return ref.watch(membershipCacheProvider).membershipOf(itemId);
});

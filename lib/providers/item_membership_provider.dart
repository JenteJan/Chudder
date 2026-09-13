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
class ItemMembership {
  /// Null while unknown - still loading, or too many to check.
  final bool? inCollection;
  final bool? inPlaylist;

  const ItemMembership({this.inCollection, this.inPlaylist});

  static const unknown = ItemMembership();
}

class MembershipCache {
  MembershipCache(this.ref);

  final Ref ref;

  static const int maxLookups = 60;
  static const Duration maxAge = Duration(minutes: 10);

  Map<String, Set<String>>? _collections;
  Map<String, Set<String>>? _playlists;
  DateTime? _fetched;
  Future<void>? _inFlight;

  JellyService get _api => ref.read(jellyApiProvider);

  bool get _stale => _fetched == null || DateTime.now().difference(_fetched!) > maxAge;

  /// Forgets everything, so the next page asks again. Called after an item
  /// has been added to or taken out of anything.
  void invalidate() {
    _collections = null;
    _playlists = null;
    _fetched = null;
  }

  Future<ItemMembership> membershipOf(String itemId) async {
    if (_stale) {
      _inFlight ??= _load().whenComplete(() => _inFlight = null);
      await _inFlight;
    }
    return ItemMembership(
      inCollection: _contains(_collections, itemId),
      inPlaylist: _contains(_playlists, itemId),
    );
  }

  bool? _contains(Map<String, Set<String>>? groups, String itemId) {
    if (groups == null) return null;
    return groups.values.any((ids) => ids.contains(itemId));
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_loadCollections(), _loadPlaylists()]);
      _collections = results[0];
      _playlists = results[1];
      _fetched = DateTime.now();
    } catch (e) {
      log('Membership lookup failed: $e');
    }
  }

  Future<Map<String, Set<String>>?> _loadCollections() async {
    final response = await _api.usersUserIdItemsGet(recursive: true, includeItemTypes: [BaseItemKind.boxset]);
    final boxSets = response.body?.items ?? const <BaseItemDto>[];
    if (boxSets.length > maxLookups) return null;
    final entries = await Future.wait(boxSets.map((boxSet) async {
      final children = await _api.usersUserIdItemsGet(parentId: boxSet.id);
      return MapEntry(boxSet.id ?? '', (children.body?.items ?? const <BaseItemDto>[]).map((e) => e.id ?? '').toSet());
    }));
    return Map.fromEntries(entries);
  }

  Future<Map<String, Set<String>>?> _loadPlaylists() async {
    final response = await _api.usersUserIdItemsGet(recursive: true, includeItemTypes: [BaseItemKind.playlist]);
    final playlists = response.body?.items ?? const <BaseItemDto>[];
    if (playlists.length > maxLookups) return null;
    final entries = await Future.wait(playlists.map((playlist) async {
      final children = await _api.playlistsPlaylistIdItemsGet(
        playlistId: playlist.id,
        enableImages: false,
        enableUserData: false,
        fields: [],
      );
      return MapEntry(playlist.id ?? '', (children.body?.items ?? const []).map((e) => e.id).toSet());
    }));
    return Map.fromEntries(entries);
  }
}

final membershipCacheProvider = Provider<MembershipCache>((ref) => MembershipCache(ref));

/// Whether [itemId] is in any collection, and in any playlist.
final itemMembershipProvider = FutureProvider.autoDispose.family<ItemMembership, String>((ref, itemId) {
  return ref.watch(membershipCacheProvider).membershipOf(itemId);
});

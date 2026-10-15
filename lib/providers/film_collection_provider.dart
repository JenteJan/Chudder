import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/item_membership_provider.dart';
import 'package:chudder/providers/user_provider.dart';

final filmCollectionsProvider = Provider<FilmCollections>((ref) => FilmCollections(ref));

/// Which collection a film belongs to, and what else is in it - so a film
/// played on its own goes on with the rest of its collection, the way an
/// episode goes on with its show.
extension on List<({String id, String name})> {
  List<({String id, String name})> uniqueById() {
    final seen = <String>{};
    return where((collection) => seen.add(collection.id)).toList();
  }
}

class FilmCollections {
  FilmCollections(this.ref);

  final Ref ref;

  static const _maxAge = Duration(minutes: 10);
  Future<List<BaseItemDto>>? _boxSets;
  DateTime? _boxSetsAt;

  /// Every collection with its provider ids, in one request however many
  /// there are, kept a while.
  Future<List<BaseItemDto>> _allBoxSets() {
    final at = _boxSetsAt;
    if (_boxSets == null || at == null || DateTime.now().difference(at) > _maxAge) {
      _boxSetsAt = DateTime.now();
      _boxSets = ref
          .read(jellyApiProvider)
          .api
          .usersUserIdItemsGet(
            userId: ref.read(userProvider)?.id,
            recursive: true,
            includeItemTypes: [BaseItemKind.boxset],
            fields: [ItemFields.providerids],
            enableImages: false,
            enableUserData: false,
          )
          .then((response) => response.body?.items ?? const <BaseItemDto>[])
          .catchError((Object _) {
        _boxSets = null;
        return const <BaseItemDto>[];
      });
    }
    return _boxSets!;
  }

  static String? _id(Map<String, dynamic>? ids, String key) {
    final value = ids?.entries.firstWhereOrNull((entry) => entry.key.toLowerCase() == key)?.value?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  /// The collection [film] is in. A film from TMDB names its collection,
  /// which a collection made from it carries as its own TMDB id: one lookup.
  /// Without that, the collections are searched through.
  Future<({String id, String name})?> collectionOf(MovieModel film) async {
    final tmdbCollection = _id(film.providerIds, 'tmdbcollection');
    if (tmdbCollection != null) {
      final match = (await _allBoxSets()).firstWhereOrNull((set) => _id(set.providerIds, 'tmdb') == tmdbCollection);
      if (match?.id != null) return (id: match!.id!, name: match.name ?? '');
    }
    final known = await ref.read(membershipCacheProvider).collectionsOf(film.id);
    return known.firstOrNull;
  }

  /// Every collection [item] is in: its film collection, found through TMDB
  /// whatever the number of collections, and the ones the membership cache
  /// knows of. Empty when none or when that cannot be told.
  Future<List<({String id, String name})>> containing(ItemBaseModel item) async {
    final film = item is MovieModel ? await collectionOf(item).catchError((Object _) => null) : null;
    final found = <({String id, String name})>[
      if (film != null) film,
      ...await ref.read(membershipCacheProvider).collectionsOf(item.id),
    ];
    return found.where((collection) => collection.id.isNotEmpty).toList().uniqueById();
  }

  /// What [collectionId] holds that can be played, in the order its page
  /// lists it: by release.
  Future<List<ItemBaseModel>> playableIn(String collectionId) async {
    final response = await ref.read(jellyApiProvider).itemsGet(
      parentId: collectionId,
      sortBy: const [ItemSortBy.premieredate, ItemSortBy.productionyear, ItemSortBy.sortname],
      sortOrder: const [SortOrder.ascending],
      fields: const [ItemFields.primaryimageaspectratio, ItemFields.parentid, ItemFields.providerids],
    );
    return (response.body?.items ?? const <ItemBaseModel>[]).where((item) => item.playAble).toList();
  }
}

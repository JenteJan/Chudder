import 'package:collection/collection.dart';

import 'package:fladder/models/item_base_model.dart';

/// Jellyfin's `/Items` search is a filter, not a ranking: it hands back
/// everything whose name merely contains the term, ordered by sort name. For a
/// one-letter query that is alphabetical noise - the first five titles in the
/// alphabet that happen to hold an "a", not the five things you meant.
///
/// So we rank what comes back the way a person reads a result list: the exact
/// title first, then titles that start with what was typed, then titles with a
/// word starting with it, then the rest - and within each of those, the kinds
/// of thing you search for (a film, a show, a person) above the kinds you
/// stumble into (an episode, a track).
extension SearchRelevance on List<ItemBaseModel> {
  /// Best matches first. Stable, so items the server already ordered keep
  /// their relative places inside a tier.
  List<ItemBaseModel> rankedFor(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty || length < 2) return this;
    return sorted((a, b) => _compare(a, b, trimmed));
  }
}

int _compare(ItemBaseModel a, ItemBaseModel b, String query) {
  final nameTier = _nameTier(a.name, query).compareTo(_nameTier(b.name, query));
  if (nameTier != 0) return nameTier;

  final typeTier = _typeTier(a).compareTo(_typeTier(b));
  if (typeTier != 0) return typeTier;

  if (a.userData.isFavourite != b.userData.isFavourite) {
    return a.userData.isFavourite ? -1 : 1;
  }

  // A shorter title holding the query is the closer match: "Alien" before
  // "Aliens vs Predator" for "alien".
  final byLength = a.name.length.compareTo(b.name.length);
  if (byLength != 0) return byLength;

  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

final _wordBreak = RegExp(r"[\s\-:_/\()\[\]{}.,!?'’–—]+");

int _nameTier(String name, String query) {
  final value = name.trim().toLowerCase();
  if (value == query) return 0;
  if (value.startsWith(query)) return 1;
  if (value.split(_wordBreak).any((word) => word.startsWith(query))) return 2;
  if (value.contains(query)) return 3;
  // Matched on something the name does not show - an original title, an
  // overview - so it goes below everything that visibly matches.
  return 4;
}

int _typeTier(ItemBaseModel item) {
  // A studio reports itself as a base type - the bottom of the pile - when it
  // belongs up with the people as something you deliberately search for.
  if (item.isStudio) return 2;
  return switch (item.type) {
    FladderItemType.movie || FladderItemType.series => 0,
    FladderItemType.boxset || FladderItemType.playlist || FladderItemType.book => 1,
    FladderItemType.person || FladderItemType.musicArtist => 2,
    FladderItemType.musicAlbum || FladderItemType.photoAlbum || FladderItemType.tvchannel => 3,
    FladderItemType.season => 4,
    FladderItemType.episode || FladderItemType.audio || FladderItemType.musicVideo => 5,
    _ => 6,
  };
}

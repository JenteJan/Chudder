import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/seerr/seerr_dashboard_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/related_provider.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';

/// What a collection page shows: the boxset itself (artwork, overview,
/// genres) and everything inside it, in release order.
class CollectionDetails {
  const CollectionDetails({
    this.collection,
    this.children = const [],
    this.related = const [],
    this.seerrRecommended = const [],
    this.loading = true,
  });

  final ItemBaseModel? collection;
  final List<ItemBaseModel> children;

  /// What the server thinks goes with this collection — similar items,
  /// minus anything already inside it.
  final List<ItemBaseModel> related;

  /// Jellyseerr recommendations seeded from the newest entry.
  final List<SeerrDashboardPosterModel> seerrRecommended;

  final bool loading;

  /// The first thing in the collection the user hasn't finished — what the
  /// play button offers, the way a show's detail screen offers the next
  /// episode.
  ItemBaseModel? get nextToWatch =>
      children.where((child) => child.playAble).where((child) => !child.userData.played).firstOrNull ??
      children.where((child) => child.playAble).firstOrNull;

  /// A collection rarely carries artwork of its own beyond the poster, so
  /// borrow what's missing from what's inside it: the first child with
  /// backdrops lends those, the first with a logo lends the franchise mark.
  ImagesData? get effectiveImages {
    final own = collection?.images;
    final hasBackdrop = own?.backDrop?.isNotEmpty == true;
    if (hasBackdrop && own?.logo != null) return own;
    final childWithBackdrop = children.firstWhereOrNull((c) => c.images?.backDrop?.isNotEmpty == true)?.images;
    final childWithLogo = children.firstWhereOrNull((c) => c.images?.logo != null)?.images;
    if (own == null && childWithBackdrop == null && childWithLogo == null) return null;
    return ImagesData(
      primary: own?.primary ?? childWithBackdrop?.primary,
      backDrop: hasBackdrop ? own?.backDrop : childWithBackdrop?.backDrop,
      logo: own?.logo ?? childWithLogo?.logo,
    );
  }

  /// How much of the collection has been watched, for the header line.
  int get watchedCount => children.where((c) => c.userData.played).length;

  /// Combined runtime of everything inside — the "how long is this whole
  /// franchise" number.
  Duration get totalRunTime =>
      children.fold(Duration.zero, (total, c) => total + (c.overview.runTime ?? Duration.zero));

  /// The faces of the franchise: people who appear in more than one entry,
  /// most appearances first. A single film's one-off cast says little about
  /// the collection; the recurring names are what tie it together.
  List<Person> get recurringCast {
    final counts = <String, int>{};
    final byId = <String, Person>{};
    for (final child in children) {
      for (final person in child.overview.people) {
        counts.update(person.id, (v) => v + 1, ifAbsent: () => 1);
        byId.putIfAbsent(person.id, () => person);
      }
    }
    final recurring = counts.entries.where((e) => e.value > 1).toList()..sort((a, b) => b.value.compareTo(a.value));
    return recurring.take(15).map((e) => byId[e.key]).nonNulls.toList();
  }

  /// Release-year span of the contents, e.g. "2001 – 2011".
  String? get yearSpan {
    final years = children.map((e) => e.overview.productionYear).nonNulls.toList()..sort();
    if (years.isEmpty) return null;
    return years.first == years.last ? years.first.toString() : "${years.first} – ${years.last}";
  }

  CollectionDetails copyWith({
    ItemBaseModel? collection,
    List<ItemBaseModel>? children,
    List<ItemBaseModel>? related,
    List<SeerrDashboardPosterModel>? seerrRecommended,
    bool? loading,
  }) =>
      CollectionDetails(
        collection: collection ?? this.collection,
        children: children ?? this.children,
        related: related ?? this.related,
        seerrRecommended: seerrRecommended ?? this.seerrRecommended,
        loading: loading ?? this.loading,
      );
}

final collectionDetailsProvider =
    StateNotifierProvider.autoDispose.family<CollectionDetailsNotifier, CollectionDetails, String>((ref, id) {
  return CollectionDetailsNotifier(ref, id);
});

class CollectionDetailsNotifier extends StateNotifier<CollectionDetails> {
  CollectionDetailsNotifier(this.ref, this.collectionId) : super(const CollectionDetails());

  final Ref ref;
  final String collectionId;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> fetch(ItemBaseModel? known) async {
    state = state.copyWith(collection: known, loading: true);

    // The tapped poster only carries what its row happened to hold; the full
    // item brings the overview, genres and complete artwork.
    final collectionFuture = api.usersUserIdItemsItemIdGet(itemId: collectionId);
    final childrenFuture = api.itemsGet(
      parentId: collectionId,
      fields: [
        ItemFields.overview,
        ItemFields.primaryimageaspectratio,
        ItemFields.parentid,
        // For the Jellyseerr rows (tmdbId lives in the provider ids).
        ItemFields.providerids,
      ],
      sortBy: _childrenSort,
      sortOrder: [SortOrder.ascending],
    )..ignore();
    // The cast of every entry, for the recurring-cast row, in a request of
    // its own. Serialising everyone in every film is most of the server's
    // work for a collection, and in the request above it held back every
    // poster on the page (and the backdrop borrowed from one) for a row at
    // the bottom of it.
    final peopleFuture = api
        .itemsGet(
          parentId: collectionId,
          fields: [ItemFields.people],
          enableUserData: false,
          sortBy: _childrenSort,
          sortOrder: [SortOrder.ascending],
        )
        .then<Map<String, List<Person>>?>(
          (response) => response.body == null
              ? null
              : {for (final child in response.body!.items) child.id: child.overview.people},
        )
        .catchError((Object error, StackTrace stack) {
      log('Failed to fetch the cast of collection $collectionId due to $error',
          level: logging.Level.WARNING.value, error: error, stackTrace: stack);
      return null;
    });
    final similarFuture = _similar(collectionId);

    final collection = await collectionFuture;
    if (!mounted) return;
    if (collection.isSuccessful && collection.body != null) {
      state = state.copyWith(collection: collection.bodyOrThrow);
    }

    final children = await childrenFuture;
    if (!mounted) return;
    // Until the cast is in, a refresh keeps the cast the entries already had
    // rather than dropping the row for a moment.
    final knownPeople = <String, List<Person>>{
      for (final child in state.children) child.id: child.overview.people,
    };
    state = state.copyWith(
      children: _withPeople(children.body?.items ?? [], _people ?? knownPeople),
      loading: false,
    );

    await Future.wait([
      peopleFuture.then((people) {
        if (!mounted || people == null) return;
        _people = people;
        state = state.copyWith(children: _withPeople(state.children, people));
      }),
      _fetchRelated(similarFuture),
      _fetchFromSeerr(),
    ]);
  }

  static const _childrenSort = [ItemSortBy.premieredate, ItemSortBy.productionyear, ItemSortBy.sortname];

  /// The cast from the latest cast request, once it is in.
  Map<String, List<Person>>? _people;

  List<ItemBaseModel> _withPeople(List<ItemBaseModel> children, Map<String, List<Person>> people) => children.map(
        (child) {
          final cast = people[child.id];
          if (cast == null || identical(cast, child.overview.people)) return child;
          return child.copyWith(overview: child.overview.copyWith(people: cast));
        },
      ).toList();

  Future<List<ItemBaseModel>> _similar(String itemId) => ref
          .read(relatedUtilityProvider)
          .relatedContent(itemId)
          .then((response) => response.body ?? <ItemBaseModel>[])
          .catchError((Object error, StackTrace stack) {
        log('Failed to fetch items similar to $itemId due to $error',
            level: logging.Level.WARNING.value, error: error, stackTrace: stack);
        return <ItemBaseModel>[];
      });

  /// Similar items, tried on the boxset itself first (Jellyfin matches on
  /// its genres) and falling back to the newest entry when that comes back
  /// empty. Anything already inside the collection is dropped.
  Future<void> _fetchRelated(Future<List<ItemBaseModel>> similarToCollection) async {
    var related = await similarToCollection;
    if (!mounted) return;
    if (related.isEmpty && state.children.isNotEmpty) {
      related = await _similar(state.children.last.id);
    }
    if (!mounted) return;
    final childIds = state.children.map((c) => c.id).toSet();
    state = state.copyWith(
      related: related.where((item) => !childIds.contains(item.id) && item.id != collectionId).toList(),
    );
  }

  /// Recommendations seeded from the newest entry's TMDB id — the closest
  /// thing to "what does this franchise's crowd also watch".
  Future<void> _fetchFromSeerr() async {
    if (ref.read(userProvider)?.seerrCredentials?.isConfigured != true) return;
    final tmdbId = state.children.reversed.map((c) => c.tmdbId).nonNulls.firstOrNull;
    if (tmdbId == null) return;
    try {
      final recommended = await ref.read(seerrApiProvider).discoverRecommendedMovies(tmdbId: tmdbId);
      if (!mounted) return;
      state = state.copyWith(seerrRecommended: recommended);
    } catch (_) {
      // Seerr being down shouldn't dent the page.
    }
  }
}

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/related_provider.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';

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
    final recurring = counts.entries.where((e) => e.value > 1).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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
        // For the recurring-cast row.
        ItemFields.people,
        // For the Jellyseerr rows (tmdbId lives in the provider ids).
        ItemFields.providerids,
      ],
      sortBy: [ItemSortBy.premieredate, ItemSortBy.productionyear, ItemSortBy.sortname],
      sortOrder: [SortOrder.ascending],
    );

    final collection = await collectionFuture;
    if (mounted && collection.isSuccessful && collection.body != null) {
      state = state.copyWith(collection: collection.bodyOrThrow);
    }

    final children = await childrenFuture;
    if (!mounted) return;
    state = state.copyWith(
      children: children.body?.items ?? [],
      loading: false,
    );

    await _fetchRelated();
    await _fetchFromSeerr();
  }

  /// Similar items, tried on the boxset itself first (Jellyfin matches on
  /// its genres) and falling back to the newest entry when that comes back
  /// empty. Anything already inside the collection is dropped.
  Future<void> _fetchRelated() async {
    final childIds = state.children.map((c) => c.id).toSet();
    var related = (await ref.read(relatedUtilityProvider).relatedContent(collectionId)).body ?? [];
    if (related.isEmpty && state.children.isNotEmpty) {
      related = (await ref.read(relatedUtilityProvider).relatedContent(state.children.last.id)).body ?? [];
    }
    if (!mounted) return;
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

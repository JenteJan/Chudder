import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/movie_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/items/movie_details_prefetch_provider.dart';
import 'package:fladder/providers/items/series_next_up_provider.dart';

/// Whatever the page an item opens will need first, asked for before the page
/// exists.
///
/// One place that knows, per kind of item, what its detail page waits on - a
/// show waits on its next-up episode, a film on its streams - so a card does
/// not have to. Every card calls [ItemPrefetch.prefetch] from its hover and
/// focus, and [ItemBaseModel.navigateTo] calls it again on the way out, so a
/// card that forgot still gets the request started a transition earlier than
/// the page could have.
///
/// Anything this does not know about is a no-op; add a case here, not in a
/// card, when a page gains something worth asking for ahead.
final itemPrefetchProvider = Provider<ItemPrefetch>(ItemPrefetch.new);

class ItemPrefetch {
  ItemPrefetch(this.ref);

  final Ref ref;

  void prefetch(ItemBaseModel? item) {
    switch (item) {
      case MovieModel():
        ref.read(movieDetailsPrefetchProvider).prefetch(item.id);
      case SeriesModel():
        ref.read(seriesNextUpProvider).prefetch(item.id);
      // Both open the show's page, which names the show's next-up episode on
      // its play button until something is picked.
      case EpisodeModel():
        // An episode's parent is its show - see [EpisodeModel.fromBaseDto].
        ref.read(seriesNextUpProvider).prefetch(item.parentId);
      case SeasonModel():
        ref.read(seriesNextUpProvider).prefetch(item.seriesId);
      default:
        break;
    }
  }
}

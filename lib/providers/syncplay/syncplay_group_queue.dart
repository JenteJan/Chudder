/// The most jellyfin-web asks the server for when it reads a group's queue. It
/// pairs what comes back with the queue by place, so one longer than this has
/// it reporting the wrong item.
const int maxGroupQueueLength = 300;

/// The part of a queue a group can be handed: all of it, or [limit] items
/// around what plays with what comes next favoured.
({List<String> itemIds, int position}) groupQueueWindow(
  List<String> itemIds,
  int position, {
  int limit = maxGroupQueueLength,
}) {
  if (itemIds.length <= limit) return (itemIds: itemIds, position: position);
  final start = (position - 20).clamp(0, itemIds.length - limit);
  return (itemIds: itemIds.sublist(start, start + limit), position: position - start);
}

/// What a Ready says about the player: whether it is running, as jellyfin-web
/// says it. The server treats the two differently. A member that claims to be
/// running while paused and is the last one in, a little behind, is sent no
/// Unpause at all - the server takes it to be on its way already.
///
/// Two exceptions, both where a true "paused" would get the Ready refused
/// until the group's wait runs out: a member with nothing loaded is not
/// watching and must not hold anyone, and the file can run on past the length
/// the server has for it, where the server cuts the position short of the
/// group's and only a running member is given the room.
bool readyClaimsRunning({
  required bool playerRunning,
  required bool hasPlayer,
  required int positionTicks,
  required int durationTicks,
}) {
  if (playerRunning || !hasPlayer) return true;
  return durationTicks > 0 && positionTicks >= durationTicks - 10000000;
}

/// The group's queue as the server last sent it: the items in the order the
/// group steps through them, the server's own id for each place in it, and
/// the place that is playing.
///
/// An item can stand in the queue more than once, so an edit names a place,
/// not an item: the server moves and removes by the place's id.
class GroupQueue {
  const GroupQueue({this.itemIds = const [], this.placeIds = const [], this.index = -1});

  final List<String> itemIds;

  /// The server's PlaylistItemId for each place, in the same order.
  final List<String> placeIds;

  /// The place playing, or -1.
  final int index;

  static const empty = GroupQueue();

  int get length => itemIds.length;

  /// The place [itemId] would be meant at: the first after what plays, the
  /// way the lists show what is coming; else the first anywhere. -1 when it
  /// is not in the queue.
  int positionOf(String itemId) {
    for (var i = index + 1; i < itemIds.length; i++) {
      if (itemIds[i] == itemId) return i;
    }
    return itemIds.indexOf(itemId);
  }

  /// The server's id for the place of [itemId]; see [positionOf].
  String? placeOf(String itemId) {
    final at = positionOf(itemId);
    return at >= 0 && at < placeIds.length ? placeIds[at] : null;
  }

  /// The index to move [itemId] to so it plays straight after what plays.
  ///
  /// The server takes the item out before putting it back: one from before
  /// what plays leaves a gap there, and what plays moves up one.
  int nextIndexFor(String itemId) {
    final at = positionOf(itemId);
    final after = index + 1;
    return (at >= 0 && at < index ? after - 1 : after).clamp(0, length - 1);
  }

  /// The items of [known] in the group's order, each place once. Items not
  /// in [known] are left out.
  List<T> ordered<T>(Map<String, T> known) => [
        for (final id in itemIds)
          ?known[id],
      ];

  /// The group's items that are not among [known].
  Set<String> missingFrom(Iterable<String> known) {
    final have = known.toSet();
    return {
      for (final id in itemIds)
        if (id.isNotEmpty && !have.contains(id)) id,
    };
  }
}

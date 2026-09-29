import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What is being done to a download as a whole, right now.
enum ItemActivityKind {
  /// Its metadata is being read from the server again.
  refreshing,

  /// The server is being asked what it has that is not here yet.
  searching,

  /// It is being taken off the device.
  deleting,
}

class ItemActivity {
  const ItemActivity(this.kind, {this.done = 0, this.total = 0});

  final ItemActivityKind kind;

  /// How far along, when that is known ([total] is 0 when it is not).
  final int done;
  final int total;

  double? get fraction => total > 0 ? (done / total).clamp(0.0, 1.0) : null;

  ItemActivity copyWith({int? done, int? total}) => ItemActivity(kind, done: done ?? this.done, total: total ?? this.total);
}

/// One thing at a time per download. Widgets follow it to show a spinner and
/// to keep buttons still while something is under way; the operations use
/// [ItemActivityNotifier.run] so that a second press while one runs is refused
/// instead of started alongside it, and so the marker is cleared however the
/// operation ends.
class ItemActivityNotifier extends StateNotifier<Map<String, ItemActivity>> {
  ItemActivityNotifier() : super(const {});

  bool isBusy(String id) => state.containsKey(id);

  /// Marks [id] as busy. False when it already is, and nothing changes.
  bool begin(String id, ItemActivityKind kind, {int total = 0}) {
    if (state.containsKey(id)) return false;
    state = {...state, id: ItemActivity(kind, total: total)};
    return true;
  }

  void progress(String id, {required int done, int? total}) {
    final current = state[id];
    if (current == null) return;
    state = {...state, id: current.copyWith(done: done, total: total)};
  }

  void end(String id) {
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }

  /// Runs [action] as [kind] on [id]. Null, without running it, when [id] is
  /// busy already. The marker is cleared whether [action] returns or throws.
  Future<T?> run<T>(
    String id,
    ItemActivityKind kind,
    Future<T> Function() action, {
    int total = 0,
  }) async {
    if (!begin(id, kind, total: total)) return null;
    try {
      return await action();
    } finally {
      if (mounted) end(id);
    }
  }
}

final itemActivityProvider = StateNotifierProvider<ItemActivityNotifier, Map<String, ItemActivity>>(
  (ref) => ItemActivityNotifier(),
);

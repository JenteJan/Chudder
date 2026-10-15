import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/language_preferences_model.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';

/// Where [RememberedQueues] are kept. Device only, like the languages.
const rememberedQueuesKey = 'rememberedQueues';

/// A collection's queue as it was last played from the collection's page, so
/// that a film in it picked up later - from Continue watching, say - plays on
/// with the same queue instead of on its own.
class RememberedQueue {
  const RememberedQueue({
    required this.userId,
    required this.scope,
    required this.itemIds,
    required this.savedAt,
  });

  final String userId;
  final LanguageScope scope;

  /// In the order they played, a show already stood in for by its episodes.
  final List<String> itemIds;
  final DateTime savedAt;

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'id': scope.id,
        'name': scope.name,
        'kind': scope.kind.name,
        'itemIds': itemIds,
        'savedAt': savedAt.toIso8601String(),
      };

  static RememberedQueue? fromMap(Object? map) {
    if (map is! Map) return null;
    final kind = LanguageScopeKind.values.firstWhereOrNull((kind) => kind.name == map['kind']);
    final savedAt = DateTime.tryParse(map['savedAt']?.toString() ?? '');
    final ids = map['itemIds'];
    if (kind == null || savedAt == null || ids is! List || map['id'] is! String) return null;
    return RememberedQueue(
      userId: map['userId']?.toString() ?? '',
      scope: LanguageScope(id: map['id'] as String, name: map['name']?.toString() ?? '', kind: kind),
      itemIds: ids.map((id) => id.toString()).toList(),
      savedAt: savedAt,
    );
  }
}

final rememberedQueuesProvider = Provider<RememberedQueues>((ref) => RememberedQueues(ref));

class RememberedQueues {
  RememberedQueues(this.ref);

  final Ref ref;

  /// Collections remembered at most; the one played longest ago goes first.
  static const maxQueues = 20;

  /// Longer than this unplayed, a collection's queue is not taken up again.
  static const maxAge = Duration(days: 120);

  List<RememberedQueue> _read() {
    try {
      final stored = ref.read(sharedPreferencesProvider).getString(rememberedQueuesKey);
      if (stored == null) return [];
      return (jsonDecode(stored) as List).map(RememberedQueue.fromMap).nonNulls.toList();
    } catch (_) {
      return [];
    }
  }

  void _write(List<RememberedQueue> queues) {
    try {
      ref
          .read(sharedPreferencesProvider)
          .setString(rememberedQueuesKey, jsonEncode(queues.map((queue) => queue.toMap()).toList()));
    } catch (_) {}
  }

  String get _userId => ref.read(userProvider)?.id ?? '';

  /// Keeps [itemIds] as the queue of the collection [scope], in place of
  /// whatever was kept for it before.
  void remember(LanguageScope scope, List<String> itemIds) {
    if (scope.kind != LanguageScopeKind.collection || itemIds.length < 2) return;
    final userId = _userId;
    final queues = _read()..removeWhere((queue) => queue.userId == userId && queue.scope.id == scope.id);
    // Kept in the order played, the latest last.
    queues.add(RememberedQueue(userId: userId, scope: scope, itemIds: itemIds, savedAt: DateTime.now()));
    _write(queues.length > maxQueues ? queues.sublist(queues.length - maxQueues) : queues);
  }

  /// The queue [itemId] last played in, when that was a collection's.
  RememberedQueue? containing(String itemId) {
    final userId = _userId;
    final now = DateTime.now();
    return _read().reversed.firstWhereOrNull(
        (queue) => queue.userId == userId && now.difference(queue.savedAt) < maxAge && queue.itemIds.contains(itemId));
  }

  /// Notes that [scope]'s queue was taken up again, so it is not the first
  /// to be forgotten.
  void touch(RememberedQueue queue) => remember(queue.scope, queue.itemIds);
}

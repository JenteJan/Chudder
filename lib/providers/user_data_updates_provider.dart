import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/providers/websocket/jellyfin_websocket_provider.dart';
import 'package:chudder/providers/websocket/websocket_log.dart';

/// One batch of what the server has just been told about what you have
/// watched, by item id.
///
/// A batch rather than a single item because that is how the server sends it:
/// finishing an episode moves the episode, its season and its series in one
/// message.
class UserDataUpdate {
  final Map<String, UserData> byId;

  const UserDataUpdate(this.byId);

  UserData? operator [](String id) => byId[id];
}

/// What the server pushes about your own watch state, as it arrives.
///
/// Jellyfin sends a UserDataChanged message whenever anything is played,
/// marked or favourited - by this client or any other. Every one of them was
/// decoded, re-broadcast and thrown away: the only listener on that socket is
/// SyncPlay, which drops everything that is not a SyncPlay message. So the way
/// a page learned that the film it is showing had been watched was to fetch the
/// whole film again when the player closed.
///
/// Anything holding items listens here instead and folds the new state into
/// what it already has. Nothing about *which* items belong in a row comes from
/// this - next-up, the unplayed counts on a season and the order of the
/// dashboard are the server's to work out - only what the items themselves say
/// about having been watched.
final userDataUpdatesProvider = StateNotifierProvider<UserDataUpdatesNotifier, UserDataUpdate?>(
  (ref) => UserDataUpdatesNotifier(ref),
);

class UserDataUpdatesNotifier extends StateNotifier<UserDataUpdate?> {
  UserDataUpdatesNotifier(this.ref) : super(null) {
    // The re-broadcast stream, not the socket itself, so an account switch or
    // a socket rebuild is invisible here.
    _subscription = ref.read(jellyfinWebSocketControllerProvider.notifier).messages.listen(_onMessage);
  }

  final Ref ref;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  void _onMessage(Map<String, dynamic> message) {
    if (message['MessageType'] != 'UserDataChanged') return;

    final Map<String, UserData> byId = {};
    try {
      final changed = UserDataChangedMessage.fromJson(message).data?.userDataList ?? const [];
      for (final entry in changed) {
        final id = entry.itemId;
        if (id == null || id.isEmpty) continue;
        byId[id] = UserData.fromDto(entry);
      }
    } catch (e) {
      // A message we cannot read is worth saying so about once, and nothing
      // more: the page is no worse off than before this existed.
      log('UserDataChanged: could not be read: $e');
      return;
    }

    if (byId.isEmpty) return;
    // A new object each time, so a second message saying the same thing still
    // reaches whoever is listening.
    state = UserDataUpdate(byId);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

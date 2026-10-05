import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/user_provider.dart';

/// How many upcoming items go to the receiver with a `PlayNow`. A season is
/// well inside this, and the message stays a fraction of the 64 KB the Cast
/// channel carries; a longer queue is picked up by the phone once the
/// receiver's list runs out.
const castQueueLimit = 50;

/// The minimal item the Jellyfin receiver takes in a `PlayNow`:
/// `{Id, ServerId, Name, Type, MediaType, IsFolder}`. It fetches everything
/// else about the item from the server itself.
Map<String, dynamic> jellyfinItemStub(ItemBaseModel item, {required String? serverId, bool audio = false}) => {
      'Id': item.id,
      'ServerId': serverId,
      'Name': item.name,
      // Jellyfin expects PascalCase Type values ("Episode"), which is the
      // enum's JsonValue (`.value`) — `.name` gives the lowercase Dart id.
      'Type': item.jellyType?.value,
      'MediaType': audio ? 'Audio' : 'Video',
      'IsFolder': false,
    };

/// The items that follow the one [model] plays, in the order the app itself
/// would play them, as stubs for the receiver's queue. Empty for music (the
/// phone drives that queue) and once the queue is past its limit.
List<Map<String, dynamic>> upcomingItemStubs(
  PlaybackModel model, {
  required String? serverId,
  int limit = castQueueLimit,
}) {
  if (model.isAudioPlayback) return const [];
  final seen = <String>{model.item.id};
  return [
    for (final item in model.playbackQueue.queueForDisplay(model.item.id, wrapAround: false))
      if (seen.add(item.id)) jellyfinItemStub(item, serverId: serverId),
  ].take(limit).toList();
}

/// What to queue on the receiver behind the item [model] plays: nothing when
/// the user turned auto-play off, or a SyncPlay group decides what comes next.
///
/// An empty queue is meaningful — see `playNowItems`: it keeps the receiver
/// from building a queue of its own.
List<Map<String, dynamic>> castUpcomingFor(Ref ref, PlaybackModel? model) {
  if (model == null) return const [];
  if (ref.read(videoPlayerSettingsProvider).nextVideoType == AutoNextType.off) return const [];
  if (ref.read(isSyncPlayActiveProvider)) return const [];
  return upcomingItemStubs(model, serverId: ref.read(userProvider)?.credentials.serverId);
}

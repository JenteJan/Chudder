import 'dart:convert';

import 'package:flutter/widgets.dart' show ImageProvider;

import 'package:chudder/models/settings/subtitle_settings_model.dart';

/// The Jellyfin Cast receiver's custom namespace.
const jellyfinCastNamespace = 'urn:x-cast:com.connectsdk';

/// The Jellyfin receiver's app id (the modern JS receiver that plays the item
/// server-side). Shared by the mobile (native SDK) and web (Cast Web Sender)
/// senders.
const jellyfinReceiverAppId = 'F007D354';

/// The connection + item context the Jellyfin receiver needs to play. Mirrors
/// the message the jellyfin-web sender builds. Transport-agnostic — used by the
/// native ([JellyfinCastPlayer]) and web ([WebJellyfinCastPlayer]) senders.
class JellyfinCastContext {
  final String serverAddress;
  final String accessToken;
  final String userId;
  final String deviceId;
  final String serverId;
  final String serverVersion;

  /// The minimal item stub the receiver expects:
  /// `{Id, ServerId, Name, Type, MediaType, IsFolder}`.
  final Map<String, dynamic> itemStub;
  final Duration startPosition;
  final int? maxBitrate;

  /// The media source (version) to play. REQUIRED for track selection: the
  /// server ignores AudioStreamIndex/SubtitleStreamIndex in PlaybackInfo
  /// unless MediaSourceId is sent along with them.
  final String? mediaSourceId;

  /// Backdrop/poster for the casting placeholder UI.
  final ImageProvider? image;

  /// The phone's selected tracks, carried into PlayNow so the receiver doesn't
  /// fall back to the server defaults.
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  /// The app's subtitle look for the first PlayNow (see
  /// [receiverSubtitleAppearance]); later changes follow through the player.
  final Map<String, dynamic>? subtitleAppearance;

  /// The items queued behind [itemStub], for the receiver to carry on with
  /// when this one ends.
  final List<Map<String, dynamic>> upcoming;

  const JellyfinCastContext({
    required this.serverAddress,
    required this.accessToken,
    required this.userId,
    required this.deviceId,
    required this.serverId,
    required this.serverVersion,
    required this.itemStub,
    required this.startPosition,
    this.maxBitrate,
    this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.subtitleAppearance,
    this.upcoming = const [],
    this.image,
  });
}

/// Builds the full message envelope (command + credentials) the receiver
/// expects, as a JSON string on the Jellyfin namespace.
///
/// [receiverName] names the receiver's own server session ("Living room TV"
/// rather than "Google Cast"), and the receiver reads it once, from the first
/// message it gets — so every message carries it.
String buildJellyfinEnvelope({
  required String command,
  required Map<String, dynamic> options,
  required JellyfinCastContext context,
  required String receiverName,
  int? maxBitrate,
  Map<String, dynamic>? subtitleAppearance,
}) {
  return jsonEncode({
    'command': command,
    'options': options,
    'userId': context.userId,
    'deviceId': context.deviceId,
    'accessToken': context.accessToken,
    'serverAddress': context.serverAddress,
    'serverId': context.serverId,
    'serverVersion': context.serverVersion,
    'receiverName': receiverName,
    if (maxBitrate != null) 'maxBitrate': maxBitrate,
    if (subtitleAppearance != null) 'subtitleAppearance': subtitleAppearance,
  });
}

/// The `items` of a `PlayNow`: [current], then what follows it.
///
/// The receiver treats a lone `Episode` as "keep going": if the account has
/// next-episode autoplay on, it fetches the rest of the *series* and queues
/// that itself. With nothing queued here (auto-play off in Chudder, a SyncPlay
/// group, the last episode) that would play on regardless, so the type goes
/// out as plain `Video` and the receiver plays just the one. It fetches the
/// full item by id, so nothing else reads the type.
List<Map<String, dynamic>> playNowItems(Map<String, dynamic> current, List<Map<String, dynamic>> upcoming) {
  if (upcoming.isEmpty && current['Type'] == 'Episode') {
    return [
      {...current, 'Type': 'Video'},
    ];
  }
  return [current, ...upcoming];
}

/// Builds the `PlayNow` options. The server ignores the track indexes unless
/// `mediaSourceId` is sent too.
///
/// [upcoming] is the queue behind the item: the receiver plays it on its own
/// when the item ends, whether or not this app is still around.
///
/// The subtitle index always goes out, as -1 for none: the receiver only
/// attaches the item's subtitle tracks when the server answers with a
/// selection, and with no index sent the server may pick none — after which
/// switching subtitles on did nothing.
Map<String, dynamic> buildPlayNowOptions({
  required Map<String, dynamic> itemStub,
  required Duration startPosition,
  List<Map<String, dynamic>> upcoming = const [],
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
}) {
  return {
    'items': playNowItems(itemStub, upcoming),
    'startPositionTicks': startPosition.inMilliseconds * 10000,
    'startIndex': 0,
    if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
    if (audioStreamIndex != null) 'audioStreamIndex': audioStreamIndex,
    'subtitleStreamIndex': subtitleStreamIndex ?? -1,
  };
}

/// The app's subtitle look in the receiver's `subtitleAppearance` terms, so
/// the TV draws subtitles like the phone does. The receiver understands a
/// colour, a size bucket, an edge style and a transparent background; the
/// rest (weight, position) it has no way to show.
Map<String, dynamic> receiverSubtitleAppearance(SubtitleSettingsModel settings) {
  final rgb = settings.color.toARGB32() & 0xFFFFFF;
  final scale = settings.fontSize / const SubtitleSettingsModel().fontSize;
  final String? textSize = switch (scale) {
    < 0.7 => 'smaller',
    < 0.9 => 'small',
    < 1.075 => null,
    < 1.22 => 'large',
    < 1.37 => 'larger',
    _ => 'extralarge',
  };
  // CAF edge types, which the receiver hands on as they are.
  final edge = settings.outlineSize > 0 && settings.outlineColor.a > 0.05
      ? 'OUTLINE'
      : settings.shadow > 0.01
          ? 'DROP_SHADOW'
          : 'NONE';
  return {
    'textColor': '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}',
    if (textSize != null) 'textSize': textSize,
    'dropShadow': edge,
    if (settings.backGroundColor.a < 0.1) 'textBackground': 'transparent',
  };
}

/// A parsed receiver → sender status message. Messages are
/// `{type, data:{PlayState:{...}, NowPlayingItem:{...}}}` (ticks = 100ns units).
class ReceiverReport {
  final String? type;
  final bool? playing;
  final Duration? position;
  final Duration? duration;
  final String? itemId;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  /// Receiver device volume 0–100, so the phone's volume keys/slider can
  /// track it.
  final int? volumeLevel;

  /// The text of an error report (the receiver puts it beside `data`, not in
  /// it).
  final String? message;

  /// What the Cast media session itself says (`MEDIA_STATUS`): `PLAYING`,
  /// `BUFFERING`, `PAUSED`, `IDLE`, and the position it has reached. The
  /// receiver's own reports to this app are sparse; this is the plain truth
  /// about whether the TV is playing.
  final String? mediaPlayerState;
  final Duration? mediaCurrentTime;

  const ReceiverReport({
    this.type,
    this.playing,
    this.position,
    this.duration,
    this.itemId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.volumeLevel,
    this.message,
    this.mediaPlayerState,
    this.mediaCurrentTime,
  });

  /// `connectionerror` (the TV cannot reach the server), `playbackerror` (the
  /// item cannot be played) or `error` (a message it could not use).
  bool get isError => type == 'error' || type == 'playbackerror' || type == 'connectionerror';
}

/// Parses a raw receiver message, or null if it isn't a JSON object.
ReceiverReport? parseReceiverMessage(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;

  final type = decoded['type'] as String?;
  final body = decoded['data'];
  String? itemId;
  bool? playing;
  Duration? position;
  Duration? duration;
  int? audioStreamIndex;
  int? subtitleStreamIndex;
  int? volumeLevel;

  if (body is Map) {
    final reportedItemId = body['ItemId'];
    if (reportedItemId is String && reportedItemId.isNotEmpty) itemId = reportedItemId;

    final playState = body['PlayState'];
    if (playState is Map) {
      final isPaused = playState['IsPaused'];
      if (isPaused is bool) playing = !isPaused;
      final ticks = playState['PositionTicks'];
      if (ticks is num) position = Duration(microseconds: (ticks / 10).round());
      final audioIndex = playState['AudioStreamIndex'];
      if (audioIndex is int) audioStreamIndex = audioIndex;
      final subIndex = playState['SubtitleStreamIndex'];
      if (subIndex is int) subtitleStreamIndex = subIndex;
      final volume = playState['VolumeLevel'];
      if (volume is num) volumeLevel = volume.round().clamp(0, 100);
    }

    final nowPlaying = body['NowPlayingItem'];
    if (nowPlaying is Map) {
      final runtimeTicks = nowPlaying['RunTimeTicks'];
      if (runtimeTicks is num && runtimeTicks > 0) duration = Duration(microseconds: (runtimeTicks / 10).round());
    }
  }

  String? mediaPlayerState;
  Duration? mediaCurrentTime;
  final status = decoded['status'];
  if (type == 'MEDIA_STATUS' && status is List && status.isNotEmpty && status.first is Map) {
    final first = status.first as Map;
    final state = first['playerState'];
    if (state is String) mediaPlayerState = state;
    final time = first['currentTime'];
    if (time is num) mediaCurrentTime = Duration(milliseconds: (time * 1000).round());
  }

  final message = decoded['message'];
  return ReceiverReport(
    type: type,
    playing: playing,
    position: position,
    duration: duration,
    itemId: itemId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex,
    volumeLevel: volumeLevel,
    message: message is String && message.isNotEmpty ? message : null,
    mediaPlayerState: mediaPlayerState,
    mediaCurrentTime: mediaCurrentTime,
  );
}

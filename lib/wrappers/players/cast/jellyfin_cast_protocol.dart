import 'dart:convert';

import 'package:flutter/widgets.dart' show ImageProvider;

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
    this.image,
  });
}

/// Builds the full message envelope (command + credentials) the receiver
/// expects, as a JSON string on the Jellyfin namespace.
String buildJellyfinEnvelope({
  required String command,
  required Map<String, dynamic> options,
  required JellyfinCastContext context,
  required String receiverName,
  int? maxBitrate,
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
  });
}

/// Builds the `PlayNow` options. The server ignores the track indexes unless
/// `mediaSourceId` is sent too.
Map<String, dynamic> buildPlayNowOptions({
  required Map<String, dynamic> itemStub,
  required Duration startPosition,
  String? mediaSourceId,
  int? audioStreamIndex,
  int? subtitleStreamIndex,
}) {
  return {
    'items': [itemStub],
    'startPositionTicks': startPosition.inMilliseconds * 10000,
    'startIndex': 0,
    if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
    if (audioStreamIndex != null) 'audioStreamIndex': audioStreamIndex,
    if (subtitleStreamIndex != null) 'subtitleStreamIndex': subtitleStreamIndex,
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

  const ReceiverReport({
    this.type,
    this.playing,
    this.position,
    this.duration,
    this.itemId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
  });
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
    }

    final nowPlaying = body['NowPlayingItem'];
    if (nowPlaying is Map) {
      final runtimeTicks = nowPlaying['RunTimeTicks'];
      if (runtimeTicks is num) duration = Duration(microseconds: (runtimeTicks / 10).round());
    }
  }

  return ReceiverReport(
    type: type,
    playing: playing,
    position: position,
    duration: duration,
    itemId: itemId,
    audioStreamIndex: audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex,
  );
}

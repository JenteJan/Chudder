import 'dart:convert';

/// CASTV2 namespaces, well-known endpoint ids, JSON payload builders and the
/// status parsers used by the desktop Cast sender. Pure data/string logic —
/// no IO — so all of it is unit-testable.
class CastProtocol {
  CastProtocol._();

  // Namespaces.
  static const tpConnection = 'urn:x-cast:com.google.cast.tp.connection';
  static const tpHeartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const receiver = 'urn:x-cast:com.google.cast.receiver';
  static const media = 'urn:x-cast:com.google.cast.media';

  /// The custom namespace the Jellyfin Cast receiver speaks (shared verbatim
  /// with the mobile bridge — see `jellyfin_cast_channel.dart`).
  static const jellyfin = 'urn:x-cast:com.connectsdk';

  // Endpoint ids.
  static const senderId = 'sender-0';

  /// The platform receiver (the device itself), as opposed to a launched app's
  /// transport id (learned from a RECEIVER_STATUS after LAUNCH).
  static const platformReceiverId = 'receiver-0';

  // tp.connection
  static String connect() => jsonEncode({'type': 'CONNECT'});
  static String close() => jsonEncode({'type': 'CLOSE'});

  // tp.heartbeat
  static String ping() => jsonEncode({'type': 'PING'});
  static String pong() => jsonEncode({'type': 'PONG'});

  // receiver
  static String launch(String appId, int requestId) =>
      jsonEncode({'type': 'LAUNCH', 'appId': appId, 'requestId': requestId});

  static String stop(String sessionId, int requestId) =>
      jsonEncode({'type': 'STOP', 'sessionId': sessionId, 'requestId': requestId});

  static String getReceiverStatus(int requestId) =>
      jsonEncode({'type': 'GET_STATUS', 'requestId': requestId});

  /// Device volume on the platform receiver (0.0–1.0). The Jellyfin receiver
  /// stubs its protocol volume handlers, so this SDK-level command is how
  /// volume is actually set while casting (see CASTING.md §2).
  static String setVolume(double level, int requestId) => jsonEncode({
        'type': 'SET_VOLUME',
        'volume': {'level': level.clamp(0.0, 1.0)},
        'requestId': requestId,
      });

  static String setMuted(bool muted, int requestId) => jsonEncode({
        'type': 'SET_VOLUME',
        'volume': {'muted': muted},
        'requestId': requestId,
      });

  // media — used only on the default-receiver path (we own the stream URL).
  static String load({
    required String contentId,
    required String contentType,
    required int requestId,
    String streamType = 'BUFFERED',
    bool autoplay = true,
    Duration currentTime = Duration.zero,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? customData,
  }) =>
      jsonEncode({
        'type': 'LOAD',
        'autoplay': autoplay,
        'currentTime': currentTime.inMilliseconds / 1000.0,
        'media': {
          'contentId': contentId,
          'contentType': contentType,
          'streamType': streamType,
          if (metadata != null) 'metadata': metadata,
          if (customData != null) 'customData': customData,
        },
        'requestId': requestId,
      });

  static String mediaCommand(String type, int mediaSessionId, int requestId,
          [Map<String, dynamic>? extra]) =>
      jsonEncode({
        'type': type,
        'mediaSessionId': mediaSessionId,
        'requestId': requestId,
        if (extra != null) ...extra,
      });

  static String play(int mediaSessionId, int requestId) =>
      mediaCommand('PLAY', mediaSessionId, requestId);
  static String pause(int mediaSessionId, int requestId) =>
      mediaCommand('PAUSE', mediaSessionId, requestId);
  static String seek(int mediaSessionId, Duration to, int requestId) =>
      mediaCommand('SEEK', mediaSessionId, requestId,
          {'currentTime': to.inMilliseconds / 1000.0});
  static String getMediaStatus(int mediaSessionId, int requestId) =>
      mediaCommand('GET_STATUS', mediaSessionId, requestId);

  static String messageType(String json) {
    final decoded = jsonDecode(json);
    return decoded is Map && decoded['type'] is String ? decoded['type'] as String : '';
  }
}

/// One application entry inside a RECEIVER_STATUS.
class CastApplication {
  final String appId;
  final String? transportId;
  final String? sessionId;
  final String? displayName;
  final List<String> namespaces;

  const CastApplication({
    required this.appId,
    this.transportId,
    this.sessionId,
    this.displayName,
    this.namespaces = const [],
  });
}

/// Parsed RECEIVER_STATUS payload — the running applications and device volume.
class ReceiverStatus {
  final List<CastApplication> applications;
  final double? volumeLevel;
  final bool? muted;

  const ReceiverStatus({
    this.applications = const [],
    this.volumeLevel,
    this.muted,
  });

  /// The transport id to open a virtual connection to for [appId], or null if
  /// that app isn't (yet) running.
  String? transportFor(String appId) => applications
      .where((a) => a.appId == appId && a.transportId != null)
      .map((a) => a.transportId)
      .firstWhere((_) => true, orElse: () => null);

  static ReceiverStatus parse(String json) {
    final decoded = jsonDecode(json);
    final status = decoded is Map ? decoded['status'] : null;
    if (status is! Map) return const ReceiverStatus();

    final apps = <CastApplication>[];
    final rawApps = status['applications'];
    if (rawApps is List) {
      for (final a in rawApps) {
        if (a is! Map) continue;
        apps.add(CastApplication(
          appId: (a['appId'] ?? '').toString(),
          transportId: a['transportId'] as String?,
          sessionId: a['sessionId'] as String?,
          displayName: a['displayName'] as String?,
          namespaces: (a['namespaces'] is List)
              ? [
                  for (final n in a['namespaces'] as List)
                    if (n is Map && n['name'] is String) n['name'] as String
                ]
              : const [],
        ));
      }
    }

    double? level;
    bool? muted;
    final volume = status['volume'];
    if (volume is Map) {
      final l = volume['level'];
      if (l is num) level = l.toDouble();
      if (volume['muted'] is bool) muted = volume['muted'] as bool;
    }

    return ReceiverStatus(applications: apps, volumeLevel: level, muted: muted);
  }
}

/// Parsed MEDIA_STATUS payload (default-receiver path position/state).
class MediaStatus {
  final int? mediaSessionId;
  final String? playerState; // IDLE | BUFFERING | PLAYING | PAUSED
  final Duration? currentTime;

  const MediaStatus({this.mediaSessionId, this.playerState, this.currentTime});

  bool get isPlaying => playerState == 'PLAYING';

  static MediaStatus? parse(String json) {
    final decoded = jsonDecode(json);
    final list = decoded is Map ? decoded['status'] : null;
    if (list is! List || list.isEmpty) return null;
    final s = list.first;
    if (s is! Map) return null;
    final ct = s['currentTime'];
    return MediaStatus(
      mediaSessionId: s['mediaSessionId'] is num ? (s['mediaSessionId'] as num).toInt() : null,
      playerState: s['playerState'] as String?,
      currentTime: ct is num ? Duration(milliseconds: (ct * 1000).round()) : null,
    );
  }
}

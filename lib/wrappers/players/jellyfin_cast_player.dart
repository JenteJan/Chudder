import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_channel.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.jellyfin');

/// Jellyfin's Cast receiver communicates over this custom namespace.
const jellyfinCastNamespace = 'urn:x-cast:com.connectsdk';

/// The connection + item context the Jellyfin receiver needs to play. Mirrors
/// the message the jellyfin-web sender builds.
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
  });
}

/// A [BasePlayer] that drives the **Jellyfin Cast receiver** (app id `F007D354`)
/// over its custom protocol, the way the official Jellyfin web/Android apps do.
///
/// Unlike the default media receiver, this receiver fetches and plays the item
/// itself (doing its own PlaybackInfo/transcoding on the server), so we only
/// hand it credentials + the item — no media URL or client-side transcode.
class JellyfinCastPlayer extends BasePlayer implements RemotePlayer {
  JellyfinCastPlayer._(this.deviceName, this._context);

  @override
  final String deviceName;
  final JellyfinCastContext _context;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  final List<StreamSubscription> _subs = [];

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  /// Connects to [device] (launching app id F007D354, set at SDK init) and
  /// registers the Jellyfin message namespace.
  static Future<JellyfinCastPlayer> connect(
    GoogleCastDevice device,
    JellyfinCastContext context, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.friendlyName}"');
    final sessions = GoogleCastSessionManager.instance;

    final connected = Completer<void>();
    late final StreamSubscription sub;
    sub = sessions.currentSessionStream.listen((session) {
      if (session?.connectionState == GoogleCastConnectState.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    try {
      await sessions.startSessionWithDevice(device);
      if (sessions.connectionState != GoogleCastConnectState.connected) {
        await connected.future.timeout(timeout);
      }
    } finally {
      await sub.cancel();
    }

    await JellyfinCastChannel.instance.registerNamespace(jellyfinCastNamespace);
    _log.info('Jellyfin cast session connected to "${device.friendlyName}"');
    return JellyfinCastPlayer._(device.friendlyName, context);
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _subs.add(JellyfinCastChannel.instance.messages.listen(_onMessage));
    // Handshake — the receiver replies with its capabilities/state.
    await _send('Identify', {});
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // The receiver fetches the item itself; `url` is ignored.
    _log.info('PlayNow → "$deviceName" (item ${_context.itemStub['Id']}, start ${startPosition.inSeconds}s)');
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    await _send('PlayNow', {
      'items': [_context.itemStub],
      'startPositionTicks': startPosition.inMilliseconds * 10000,
      'startIndex': 0,
    });
  }

  @override
  Future<void> play() async => _send('Unpause', {});

  @override
  Future<void> pause() async => _send('Pause', {});

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async => _send('Stop', {});

  @override
  Future<void> seek(Duration position) async {
    await _send('Seek', {'position': position.inSeconds});
    lastState = lastState.update(position: position);
    _stateController.add(lastState);
  }

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    final index = model?.index ?? 0;
    await _send('SetAudioStreamIndex', {'index': index});
    return index;
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    final index = model?.index ?? -1;
    await _send('SetSubtitleStreamIndex', {'index': index});
    return index;
  }

  // The receiver/TV owns volume and playback rate.
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => _CastingPlaceholder(key: key, deviceName: deviceName);

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
    if (!_stateController.isClosed) await _stateController.close();
  }

  /// Builds the full message envelope (command + credentials) the receiver
  /// expects, and sends it as JSON on the Jellyfin namespace.
  Future<void> _send(String command, Map<String, dynamic> options) async {
    final message = {
      'command': command,
      'options': options,
      'userId': _context.userId,
      'deviceId': _context.deviceId,
      'accessToken': _context.accessToken,
      'serverAddress': _context.serverAddress,
      'serverId': _context.serverId,
      'serverVersion': _context.serverVersion,
      'receiverName': deviceName,
      if (_context.maxBitrate != null) 'maxBitrate': _context.maxBitrate,
    };
    try {
      await JellyfinCastChannel.instance.sendMessage(jellyfinCastNamespace, jsonEncode(message));
    } catch (error) {
      _log.warning('Failed to send $command: $error');
    }
  }

  void _onMessage(String raw) {
    _log.fine('Receiver message: $raw');
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;

      // The receiver reports playback state; map the fields we recognise.
      final isPaused = data['IsPaused'] ?? data['isPaused'];
      final positionTicks = data['PositionTicks'] ?? data['positionTicks'];
      final runtimeTicks = data['RunTimeTicks'] ?? data['runtimeTicks'];

      lastState = lastState.update(
        playing: isPaused is bool ? !isPaused : null,
        buffering: false,
        position: positionTicks is num ? Duration(microseconds: (positionTicks / 10).round()) : null,
        duration: runtimeTicks is num ? Duration(microseconds: (runtimeTicks / 10).round()) : null,
      );
      _stateController.add(lastState);
    } catch (_) {
      // Non-state messages (Identify replies, etc.) are ignored for now.
    }
  }
}

class _CastingPlaceholder extends StatelessWidget {
  const _CastingPlaceholder({super.key, required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'Casting to $deviceName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

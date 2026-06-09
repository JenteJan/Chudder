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

  // The receiver's web app registers its message listener a beat after the
  // session connects, so early messages are silently dropped. Retry PlayNow
  // until the receiver acknowledges (sends any message back), then stop.
  bool _acknowledged = false;
  Map<String, dynamic>? _playNowOptions;
  Timer? _playNowTimer;

  // The receiver only reports position every few seconds; tick locally in
  // between so the scrubber advances smoothly, correcting from each report.
  Timer? _positionTicker;

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
    _acknowledged = false;
    _playNowOptions = {
      'items': [_context.itemStub],
      'startPositionTicks': startPosition.inMilliseconds * 10000,
      'startIndex': 0,
    };
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);
    _startPlayNowAttempts();
  }

  /// Sends PlayNow, retrying until the receiver acknowledges (so the request
  /// isn't lost while the receiver's web app is still loading).
  void _startPlayNowAttempts() {
    _playNowTimer?.cancel();
    var attempts = 0;
    const maxAttempts = 8;

    Future<void> attempt() async {
      final options = _playNowOptions;
      if (_acknowledged || options == null) return;
      attempts++;
      _log.info('PlayNow → "$deviceName" (attempt $attempts, item ${_context.itemStub['Id']})');
      await _send('PlayNow', options);
    }

    attempt();
    _playNowTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_acknowledged || attempts >= maxAttempts) {
        timer.cancel();
        if (!_acknowledged) _log.warning('Receiver never acknowledged PlayNow after $attempts attempts');
        return;
      }
      attempt();
    });
  }

  @override
  Future<void> play() async {
    // Optimistically reflect the action; the receiver confirms via playstatechange.
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _syncPositionTicker(true);
    await _send('Unpause', {});
  }

  @override
  Future<void> pause() async {
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _syncPositionTicker(false);
    await _send('Pause', {});
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _playNowOptions = null;
    await _send('Stop', {});
  }

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
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
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
    if (!_acknowledged) {
      _acknowledged = true;
      _playNowTimer?.cancel();
      _log.info('Receiver acknowledged — playback handed off');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      // Messages are `{type, data:{PlayState:{...}, NowPlayingItem:{...}}}`,
      // where type ∈ {playbackstart, playstatechange, playbackprogress, ...}.
      final body = decoded['data'];
      if (body is! Map) return;
      final playState = body['PlayState'];
      final nowPlaying = body['NowPlayingItem'];

      bool? playing;
      Duration? position;
      if (playState is Map) {
        final isPaused = playState['IsPaused'];
        if (isPaused is bool) playing = !isPaused;
        final ticks = playState['PositionTicks'];
        if (ticks is num) position = Duration(microseconds: (ticks / 10).round());
      }
      Duration? duration;
      if (nowPlaying is Map) {
        final runtimeTicks = nowPlaying['RunTimeTicks'];
        if (runtimeTicks is num) duration = Duration(microseconds: (runtimeTicks / 10).round());
      }

      lastState = lastState.update(
        playing: playing,
        buffering: false,
        position: position,
        duration: duration,
      );
      _stateController.add(lastState);
      // Resync the local ticker to the receiver's authoritative position/state.
      _syncPositionTicker(playing ?? lastState.playing);
      _log.fine('Receiver ${decoded['type']}: pos=${position?.inSeconds}s playing=$playing');
    } catch (error) {
      _log.fine('Could not parse receiver message: $error');
    }
  }

  /// Runs a 1s local clock that advances [lastState] position while playing, so
  /// the scrubber moves smoothly between the receiver's periodic reports. Each
  /// report calls this to correct drift; pausing/stopping cancels it.
  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      lastState = lastState.update(position: lastState.position + const Duration(seconds: 1));
      _stateController.add(lastState);
    });
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

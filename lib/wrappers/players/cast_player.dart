import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/local_media_proxy.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.chromecast');

/// TEMPORARY isolation switch. When true, casting loads a known-good public HLS
/// stream instead of the Jellyfin transcode — proves the device + Cast plumbing
/// independently of our server/proxy. Set back to false for real playback.
const _castDiagnosticMode = false;
const _castDiagnosticUrl =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8';

/// A [BasePlayer] that drives a Chromecast through the **default Google Cast
/// media receiver** (`CC1AD845`) via `flutter_chrome_cast`. Unlike the Jellyfin
/// custom receiver, this runs on every Chromecast generation — including the
/// 2013 first-gen dongle — because the receiver is a tiny native player rather
/// than a modern JS web app.
///
/// The receiver can't decode most direct-play containers, and old hardware can't
/// validate modern TLS certs, so we hand it a **progressive H.264/AAC MP4**
/// transcode re-served over plain HTTP on the LAN by [LocalMediaProxy] (the
/// phone does the HTTPS fetch). Android only.
class CastPlayer extends BasePlayer implements RemotePlayer {
  CastPlayer._(this.deviceName, this._streamUrl, this._useProxy);

  @override
  final String deviceName;

  /// The cast-specific Jellyfin transcode URL (HTTPS). Replaces the app's normal
  /// stream URL, which the receiver typically can't play.
  final String _streamUrl;

  /// Whether to re-serve [_streamUrl] through the on-device proxy (recommended:
  /// bypasses the receiver's old TLS stack and any non-LAN-reachable server).
  final bool _useProxy;

  final LocalMediaProxy _proxy = LocalMediaProxy();
  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  final List<StreamSubscription> _subs = [];
  Timer? _loadWatchdog;
  String? _lastLoggedState;

  GoogleCastRemoteMediaClientPlatformInterface get _media => GoogleCastRemoteMediaClient.instance;

  /// Starts a session with [device] and waits until it reports connected.
  static Future<CastPlayer> connect(
    GoogleCastDevice device, {
    required String streamUrl,
    bool useProxy = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Chromecast session with "${device.friendlyName}"');
    final sessions = GoogleCastSessionManager.instance;

    final connected = Completer<void>();
    late final StreamSubscription sub;
    sub = sessions.currentSessionStream.listen((session) {
      final state = session?.connectionState;
      _log.fine('Session state: ${state?.name}');
      if (state == GoogleCastConnectState.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    try {
      await sessions.startSessionWithDevice(device);
      if (sessions.connectionState != GoogleCastConnectState.connected) {
        await connected.future.timeout(timeout);
      }
      _log.info('Chromecast session connected to "${device.friendlyName}"');
    } on TimeoutException {
      _log.warning('Chromecast session to "${device.friendlyName}" timed out after ${timeout.inSeconds}s');
      rethrow;
    } finally {
      await sub.cancel();
    }

    return CastPlayer._(device.friendlyName, streamUrl, useProxy);
  }

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _subs.add(_media.mediaStatusStream.listen(_onMediaStatus));
    _subs.add(_media.playerPositionStream.listen((position) {
      lastState = lastState.update(position: position);
      _stateController.add(lastState);
    }));
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // We ignore the app's [url] and play the cast-specific transcode instead.
    var mediaUrl = _streamUrl;

    if (_castDiagnosticMode) {
      _log.warning('CAST DIAGNOSTIC MODE — loading a known-good public HLS stream. '
          'If THIS plays, the device + Cast plumbing work and the issue is the server/proxy stream.');
      mediaUrl = _castDiagnosticUrl;
    } else if (_useProxy) {
      final served = await _proxy.start(_streamUrl);
      if (served != null) {
        mediaUrl = served;
        _log.info('Casting via on-device proxy (dongle fetches plain HTTP from the phone)');
      } else {
        _log.warning('Proxy unavailable — falling back to the direct (HTTPS) stream URL');
      }
    }

    final contentType = _contentTypeFor(mediaUrl);
    final isHls = contentType.contains('mpegurl');
    _log.info('LOAD on "$deviceName" (start ${startPosition.inSeconds}s, type $contentType, '
        '${_useProxy ? 'proxied' : 'direct'})');
    _log.fine('Stream URL: $mediaUrl');
    _lastLoggedState = null;
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    final media = GoogleCastMediaInformation(
      contentId: mediaUrl,
      streamType: CastMediaStreamType.buffered,
      contentType: contentType,
      contentUrl: Uri.tryParse(mediaUrl),
      hlsVideoSegmentFormat: isHls ? HlsVideoSegmentFormat.mpeg2Ts : null,
    );

    // Start at 0: a fresh progressive transcode only has data from the start, so
    // seeking into it immediately stalls the receiver. Resume-on-cast needs the
    // offset baked into the transcode URL — a follow-up.
    await _media.loadMedia(media, autoPlay: play, playPosition: Duration.zero);

    // Casting spins up a server-side transcode; first-segment latency can be
    // 15-30s, so give it room before declaring failure.
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 45), () {
      if (_lastLoggedState == null || _lastLoggedState == 'idle' || _lastLoggedState == 'loading') {
        _log.warning('"$deviceName" never started playback (stuck ${_lastLoggedState ?? 'idle'}). '
            'If it is stuck LOADING, the receiver could not fetch the stream.');
        lastState = lastState.update(buffering: false, playing: false);
        _stateController.add(lastState);
      }
    });
  }

  @override
  Future<void> play() async => _media.play();

  @override
  Future<void> pause() async => _media.pause();

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _loadWatchdog?.cancel();
    await _media.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _media.seek(GoogleCastMediaSeekOption(position: position));
    lastState = lastState.update(position: position);
    _stateController.add(lastState);
  }

  @override
  Future<void> setSpeed(double speed) async => _media.setPlaybackRate(speed);

  // The receiver/TV owns its own volume; leave as a no-op for v1.
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => _CastingPlaceholder(key: key, deviceName: deviceName);

  @override
  Future<void> dispose() async {
    _loadWatchdog?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
    await _proxy.stop();
    if (!_stateController.isClosed) await _stateController.close();
  }

  void _onMediaStatus(GoggleCastMediaStatus? status) {
    if (status == null) return;
    final state = status.playerState;

    if (state.name != _lastLoggedState) {
      _lastLoggedState = state.name;
      _log.info('Receiver state: ${state.name}${status.idleReason != null ? ' (${status.idleReason?.name})' : ''}');
    }
    if (state == CastMediaPlayerState.playing || state == CastMediaPlayerState.buffering) {
      _loadWatchdog?.cancel();
    }

    lastState = lastState.update(
      playing: state == CastMediaPlayerState.playing,
      buffering: state == CastMediaPlayerState.buffering || state == CastMediaPlayerState.loading,
      duration: status.mediaInformation?.duration,
    );
    _stateController.add(lastState);
  }

  /// Best-effort content type so the receiver picks the right pipeline.
  static String _contentTypeFor(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    final container = Uri.tryParse(url)?.queryParameters['container']?.toLowerCase();
    return switch (container) {
      'mp4' || 'm4v' => 'video/mp4',
      'webm' => 'video/webm',
      'mkv' => 'video/x-matroska',
      'ts' => 'video/mp2t',
      _ => lower.contains('.ts') ? 'video/mp2t' : 'video/mp4',
    };
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.chromecast');

/// TEMPORARY isolation test. When true, casting loads a known-good public HLS
/// stream instead of the Jellyfin transcode. If it plays, the Chromecast device
/// and our integration work, and the stall is server/transcode-side (→ a custom
/// receiver is worth building). If it also stalls, the issue is the device/network.
/// Set back to false once diagnosed.
const _castDiagnosticMode = false;
const _castDiagnosticUrl =
    'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8';

/// A [BasePlayer] that drives a Chromecast receiver through the **native Google
/// Cast SDK** (via `flutter_chrome_cast`). This is the same sender library the
/// official Cast apps use, so it satisfies the receiver handshake that a
/// reverse-engineered protocol implementation does not.
///
/// Playback happens on the remote device; this class issues commands and mirrors
/// the receiver's media status into a [PlayerState] stream. Android only for now.
class CastPlayer extends BasePlayer implements RemotePlayer {
  CastPlayer._(this.deviceName, this.mediaUrlOverride);

  @override
  final String deviceName;

  /// A cast-compatible (transcoded HLS/H.264) URL to send instead of the app's
  /// stream URL — the receiver can't decode many direct-play containers/codecs.
  final String? mediaUrlOverride;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  final List<StreamSubscription> _subs = [];
  Timer? _loadWatchdog;
  String? _lastLoggedState;

  GoogleCastRemoteMediaClientPlatformInterface get _media => GoogleCastRemoteMediaClient.instance;

  /// Starts a session with [device] and waits until it reports connected.
  static Future<CastPlayer> connect(
    GoogleCastDevice device, {
    String? mediaUrlOverride,
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

    return CastPlayer._(device.friendlyName, mediaUrlOverride);
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
    var mediaUrl = mediaUrlOverride ?? url;
    if (_castDiagnosticMode) {
      _log.warning('CAST DIAGNOSTIC MODE — loading a known-good public HLS stream instead of Jellyfin media. '
          'If THIS plays, the device + integration work and the issue is your server/transcode.');
      mediaUrl = _castDiagnosticUrl;
    }
    final contentType = _contentTypeFor(mediaUrl);
    final isHls = contentType.contains('mpegurl');
    _log.info('LOAD on "$deviceName" (start ${startPosition.inSeconds}s, type $contentType'
        '${mediaUrlOverride != null ? ', transcoded' : ''})');
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

    // Start at 0: seeking into a freshly-started on-demand transcode (Jellyfin
    // has only produced segment 0) stalls the receiver in LOADING. Resume-on-cast
    // needs the start position baked into the transcode URL — a follow-up.
    await _media.loadMedia(media, autoPlay: play, playPosition: Duration.zero);

    // Casting spins up a fresh server-side transcode; first-segment latency can
    // be 15-30s, so give it room before declaring failure.
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 45), () {
      if (_lastLoggedState == null || _lastLoggedState == 'idle' || _lastLoggedState == 'loading') {
        _log.warning('"$deviceName" never started playback (stuck ${_lastLoggedState ?? 'idle'}).');
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
      _ => 'video/mp4',
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

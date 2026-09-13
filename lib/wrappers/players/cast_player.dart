import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/screens/video_player/components/casting_placeholder.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/local_media_proxy.dart';
import 'package:chudder/wrappers/players/player_states.dart';
import 'package:chudder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.chromecast');

/// Builds the cast-specific Jellyfin transcode URL for the *current* item with
/// the active track/quality selection and resume offset baked in. Mirrors the
/// DLNA builder so track/quality switches and resume reach the default receiver.
typedef ChromecastStreamBuilder = Future<String?> Function({
  int? audioStreamIndex,
  int? subtitleStreamIndex,
  int? maxBitrate,
  Duration? startPosition,
});

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
  CastPlayer._(this.deviceName, this._streamBuilder, this._useProxy, this._image);

  @override
  final String deviceName;

  /// Item backdrop/poster shown behind the casting placeholder.
  final ImageProvider? _image;

  // The default receiver just pulls a stream; the phone stays the session
  // owner and must keep reporting progress for watched-state to update.
  @override
  bool get reportsOwnProgress => false;

  @override
  int? get remoteVolumeLevel => null;

  /// Builds the cast-specific Jellyfin transcode URL (HTTPS) for the *current*
  /// item, on demand at load time. Replaces the app's normal stream URL, which
  /// the receiver typically can't play. Lazy (not baked at connect) so
  /// connecting before playback and switching items while connected both work —
  /// uniform with the DLNA/AirPlay/Jellyfin paths.
  final ChromecastStreamBuilder _streamBuilder;

  // Track/quality overrides; changing one rebuilds the transcode and reloads
  // (the default receiver can't switch embedded tracks itself). Null = source
  // defaults.
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;
  int? _maxBitrate;

  /// Media position the current transcode begins at. The receiver reports
  /// positions relative to the stream start, so this is added back to surface
  /// the true item position (resume, mid-item track/quality switches).
  Duration _streamStartOffset = Duration.zero;

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
    required ChromecastStreamBuilder streamBuilder,
    ImageProvider? image,
    bool useProxy = true,
    int? initialAudioStreamIndex,
    int? initialSubtitleStreamIndex,
    int? initialMaxBitrate,
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

    return CastPlayer._(device.friendlyName, streamBuilder, useProxy, image)
      .._audioStreamIndex = initialAudioStreamIndex
      .._subtitleStreamIndex = initialSubtitleStreamIndex
      .._maxBitrate = initialMaxBitrate;
  }

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _subs.add(_media.mediaStatusStream.listen(_onMediaStatus));
    _subs.add(_media.playerPositionStream.listen((position) {
      // The receiver reports relative to the transcode's start; add the offset
      // back so the timeline shows the true item position.
      lastState = lastState.update(position: _streamStartOffset + position);
      _stateController.add(lastState);
    }));
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    _lastLoggedState = null;
    // Clear the previous item's completion/error BEFORE the (slow) stream
    // resolution below: receiver status events can re-emit during the awaits
    // and must not carry a stale completed/error flag into the new item.
    lastState = lastState.update(
        buffering: true, playing: play, position: startPosition, completed: false, error: false);
    _stateController.add(lastState);

    // Ignore the app's [url]; resolve the cast-specific transcode for the
    // current item now (lazy — supports connect-before-play and item switching),
    // with the active track/quality selection and resume offset baked in.
    final resolved = await _streamBuilder(
      audioStreamIndex: _audioStreamIndex,
      subtitleStreamIndex: _subtitleStreamIndex,
      maxBitrate: _maxBitrate,
      startPosition: startPosition,
    );
    if (resolved == null) {
      _log.warning('No Chromecast stream available for the current item; nothing to load.');
      lastState = lastState.update(buffering: false, playing: false, error: true);
      _stateController.add(lastState);
      return;
    }
    var mediaUrl = resolved;

    if (_castDiagnosticMode) {
      _log.warning('CAST DIAGNOSTIC MODE — loading a known-good public HLS stream. '
          'If THIS plays, the device + Cast plumbing work and the issue is the server/proxy stream.');
      mediaUrl = _castDiagnosticUrl;
    } else if (_useProxy) {
      final served = await _proxy.start(resolved);
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
    final media = GoogleCastMediaInformation(
      contentId: mediaUrl,
      streamType: CastMediaStreamType.buffered,
      contentType: contentType,
      contentUrl: Uri.tryParse(mediaUrl),
      hlsVideoSegmentFormat: isHls ? HlsVideoSegmentFormat.mpeg2Ts : null,
    );

    // The transcode already begins at [startPosition] (baked into the URL), so
    // the receiver plays from its start — load at 0 and surface the true
    // position by adding the offset back (see the position stream above).
    _streamStartOffset = startPosition;
    await _media.loadMedia(media, autoPlay: play, playPosition: Duration.zero);

    // Casting spins up a server-side transcode; first-segment latency can be
    // 15-30s, so give it room before declaring failure.
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 45), () {
      if (_lastLoggedState == null || _lastLoggedState == 'idle' || _lastLoggedState == 'loading') {
        _log.warning('"$deviceName" never started playback (stuck ${_lastLoggedState ?? 'idle'}). '
            'If it is stuck LOADING, the receiver could not fetch the stream.');
        lastState = lastState.update(buffering: false, playing: false, error: true);
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
    final target = position < Duration.zero ? Duration.zero : position;
    // In-place seeks only work inside data the live transcode has already
    // produced; seeking past it stalls the receiver on a spinner. The produced
    // region isn't observable, so allow only a short hop past the current
    // position (the server transcodes ahead of playback) and rebuild the
    // transcode from the target for anything farther — same as a backward
    // seek before the stream's start offset.
    final nearCurrent =
        target >= _streamStartOffset && target <= lastState.position + const Duration(seconds: 30);
    if (nearCurrent) {
      lastState = lastState.update(position: target);
      _stateController.add(lastState);
      await _media.seek(GoogleCastMediaSeekOption(position: target - _streamStartOffset));
    } else {
      await loadVideo('', lastState.playing, startPosition: target);
    }
  }

  @override
  Future<void> setSpeed(double speed) async => _media.setPlaybackRate(speed);

  // The receiver/TV owns its own volume; leave as a no-op for v1.
  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> loop(bool loop) async {}

  // Switching a track rebuilds the transcode with the new track baked in (the
  // default receiver can't switch embedded tracks itself) and reloads at the
  // current position — same model as the DLNA player.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _audioStreamIndex ?? -1;
    _audioStreamIndex = model.index;
    await _reload();
    return model.index;
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _subtitleStreamIndex ?? -1;
    _subtitleStreamIndex = model.index;
    await _reload();
    return model.index;
  }

  /// Points the per-item track overrides at the item about to be loaded —
  /// called right before [loadVideo] when the app switches items mid-cast, so
  /// the previous item's stream indexes (which may not exist, or mean a
  /// different track, on the new media source) aren't baked into its stream.
  void syncTrackSelection({int? audioStreamIndex, int? subtitleStreamIndex}) {
    _audioStreamIndex = audioStreamIndex;
    _subtitleStreamIndex = subtitleStreamIndex;
  }

  /// Applies a quality cap from the in-player quality control. A null/very-high
  /// cap keeps the default cast bitrate; a real cap forces a lower transcode.
  Future<void> setMaxBitrate(int? maxBitrate) async {
    if (_maxBitrate == maxBitrate) return;
    _maxBitrate = maxBitrate;
    await _reload();
  }

  /// Rebuilds the transcode (current track/quality selection) and resumes at the
  /// current position.
  Future<void> _reload() async => loadVideo('', lastState.playing, startPosition: lastState.position);

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) => CastingPlaceholder(key: key, deviceName: deviceName, image: _image);

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

    // The receiver finished the item naturally (not a user stop/seek): signal
    // completion so the app can roll to the next episode. The stopped report
    // sent during the advance carries the end position; the server marks the
    // item watched from that.
    final finished = state == CastMediaPlayerState.idle && status.idleReason == GoogleCastMediaIdleReason.finished;

    // A transcode begun at an offset reports its duration as the *remaining*
    // length, so add the offset back to surface the true item duration.
    final reportedDuration = status.mediaInformation?.duration;
    final trueDuration = reportedDuration == null ? null : _streamStartOffset + reportedDuration;
    lastState = lastState.update(
      playing: state == CastMediaPlayerState.playing,
      buffering: state == CastMediaPlayerState.buffering || state == CastMediaPlayerState.loading,
      duration: trueDuration,
      completed: finished ? true : null,
      // The stream truly ended; snap to the real end so the stopped report
      // lands past the server's watched threshold.
      position: (finished && trueDuration != null) ? trueDuration : null,
      // The receiver is demonstrably working — clear a load-watchdog false
      // positive (a slow first transcode segment) instead of showing the error
      // overlay for the rest of the session.
      error: (state == CastMediaPlayerState.playing || state == CastMediaPlayerState.buffering) ? false : null,
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

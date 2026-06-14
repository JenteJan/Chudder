import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';
import 'package:video_player/video_player.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.airplay');

/// A [BasePlayer] that plays through `AVPlayer` (via the `video_player` plugin)
/// so iOS/macOS can route **video** out over AirPlay — the one API that does
/// AirPlay video. mpv/media-kit cannot AirPlay, so this is swapped in for the
/// AirPlay session exactly like the Chromecast/DLNA remote players.
///
/// Crucially, playback is *local* here: the phone's `AVPlayer` fetches the HLS
/// transcode and decodes/presents it; when the user selects an AirPlay route
/// (system picker / Control Center), `AVPlayer`'s external playback hands video
/// to the Apple TV automatically. So the device does the fetch (like DLNA's
/// proxy model) and the phone stays the Jellyfin session owner.
///
/// LIMITATIONS (see docs/CASTING.md):
/// - Needs a route selected by the user via the system AirPlay UI — there's no
///   public API to open it programmatically, so this player is started first
///   (swapping out mpv) and the route is chosen separately.
/// - Audio/subtitle *track switching* mid-play requires a fresh transcode URL
///   and is not wired (v1). The track baked into the transcode is what plays.
/// - No screenshots; playback rate works via AVPlayer but is ignored by some
///   AirPlay receivers.
class AirPlayVideoPlayer extends BasePlayer implements RemotePlayer {
  AirPlayVideoPlayer._(this._streamBuilder);

  /// Builds the AirPlay-specific HLS transcode URL (with [airplayProfile]) for
  /// the *current* item, on demand at load time. We ignore the app's mpv URL and
  /// always play this. Lazy (not baked at connect) so connect-before-play and
  /// item switching work — uniform with the Chromecast/DLNA paths.
  final Future<String?> Function() _streamBuilder;

  VideoPlayerController? _controller;
  final StreamController<PlayerState> _stateController = StreamController.broadcast();

  @override
  String get deviceName => 'AirPlay';

  // The phone's AVPlayer pulls the transcode; Jellyfin sees a stream being
  // fetched, not a separate receiver session, so the phone keeps reporting
  // progress (watched-state) — same as DLNA.
  @override
  bool get reportsOwnProgress => false;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  static Future<AirPlayVideoPlayer> connect({required Future<String?> Function() streamBuilder}) async {
    _log.info('Preparing AirPlay (AVPlayer) session');
    return AirPlayVideoPlayer._(streamBuilder);
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    _log.info('loadVideo via AVPlayer (start ${startPosition.inSeconds}s, play=$play)');
    // Resolve the current item's HLS transcode now (lazy — supports
    // connect-before-play and switching items while connected).
    final streamUrl = await _streamBuilder();
    if (streamUrl == null) {
      _log.warning('No AirPlay stream available for the current item; nothing to load.');
      lastState = lastState.update(buffering: false, playing: false);
      _stateController.add(lastState);
      return;
    }
    await _disposeController();
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    final controller = VideoPlayerController.networkUrl(Uri.parse(streamUrl));
    _controller = controller;
    controller.addListener(_onTick);
    try {
      await controller.initialize();
    } catch (error, stack) {
      _log.warning('AVPlayer failed to initialize the AirPlay stream', error, stack);
      await _disposeController();
      rethrow;
    }

    if (startPosition > Duration.zero) await controller.seekTo(startPosition);
    if (play) await controller.play();

    lastState = lastState.update(
      buffering: false,
      playing: controller.value.isPlaying,
      position: controller.value.position,
      duration: controller.value.duration,
    );
    _stateController.add(lastState);
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    lastState = lastState.update(
      playing: value.isPlaying,
      buffering: value.isBuffering,
      position: value.position,
      duration: value.duration,
      completed: value.duration > Duration.zero && value.position >= value.duration,
    );
    _stateController.add(lastState);
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  // BasePlayer volume is a 0–100 scale (see PlayerState); AVPlayer wants 0–1.
  @override
  Future<void> setVolume(double volume) async => _controller?.setVolume((volume / 100).clamp(0.0, 1.0));

  @override
  Future<void> setSpeed(double speed) async => _controller?.setPlaybackSpeed(speed);

  @override
  Future<void> loop(bool loop) async => _controller?.setLooping(loop);

  @override
  Future<void> stop() async {
    await _controller?.pause();
    await _controller?.seekTo(Duration.zero);
  }

  // Switching tracks needs a new transcode URL (not wired for AirPlay in v1) —
  // report the requested index without re-negotiating, mirroring DlnaPlayer.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _AirPlayPlaceholder(key: key);
    }
    final aspect = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    // While AirPlaying, AVPlayer shows nothing here (video is on the TV); when
    // a route isn't active yet it plays locally. Either way, present the player.
    return Container(
      key: key,
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(aspectRatio: aspect, child: VideoPlayer(controller)),
    );
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onTick);
      await controller.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await _disposeController();
    if (!_stateController.isClosed) await _stateController.close();
  }
}

class _AirPlayPlaceholder extends StatelessWidget {
  const _AirPlayPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.airplay, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'Preparing AirPlay…',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

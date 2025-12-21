import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/screens/video_player/video_player.dart' as video_screen;
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';

/// Tizen-specific video player implementation using video_player_tizen
/// This uses the standard video_player API which video_player_tizen extends
class TizenPlayer extends BasePlayer {
  VideoPlayerController? _controller;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    dispose();
  }

  @override
  Future<void> dispose() async {
    _controller?.removeListener(_onStateChanged);
    _controller?.dispose();
    _controller = null;
  }

  @override
  Future<void> loadVideo(String url, bool play) async {
    if (_controller != null) {
      _controller?.removeListener(_onStateChanged);
      _controller?.dispose();
    }

    final validUrl = isValidUrl(url);
    if (validUrl != null) {
      _controller = VideoPlayerController.networkUrl(validUrl);
    } else {
      // Tizen doesn't support file playback the same way
      // For now, just use network URL
      _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    }

    await _controller?.initialize();
    _controller?.addListener(_onStateChanged);

    if (play) {
      await _controller?.play();
    }

    return setState(lastState.update(
      buffering: true,
    ));
  }

  void _onStateChanged() {
    updateState();
  }

  void setState(PlayerState state) {
    lastState = state;
    _stateController.add(state);
  }

  void updateState() {
    setState(lastState.update(
      playing: _controller?.value.isPlaying ?? false,
      completed: _controller?.value.isCompleted ?? false,
      position: _controller?.value.position ?? Duration.zero,
      duration: _controller?.value.duration ?? Duration.zero,
      volume: (_controller?.value.volume ?? 1.0) * 100,
      rate: _controller?.value.playbackSpeed ?? 1.0,
      buffering: _controller?.value.isBuffering ?? true,
      buffer: _calculateBufferedDuration(_controller?.value),
    ));
  }

  Duration _calculateBufferedDuration(VideoPlayerValue? value) {
    if (value == null) return Duration.zero;
    if (value.buffered.isEmpty) {
      return Duration.zero;
    }

    return value.buffered.fold(value.position, (total, range) {
      return (total + (range.end - range.start));
    });
  }

  @override
  Future<void> open(BuildContext context) async => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (context) => const video_screen.VideoPlayer(),
        ),
      );

  @override
  Future<void> pause() async {
    try {
      await _controller?.pause();
    } catch (e) {
      debugPrint('TizenPlayer pause error: $e');
    }
  }

  @override
  Future<void> play() async {
    try {
      await _controller?.play();
    } catch (e) {
      debugPrint('TizenPlayer play error: $e');
    }
  }

  @override
  Future<void> playOrPause() async {
    try {
      lastState.playing ? await _controller?.pause() : await _controller?.play();
    } catch (e) {
      debugPrint('TizenPlayer playOrPause error: $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _controller?.seekTo(position);
    } catch (e) {
      debugPrint('TizenPlayer seek error: $e');
    }
  }

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    // Tizen video_player may support audio track selection via platform channel
    // For now, return the default track
    final wantedAudioStream = model ?? playbackModel.defaultAudioStream;
    return wantedAudioStream?.index ?? -1;
  }

  @override
  Future<void> setSpeed(double speed) async => _controller?.setPlaybackSpeed(speed);

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    // Tizen video_player may support subtitle selection via platform channel
    // For now, return the default track
    final wantedSubtitle = model ?? playbackModel.defaultSubStream;
    return wantedSubtitle?.index ?? -1;
  }

  @override
  Future<void> stop() async {
    try {
      await _controller?.pause();
      await _controller?.seekTo(Duration.zero);
    } catch (e) {
      debugPrint('TizenPlayer stop error: $e');
    }
  }

  @override
  Widget? videoWidget(
    Key key,
    BoxFit fit,
  ) =>
      _controller == null || !(_controller!.value.isInitialized)
          ? null
          : Container(
              key: key,
              color: Colors.transparent,
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: [
                    FittedBox(
                      fit: fit,
                      alignment: Alignment.center,
                      child: ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: _controller!,
                        builder: (context, value, child) {
                          final aspectRatio = value.isInitialized ? value.aspectRatio : 16 / 9;
                          return SizedBox(
                            width: constraints.maxWidth,
                            child: AspectRatio(
                              aspectRatio: aspectRatio,
                              child: VideoPlayer(_controller!),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) {
    // Tizen handles subtitles natively through the player
    return null;
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _controller?.setVolume(volume / 100);
    } catch (e) {
      debugPrint('TizenPlayer setVolume error: $e');
    }
  }

  @override
  Future<void> loop(bool loop) async {
    try {
      await _controller?.setLooping(loop);
    } catch (e) {
      debugPrint('TizenPlayer loop error: $e');
    }
  }
}



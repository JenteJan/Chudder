import 'dart:async';
import 'dart:io';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart' show PlaybackChangeSource, SyncPlayCommandType;
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final isVideoPlayerRouteOpenProvider = StateProvider<bool>((ref) => false);

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  videoPlayer.init();
  return videoPlayer;
});

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  /// Flag to indicate if the current action is initiated by SyncPlay
  bool _syncPlayAction = false;

  /// Cooldown period after SyncPlay command during which we don't auto-report ready
  static const _syncPlayCooldown = Duration(milliseconds: 500);

  /// Check if SyncPlay is active
  bool get _isSyncPlayActive => ref.read(isSyncPlayActiveProvider);

  /// Whether player is reloading/buffering from SyncPlay perspective.
  bool get _isReloading => ref.read(syncPlayProvider.select((s) => s.correctionState.playerIsBuffering));

  /// Check if we're in the SyncPlay cooldown period
  bool get _inSyncPlayCooldown {
    final lastCommandTime = ref.read(syncPlayProvider.select((s) => s.lastCommandTime));
    if (lastCommandTime == null) {
      return false;
    }
    return DateTime.now().toUtc().difference(lastCommandTime) < _syncPlayCooldown;
  }

  Future<void> init() async {
    await state.dispose();
    await state.init();

    for (final s in subscriptions) {
      s.cancel();
    }

    final subscription = state.stateStream?.listen((value) {
      // Infer SyncPlay user actions from native player state stream (reviewer request).
      if (value.changeSource == PlaybackChangeSource.user) {
        final prev = playbackState;
        if (value.playing != prev.playing) {
          if (value.playing) {
            userPlay();
          } else {
            userPause();
          }
        } else if ((value.position - prev.position).inSeconds.abs() > 2) {
          userSeek(value.position);
        }
      }
      updateBuffering(value.buffering);
      updateBuffer(value.buffer);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
    });

    if (subscription != null) {
      subscriptions.add(subscription);
    }

    // Register player callbacks with SyncPlay
    _registerSyncPlayCallbacks();

    // Listen to SyncPlay state changes for native player overlay
    _setupSyncPlayStateListener();
  }

  /// Set up listener to forward SyncPlay command state to native player
  void _setupSyncPlayStateListener() {
    ref.listen<SyncPlayState>(
      syncPlayProvider,
      (previous, next) {
        // Only forward to native player if it's active
        if (state.isNativePlayerActive) {
          // Check if the relevant state changed
          if (previous?.isProcessingCommand != next.isProcessingCommand ||
              previous?.processingCommandType != next.processingCommandType) {
            state.updateSyncPlayCommandState(
              next.isProcessingCommand,
              _toSyncPlayCommandType(next.processingCommandType),
            );
          }
        }
      },
    );
  }

  SyncPlayCommandType _toSyncPlayCommandType(String? commandType) {
    return switch (commandType) {
      'Pause' => SyncPlayCommandType.pause,
      'Unpause' => SyncPlayCommandType.unpause,
      'Seek' => SyncPlayCommandType.seek,
      'Stop' => SyncPlayCommandType.stop,
      _ => SyncPlayCommandType.none,
    };
  }

  /// Manually set the reloading state (e.g. before fetching new PlaybackInfo)
  void setReloading(
    bool value, {
    bool reportToSyncPlay = true,
  }) {
    ref.read(syncPlayProvider.notifier).setPlayerBufferingState(value);
    if (value && _isSyncPlayActive && reportToSyncPlay) {
      ref.read(syncPlayProvider.notifier).reportBuffering();
    }
  }

  /// Register player callbacks with SyncPlay controller
  void _registerSyncPlayCallbacks() {
    ref.read(syncPlayProvider.notifier).registerPlayer(
          onPlay: () async {
            _syncPlayAction = true;
            ref.read(syncPlayProvider.notifier).markCommandExecuted();
            await state.play();
            _syncPlayAction = false;
          },
          onPause: () async {
            _syncPlayAction = true;
            ref.read(syncPlayProvider.notifier).markCommandExecuted();
            await state.pause();
            _syncPlayAction = false;
          },
          onSeek: (positionTicks) async {
            _syncPlayAction = true;
            ref.read(syncPlayProvider.notifier).markCommandExecuted();
            final position = Duration(microseconds: positionTicks ~/ 10);
            await state.seek(position);
            _syncPlayAction = false;
          },
          onSeekRequested: (positionTicks) async {
            // Another user requested a seek. Report buffering to SyncPlay
            // without forcing local buffering state, otherwise the command
            // handler can get stuck waiting and suppress Ready/Unpause.
            ref.read(syncPlayProvider.notifier).reportBuffering();
          },
          onStop: () async {
            _syncPlayAction = true;
            ref.read(syncPlayProvider.notifier).markCommandExecuted();
            await state.stop();
            ref.read(syncPlayProvider.notifier).resetCorrectionState(
                  reason: 'stop_command',
                );
            _syncPlayAction = false;
          },
          onSetSpeed: (speed) async {
            await state.setSpeed(speed);
          },
          getPositionTicks: () {
            final position = playbackState.position;
            return secondsToTicks(position.inMilliseconds / 1000);
          },
          isPlaying: () => playbackState.playing,
          isBuffering: () => _isReloading || playbackState.buffering,
          hasPlaybackRate: () => !state.isNativePlayerActive,
        );
  }

  Future<void> updateBuffering(bool event) async {
    final oldState = playbackState;
    if (oldState.buffering == event) {
      return;
    }

    mediaState.update((state) => state.copyWith(buffering: event));
    if (_isSyncPlayActive) {
      ref.read(syncPlayProvider.notifier).setPlayerBufferingState(event);
    }

    // Report buffering state to SyncPlay if active
    // Skip if we're in the cooldown period after a SyncPlay command to prevent feedback loops
    // Also skip if we are currently reloading (we'll report manually when done)
    if (_isSyncPlayActive && !_syncPlayAction && !_inSyncPlayCooldown && !_isReloading) {
      if (event) {
        // Started buffering
        ref.read(syncPlayProvider.notifier).reportBuffering();
      } else {
        // Finished buffering - ready
        ref.read(syncPlayProvider.notifier).reportReady(isPlaying: playbackState.playing);
      }
    }
  }

  Future<void> updateBuffer(Duration buffer) async {
    mediaState.update(
      (state) => (state.buffer - buffer).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              buffer: buffer,
            ),
    );
  }

  Future<void> updateDuration(Duration duration) async {
    mediaState.update((state) {
      return (state.duration - duration).inSeconds.abs() < 1
          ? state
          : state.copyWith(
              duration: duration,
            );
    });
  }

  Future<void> updatePlaying(bool event) async {
    final currentState = playbackState;
    if (!state.hasPlayer || currentState.playing == event) return;
    if (currentState.state == VideoPlayerState.disposed) return;
    mediaState.update(
      (state) => state.copyWith(playing: event),
    );
    ref.read(playBackModel)?.updatePlaybackPosition(currentState.position, currentState.playing, ref);
  }

  Future<void> updatePosition(Duration event) async {
    if (!state.hasPlayer) {
      return;
    }
    if (playbackState.playing == false) {
      return;
    }
    final currentState = playbackState;
    if (currentState.state == VideoPlayerState.disposed) return;
    final currentPosition = currentState.position;

    if ((currentPosition - event).inSeconds.abs() < 1) {
      return;
    }

    final position = event;

    final lastPosition = currentState.lastPosition;
    final diff = (position.inMilliseconds - lastPosition.inMilliseconds).abs();

    if (diff > const Duration(seconds: 10).inMilliseconds) {
      mediaState.update((value) => value.copyWith(
            position: event,
            lastPosition: position,
          ));
      ref.read(playBackModel)?.updatePlaybackPosition(position, playbackState.playing, ref);
    } else {
      mediaState.update((value) => value.copyWith(
            position: event,
          ));
    }

    // Feed time updates into SyncPlay drift estimation.
    if (_isSyncPlayActive) {
      ref.read(syncPlayProvider.notifier).updatePlaybackDrift(
            currentPositionTicks: secondsToTicks(
              event.inMilliseconds / 1000,
            ),
            at: DateTime.now().toUtc(),
          );
    }
  }

  Future<bool> loadPlaybackItem(PlaybackModel model, Duration startPositio, bool waitForSyncPlayCommand = true) async {
    ref.read(playBackModel)?.dispose();

  ref.read(syncPlayProvider.notifier).setPlayerBufferingState(true);

  // Only report group buffering for flows that should wait
  // for a SyncPlay unpause command.
  if (_isSyncPlayActive && waitForSyncPlayCommand) {
    ref.read(syncPlayProvider.notifier).reportBuffering();
  }

    await state.stop();
    ref.read(playbackRateProvider.notifier).state = 1.0;
    mediaState.update((state) => state.copyWith(
          state: VideoPlayerState.fullScreen,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
        ));

    final media = model.media;
    PlaybackModel? newPlaybackModel = model;

    // Capture syncplay state before async operations
    final syncPlayActive = _isSyncPlayActive;

    if (media != null) {
      await state.loadVideo(model, startPosition, true);
      await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);

      await state.setAudioTrack(null, model);
      await state.setSubtitleTrack(null, model);
      ref.read(playBackModel.notifier).update((state) => newPlaybackModel);

      await state.play();
      return true;
    }

    ref.read(syncPlayProvider.notifier).setPlayerBufferingState(false);
    mediaState.update((state) => state.copyWith(errorPlaying: true));
    return false;
  }

  Future<void> openPlayer(BuildContext context) async => state.openPlayer(context);

  Future<bool> takeScreenshot() async {
    final syncPath = ref.read(clientSettingsProvider).syncPath;
    // Early return here if we don't have a set/valid path. Skips actually taking the screenshot
    // which would be discarded.
    if (syncPath == null) {
      return false;
    }

    final screenshotsPath = p.join(syncPath, "Screenshots");
    final screenshotBuf = await state.takeScreenshot();

    if (screenshotBuf != null) {
      final savePathDirectory = Directory(screenshotsPath);

      // Should we try to create the directory instead?
      if (!await savePathDirectory.exists()) {
        return false;
      }

      final fileExtension = "png";
      final paddingAmount = 3;

      int maxNumber = 0;

      await for (var file in savePathDirectory.list()) {
        final finalSegment = file.uri.pathSegments.last;

        if (file is File && p.extension(finalSegment) == ".$fileExtension") {
          final match = RegExp(r'(\d+)').firstMatch(finalSegment);

          if (match != null) {
            final fileNumber = int.parse(match.group(0)!);

            if (fileNumber > maxNumber) {
              maxNumber = fileNumber;
            }
          }
        }
      }

      maxNumber += 1;

      final maxNumberStr = maxNumber.toString().padLeft(paddingAmount, '0');
      final screenshotName = '$maxNumberStr.$fileExtension';
      final screenshotPath = p.join(screenshotsPath, screenshotName);

      final screenshotFile = File(screenshotPath);
      await screenshotFile.writeAsBytes(screenshotBuf);

      return true;
    }

    return false;
  }

  // ============================================
  // User-initiated actions (go through SyncPlay if active)
  // ============================================

  /// User-initiated play - routes through SyncPlay if active
  Future<void> userPlay() async {
    if (_isSyncPlayActive) {
      // Just request unpause. The server will put the group in Waiting state,
      // and our buffering listener will report Ready(isPlaying: false) when appropriate.
      await ref.read(syncPlayProvider.notifier).requestUnpause();
    } else {
      await state.play();
    }
  }

  /// User-initiated pause - routes through SyncPlay if active
  Future<void> userPause() async {
    if (_isSyncPlayActive) {
      await ref.read(syncPlayProvider.notifier).requestPause();
    } else {
      await state.pause();
    }
  }

  /// User-initiated seek - routes through SyncPlay if active
  Future<void> userSeek(Duration position) async {
    if (_isSyncPlayActive) {
      final positionTicks = secondsToTicks(position.inMilliseconds / 1000);
      await ref.read(syncPlayProvider.notifier).requestSeek(positionTicks);
    } else {
      // Remember if we were playing before seek
      final wasPlaying = playbackState.playing;
      await state.seek(position);
      // Resume playback if we were playing before (for native player consistency)
      if (wasPlaying && !playbackState.playing) {
        await state.play();
      }
    }
  }

  /// User-initiated play/pause toggle - routes through SyncPlay if active
  Future<void> userPlayOrPause() async {
    if (playbackState.playing) {
      await userPause();
    } else {
      await userPlay();
    }
  }
}

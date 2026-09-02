import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/media_segments_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart' show PlaybackChangeSource, SyncPlayCommandType;
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;

final mediaPlaybackProvider = StateProvider<MediaPlaybackModel>((ref) => MediaPlaybackModel());

final playBackModel = StateProvider<PlaybackModel?>((ref) => null);

final isVideoPlayerRouteOpenProvider = StateProvider<bool>((ref) => false);

/// Action the next-up card offers while it is on screen, registered by the
/// video player overlay so a hardware media button can start the next item
/// instead of toggling playback.
final nextUpPlayNowProvider = StateProvider<VoidCallback?>((ref) => null);

/// Lands in the diagnostics file beside the SyncPlay traces.
final _playbackLog = logging.Logger('Playback');

final videoPlayerProvider = StateNotifierProvider<VideoPlayerNotifier, MediaControlsWrapper>((ref) {
  final videoPlayer = VideoPlayerNotifier(ref);
  videoPlayer.init();
  return videoPlayer;
});

class VideoPlayerNotifier extends StateNotifier<MediaControlsWrapper> {
  /// How long the player takes to advance after being told to play, as an
  /// estimate that follows what it measures. Starts at a typical cold start;
  /// each measured start moves it a third of the way to the new value.
  int _startLatencyMs = 300;
  DateTime? _playRequestedAt;
  Duration _positionAtPlayRequest = Duration.zero;

  void _measureStartLatency(bool playing, Duration position) {
    final requestedAt = _playRequestedAt;
    if (requestedAt == null) return;
    final since = DateTime.now().difference(requestedAt);
    if (playing && position > _positionAtPlayRequest + const Duration(milliseconds: 40)) {
      _playRequestedAt = null;
      final latency = since.inMilliseconds.clamp(0, 2000);
      _startLatencyMs = (_startLatencyMs * 2 + latency) ~/ 3;
      _playbackLog.info('start latency ${latency}ms; estimate now ${_startLatencyMs}ms');
    } else if (since > const Duration(seconds: 3)) {
      _playRequestedAt = null;
    }
  }

  VideoPlayerNotifier(this.ref) : super(MediaControlsWrapper(ref: ref));

  final Ref ref;

  List<StreamSubscription> subscriptions = [];

  late final mediaState = ref.read(mediaPlaybackProvider.notifier);

  MediaPlaybackModel get playbackState => ref.read(mediaPlaybackProvider);

  /// Flag to indicate if the current action is initiated by SyncPlay
  bool _syncPlayAction = false;

  /// Guards against a media session delivering one press as two events; a
  /// press this close behind the last is treated as a repeat of it.
  ///
  /// Deliberately short. An earlier, longer window existed to absorb Windows
  /// sending the same key through both SMTC and the focused window, but the
  /// two can arrive further apart than any sane debounce - the in-app key
  /// handler was dropped instead, so only genuine duplicates land here.
  static const _mediaButtonDebounce = Duration(milliseconds: 120);

  DateTime? _lastMediaButtonPress;

  /// Too little of a segment left for skipping it to mean anything. Also
  /// absorbs a seek landing slightly short of the end on a keyframe.
  static const _segmentSkipFloor = Duration(seconds: 2);

  /// True while [loadPlaybackItem] is loading new media on behalf of a
  /// SyncPlay-driven flow (initial play or queue change). The buffering
  /// listener must not auto-report Ready/Buffering during this window:
  /// media-kit on web doesn't reliably emit `playing=true` synchronously
  /// with `buffering=false`, and the listener would race [loadPlaybackItem]
  /// with a stale `isPlaying: false` Ready that overrides the explicit
  /// `Ready(isPlaying: true)` we send when the load is complete.
  bool _isLoadingForSyncPlay = false;

  /// Cooldown period after SyncPlay command during which we don't auto-report ready
  static const _syncPlayCooldown = Duration(milliseconds: 500);

  /// Debounce before a spontaneous buffering blip is reported to the group.
  /// Reporting `Buffering` puts the whole group into `Waiting` and pauses
  /// everyone (spec behavior), so a sub-second stall on one peer's link
  /// shouldn't ripple out. Genuine stalls last longer than this and still
  /// pause the group; only brief blips are absorbed locally.
  static const _bufferReportDebounce = Duration(milliseconds: 400);
  Timer? _bufferReportDebounceTimer;
  bool _bufferingReportedToGroup = false;

  /// Check if SyncPlay is active
  bool get _isSyncPlayActive => ref.read(isSyncPlayActiveProvider);

  /// True while a corrective SkipToSync seek is in progress. The seek forces a
  /// fresh buffer fill (expensive on a remote/transcoded stream); reporting
  /// that rebuffer would pause the whole group, so we suppress it — SyncPlay's
  /// own cooldown re-enables correction once the seek settles.
  bool get _isCorrectionSeekActive =>
      ref.read(syncPlayProvider.select((s) => s.correctionState.activeStrategy)) == SyncCorrectionStrategy.skipToSync;

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
    // While casting, the app acts as a remote control: keep the cast player
    // alive and let loadPlaybackItem route the new item to the receiver
    // instead of resetting to a local player. SyncPlay must stay wired
    // through this (a group-driven item start calls init() too): re-register
    // its callbacks — idempotent — and make sure the state-stream feed
    // exists, which it won't be when the cast session was adopted without a
    // local playback ever having run.
    if (state.isCasting) {
      if (subscriptions.isEmpty) _subscribeToPlayerStream();
      _registerSyncPlayCallbacks();
      return;
    }

    await state.stop();
    // The mpv context survives the teardown when it is what the next item
    // will use anyway; the wrapper's own subscriptions are still reset.
    await state.dispose(releasePlayer: !state.canReusePlayer);
    await state.init();

    for (final s in subscriptions) {
      s.cancel();
    }
    subscriptions.clear();

    _bufferReportDebounceTimer?.cancel();
    _bufferReportDebounceTimer = null;
    _bufferingReportedToGroup = false;

    _subscribeToPlayerStream();

    // Register player callbacks with SyncPlay
    _registerSyncPlayCallbacks();

    // Listen to SyncPlay state changes for native player overlay
    _setupSyncPlayStateListener();
  }

  void _subscribeToPlayerStream() {
    final subscription = state.stateStream.listen((value) {
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
      _measureStartLatency(value.playing, value.position);
      updatePlaying(value.playing);
      updatePosition(value.position);
      updateDuration(value.duration);
    });

    subscriptions.add(subscription);
  }

  /// Set up listener to forward SyncPlay command state to native player
  void _setupSyncPlayStateListener() {
    // Through the container, not `ref.listen`: that would make this provider
    // depend on SyncPlay, and SyncPlay's controller reads this provider back -
    // a loop that Riverpod's debug check reported as an unhandled
    // CircularDependencyError on every position tick. A container listener
    // registers no dependency; the subscription is closed with the provider.
    final subscription = ref.container.listen<SyncPlayState>(
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
    ref.onDispose(subscription.close);
  }

  SyncPlayCommandType _toSyncPlayCommandType(SyncPlayCommand? commandType) {
    return switch (commandType) {
      SyncPlayCommand.pause => SyncPlayCommandType.pause,
      SyncPlayCommand.unpause => SyncPlayCommandType.unpause,
      SyncPlayCommand.seek => SyncPlayCommandType.seek,
      SyncPlayCommand.stop => SyncPlayCommandType.stop,
      null => SyncPlayCommandType.none,
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
            _playRequestedAt = DateTime.now();
            _positionAtPlayRequest = playbackState.position;
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
          getDurationTicks: () => secondsToTicks(playbackState.duration.inMilliseconds / 1000),
          getStartLatencyMs: () => _startLatencyMs,
          isPlaying: () => playbackState.playing,
          isBuffering: () => _isReloading || playbackState.buffering,
          // Local players (ExoPlayer/mpv) support setPlaybackSpeed; surfacing
          // it lets SyncPlay drift correction pick SpeedToSync (rate nudge,
          // no buffering) instead of falling back to SkipToSync, which on
          // ExoPlayer triggers STATE_BUFFERING and amplifies into a
          // post-Unpause buffer-cycle on Android-TV. Remote players without a
          // rate command (Jellyfin Cast receiver, DLNA) report false —
          // otherwise correction loops on a silent no-op and never seeks.
          hasPlaybackRate: () => state.playbackRateSupported,
        );
  }

  /// True while a SyncPlay command is being scheduled/executed. The
  /// command handler owns the Buffering/Ready exchange in that window
  /// and we must not race it with our own reports — for a Seek command
  /// in particular, sending Ready(isPlaying: false) here (because the
  /// command paused the local player) overrides the command handler's
  /// Ready(isPlaying: true) and the server then keeps the group paused
  /// instead of broadcasting Unpause.
  bool get _isSyncPlayCommandInFlight => ref.read(syncPlayProvider.select((s) => s.isProcessingCommand));

  Future<void> updateBuffering(bool event) async {
    final oldState = playbackState;
    if (oldState.buffering == event) {
      return;
    }

    mediaState.update((state) => state.copyWith(buffering: event));
    if (_isSyncPlayActive) {
      ref.read(syncPlayProvider.notifier).setPlayerBufferingState(event);
    }

    // Report buffering state to SyncPlay if active.
    // Skip if we're in the cooldown period after a SyncPlay command to prevent
    // feedback loops; if we're currently reloading (we'll report manually when
    // done); while a command is being processed (the command handler owns the
    // Ready signal then); and while a corrective SkipToSync seek is settling
    // (its rebuffer must not pause the group).
    if (event) {
      final canReport = _isSyncPlayActive &&
          !_syncPlayAction &&
          !_inSyncPlayCooldown &&
          !_isReloading &&
          !_isSyncPlayCommandInFlight &&
          !_isLoadingForSyncPlay &&
          !_isCorrectionSeekActive;
      // Debounce: only tell the group we're buffering if the stall outlasts
      // the debounce window, so brief blips don't pause everyone.
      _bufferReportDebounceTimer?.cancel();
      if (canReport) {
        _bufferReportDebounceTimer = Timer(_bufferReportDebounce, () {
          if (!_isSyncPlayActive || !playbackState.buffering) return;
          _bufferingReportedToGroup = true;
          ref.read(syncPlayProvider.notifier).reportBuffering();
        });
      }
    } else {
      // Buffering finished. Cancel any pending (not-yet-sent) report. If we
      // already told the group we were buffering, release it with Ready —
      // unless a SyncPlay command/reload now owns the Ready handshake, in
      // which case that path sends it (avoids racing/overriding it).
      _bufferReportDebounceTimer?.cancel();
      _bufferReportDebounceTimer = null;
      if (_isSyncPlayActive && _bufferingReportedToGroup) {
        _bufferingReportedToGroup = false;
        if (!_syncPlayAction &&
            !_inSyncPlayCooldown &&
            !_isReloading &&
            !_isSyncPlayCommandInFlight &&
            !_isLoadingForSyncPlay) {
          ref.read(syncPlayProvider.notifier).reportReady(isPlaying: playbackState.playing);
        }
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
    if (!state.remoteReportsProgress) {
      // `currentState` was captured before the mediaState update above, so
      // report `event` — its `playing` still holds the superseded value.
      ref.read(playBackModel)?.updatePlaybackPosition(currentState.position, event, ref);
    }
  }

  Future<void> updatePosition(Duration event) async {
    if (!state.hasPlayer) return;
    // The local player can emit stale/jittery positions while paused, so ignore
    // them. Remote players report an authoritative position even while paused
    // (e.g. adopting a paused cast session), so let those through — otherwise
    // the scrubber sticks at 0:00 until the first play (#6).
    if (playbackState.playing == false && !state.isCasting) return;
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
      if (!state.remoteReportsProgress) {
        ref.read(playBackModel)?.updatePlaybackPosition(position, playbackState.playing, ref);
      }
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

  Future<bool> loadPlaybackItem(
    PlaybackModel model,
    Duration startPosition, {
    bool waitForSyncPlayCommand = true,
    /// Set by the paths that go on to open the player route: a play the user
    /// asked for. The minimized surfaces' own loads - the next episode from
    /// the bar - leave it false and stay where they are.
    bool openFullScreen = false,
  }) async {
    final oldPlaybackModel = ref.read(playBackModel);

    if (_isSyncPlayActive) {
      // Null the old playback model BEFORE state.stop() so its
      // 1-second-delayed POST /Sessions/Playing/Stopped is suppressed
      // (state.stop() exits early when playBackModel is null). That
      // POST is a session-lifecycle event Jellyfin broadcasts to the
      // SyncPlay group, which causes other clients (and ourselves via
      // the "pause locally on Buffer" handler) to pause. media-kit's
      // open() in loadVideo replaces the current media in place — no
      // explicit stop is needed for an in-route reload (track switch,
      // queue change while route is already open).
      ref.read(playBackModel.notifier).update((_) => null);
    }
    oldPlaybackModel?.dispose();

    ref.read(syncPlayProvider.notifier).setPlayerBufferingState(true);
    // Timed into the diagnostics log, so a slow start can be read rather
    // than guessed at.
    final loadTimer = Stopwatch()..start();

    final reportingForSyncPlay = _isSyncPlayActive && waitForSyncPlayCommand;
    // Position we're loading at — the local player's position is 0
    // here (the player just got reset), so we must pass this
    // explicitly to the SyncPlay reports. Otherwise the server reads
    // 0 from the buffering/ready payloads and broadcasts it as the
    // group's position, resetting every other client to the start.
    final loadPositionTicks = startPosition.inMicroseconds * 10;
    if (reportingForSyncPlay) {
      _isLoadingForSyncPlay = true;
      ref.read(syncPlayProvider.notifier).reportBuffering(positionTicks: loadPositionTicks);
    }

    try {
      // SyncPlay keeps the old full stop: its model is already nulled above,
      // so stop() early-returns into a plain silence. Everything else gets
      // the switch-safe stop that leaves player state and model alone.
      if (_isSyncPlayActive) {
        await state.stop();
      } else {
        await state.stopForItemSwitch();
      }
      ref.read(playbackRateProvider.notifier).state = 1.0;

      // Audio / no-video items play in the minimized player. While casting, the
      // phone is a remote control, so also minimize so the user can keep browsing.
      // And a load fired FROM the minimized player (next-episode in the bar or
      // floating window) must stay minimized: flipping to fullScreen without
      // the player route open makes every minimized surface disappear while
      // the audio plays on.
      final stayMinimized = ref.read(mediaPlaybackProvider).state == VideoPlayerState.minimized &&
          !ref.read(isVideoPlayerRouteOpenProvider);
      final useMinimizedPlayer = (stayMinimized && !openFullScreen) ||
          state.isCasting ||
          model.item.type == FladderItemType.audio ||
          model.mediaStreams?.videoStreams.isEmpty == true;

      mediaState.update((state) => state.copyWith(
            state: useMinimizedPlayer ? VideoPlayerState.minimized : VideoPlayerState.fullScreen,
            fullScreen: !useMinimizedPlayer,
            buffering: true,
            errorPlaying: false,
            skippedSegments: {},
          ));

      final media = model.media;
      PlaybackModel? newPlaybackModel = model;
      // develop: resolve the resume position for normal playback. For a
      // SyncPlay load the group dictates the position, so honour the
      // requested start as-is.
      final effectiveStartPosition =
          reportingForSyncPlay ? startPosition : await model.resolvedStartPosition(startPosition);

      if (media == null) {
        ref.read(syncPlayProvider.notifier).setPlayerBufferingState(false);
        mediaState.update((state) => state.copyWith(errorPlaying: true));
        if (reportingForSyncPlay) {
          unawaited(ref.read(syncPlayProvider.notifier).reportReady(isPlaying: false));
        }
        return false;
      }

      // Publish the new model BEFORE loadVideo: remote players (DLNA/AirPlay/
      // universal cast) resolve their stream URL through the cast provider,
      // which reads playBackModel — publishing after the load made it resolve
      // null when connected idle, or the *previous* item's stream on a
      // mid-cast episode switch.
      ref.read(playBackModel.notifier).update((state) => newPlaybackModel);

      // Don't auto-play during a SyncPlay-driven load. The server's
      // Unpause command (broadcast after all clients report Ready) is
      // what drives playback for the group; auto-playing here races
      // the protocol and produces a stale isPlaying:false Ready (see
      // _isLoadingForSyncPlay docstring above).
      await state.loadVideo(model, effectiveStartPosition, !reportingForSyncPlay);
      _playbackLog.info('load: player opened after ${loadTimer.elapsedMilliseconds}ms');

      // Together: the track selections each wait, capped at five seconds, for
      // mpv to have read the track list, and one after the other that cap
      // was paid twice; the volume needs none of that.
      await Future.wait([
        state.setVolume(ref.read(videoPlayerSettingsProvider).volume),
        state.setAudioTrack(null, model),
        state.setSubtitleTrack(null, model),
      ]);
      _playbackLog.info('load: tracks selected after ${loadTimer.elapsedMilliseconds}ms');

      if (!reportingForSyncPlay) {
        await state.play();
      } else {
        // Tell the server we're loaded and intend to play. The
        // buffering listener stayed silent thanks to
        // _isLoadingForSyncPlay, so this is the only Ready that
        // reaches the server for this load — server broadcasts
        // Unpause and onPlay drives the actual playback. We send
        // the load position explicitly so the server knows where
        // we'll be when playback resumes.
        await ref.read(syncPlayProvider.notifier).reportReady(
              isPlaying: true,
              positionTicks: loadPositionTicks,
            );
      }
      _playbackLog.info('load: ${reportingForSyncPlay ? 'ready reported' : 'playing'} after ${loadTimer.elapsedMilliseconds}ms');
      return true;
    } catch (e, stackTrace) {
      ref.read(syncPlayProvider.notifier).setPlayerBufferingState(false);
      mediaState.update((state) => state.copyWith(errorPlaying: true, buffering: false));
      // Tell the group we recovered (with isPlaying:false) so the server
      // doesn't keep everyone else paused waiting on us.
      if (reportingForSyncPlay) {
        unawaited(ref.read(syncPlayProvider.notifier).reportReady(isPlaying: false));
      }
      developer.log('loadPlaybackItem failed: $e\n$stackTrace');
      return false;
    } finally {
      _isLoadingForSyncPlay = false;
    }
  }

  Future<bool> loadAudioPlaybackItem(
    PlaybackModel model,
    List<ItemBaseModel> queue,
    int currentIndex,
    Duration startPosition,
  ) async {
    final currentPlayerState = ref.read(mediaPlaybackProvider).state;
    final keepFullScreenLayout = currentPlayerState == VideoPlayerState.fullScreen;
    final playbackSettings = ref.read(mediaPlaybackProvider);

    final initializedQueueState = PlaybackQueueState.fromQueue(
      queue,
      initialItemId: queue[currentIndex.clamp(0, queue.length - 1)].id,
      shuffleEnabled: playbackSettings.shuffleEnabled,
      repeatMode: playbackSettings.repeatMode,
    );
    final queuedModel = model.updatePlaybackQueue(initializedQueueState);
    final effectiveStartPosition = await queuedModel.resolvedStartPosition(startPosition);

    ref.read(playBackModel.notifier).update((state) => queuedModel);
    ref.read(playbackRateProvider.notifier).state = 1.0;

    mediaState.update((state) => state.copyWith(
          state: keepFullScreenLayout ? VideoPlayerState.fullScreen : VideoPlayerState.minimized,
          fullScreen: keepFullScreenLayout,
          buffering: true,
          errorPlaying: false,
          skippedSegments: {},
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));

    await state.loadAudioQueue(queue, currentIndex, effectiveStartPosition, true);
    await state.setVolume(ref.read(videoPlayerSettingsProvider).volume);

    mediaState.update((state) => state.copyWith(
          buffering: false,
          playing: true,
          position: effectiveStartPosition,
          duration: queuedModel.item.overview.runTime ?? Duration.zero,
        ));
    return true;
  }

  Future<void> reorderAudioQueueSection(
    AudioQueueSection section,
    int oldIndex,
    int newIndex,
  ) async {
    await state.reorderAudioQueueSection(section, oldIndex, newIndex);
  }

  Future<void> addToTemporaryQueue(List<ItemBaseModel> items) async {
    await state.addToTemporaryQueue(items);
  }

  Future<void> clearTemporaryQueue() async {
    state.clearTemporaryQueue();
  }

  Future<void> removeAudioQueueItem(ItemBaseModel item) async {
    await state.removeAudioQueueItem(item.id);
  }

  Future<void> removeAudioQueueSectionItem(
    AudioQueueSection section,
    int sectionIndex,
  ) async {
    await state.removeAudioQueueSectionItem(section, sectionIndex);
  }

  Future<void> playAudioQueueItem(ItemBaseModel item) async {
    if (ref.read(playBackModel) == null) return;
    await state.jumpToQueueItem(item);
  }

  /// Once. A second push while the route is up stacked a second player.
  Future<void> openPlayer(BuildContext context) async {
    if (ref.read(isVideoPlayerRouteOpenProvider)) return;
    await state.openPlayer(context);
  }

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
    final wasPlaying = playbackState.playing;
    if (_isSyncPlayActive) {
      // Apply the seek locally immediately so the UI/slider does not snap
      // back to the previous position while we wait for the server to
      // broadcast the Seek command. _syncPlayAction prevents the player
      // state stream from re-triggering userSeek for our own action.
      _syncPlayAction = true;
      try {
        await state.seek(position);
        if (wasPlaying && !playbackState.playing) {
          await state.play();
        }
      } finally {
        _syncPlayAction = false;
      }
      final positionTicks = secondsToTicks(position.inMilliseconds / 1000);
      await ref.read(syncPlayProvider.notifier).requestSeek(positionTicks);
    } else {
      await state.seek(position);
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

  /// Handles a press of the hardware media play/pause button (headphone
  /// button, keyboard media key or the system media controls).
  ///
  /// While the next-up card is on screen the press starts the next item, and
  /// while an intro/outro skip button is on screen it skips that segment.
  /// With neither prompt up, [fallback] runs the caller's normal play/pause.
  ///
  /// Returns true when a prompt consumed the press, so the caller knows the
  /// transport state it was asked for was deliberately not applied.
  Future<bool> mediaButtonPressed(Future<void> Function() fallback) async {
    final now = DateTime.now();
    final previous = _lastMediaButtonPress;
    if (previous != null && now.difference(previous) < _mediaButtonDebounce) return false;
    _lastMediaButtonPress = now;

    // The next-up card takes the button whether or not the episode is still
    // running: by the time it is on screen playback has usually reached the
    // end and stopped, which is exactly when starting the next item is wanted.
    final playNextUp = ref.read(nextUpPlayNowProvider);
    if (playNextUp != null) {
      playNextUp();
      return true;
    }

    // A skip button mid-episode is different - while paused the button should
    // resume first, and skipping then takes a second press.
    if (playbackState.playing) {
      final segment = skippableSegment();
      if (segment != null) {
        await userSeek(segment.end);
        return true;
      }
    }

    await fallback();
    return false;
  }

  /// The segment the on-screen skip button would skip right now, or null when
  /// no skip button is being offered.
  MediaSegment? skippableSegment() {
    final segments = ref.read(playBackModel.select((value) => value?.mediaSegments));
    if (segments == null) return null;
    final position = playbackState.position;
    final segment = segments.atPosition(position);
    if (segment == null) return null;

    // A segment's range includes its end, so the one just skipped still counts
    // as the segment at the position landed on. Offering it again would seek
    // to where we already are, and the button would never reach play/pause.
    //
    // Judged by what is left to skip rather than by remembering the skip, so
    // seeking back into an intro offers it again.
    if (segment.end - position < _segmentSkipFloor) return null;

    final skipType = ref.read(videoPlayerSettingsProvider.select((value) => value.segmentSkipSettings[segment.type]));
    if (skipType == SegmentSkip.none) return null;
    if (segment.visibility(position) == SegmentVisibility.hidden) return null;
    return segment;
  }
}

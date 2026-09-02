import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:logging/logging.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/item_stream_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/audio_prefetch_buffer.dart';
import 'package:fladder/models/playback/audio_url_resolver.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/settings/subtitle_settings_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/src/video_player_helper.g.dart' hide PlaybackState;
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/windows_thumbnail_controls.dart';
import 'package:fladder/wrappers/players/dlna_player.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_receiver_player.dart';
import 'package:fladder/wrappers/players/lib_mdk.dart'
    if (dart.library.html) 'package:fladder/stubs/web/lib_mdk_web.dart';
import 'package:fladder/wrappers/players/lib_mpv.dart';
import 'package:fladder/wrappers/players/native_player.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smtc_windows/smtc_windows.dart' if (dart.library.html) 'package:fladder/stubs/web/smtc_web.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'audio_queue_handler.dart';

final _log = Logger('MediaControls');

/// Cast-related events from the wrapper — named under `Cast` so they land in
/// the persistent cast diagnostics log.
final castLog = Logger('Cast.wrapper');

class MediaControlsWrapper extends BaseAudioHandler implements VideoPlayerControlsCallback {
  MediaControlsWrapper({required this.ref});

  BasePlayer? _player;
  BasePlayer? _previousPlayer;
  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  StreamSubscription<PlayerState>? _playerStateSubscription;

  bool get hasPlayer => _player != null;

  PlayerOptions? get backend => switch (_player) {
        LibMPV _ => PlayerOptions.libMPV,
        LibMDK _ => PlayerOptions.libMDK,
        _ => null,
      };

  Stream<PlayerState> get stateStream => _stateController.stream;
  PlayerState? get lastState => _player?.lastState;

  Widget? subtitleWidget(bool showOverlay, {GlobalKey? controlsKey}) =>
      _player?.subtitles(showOverlay, controlsKey: controlsKey);

  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) =>
      _player?.videoWidget(key, fit, filterQuality: filterQuality);

  final Ref ref;

  List<StreamSubscription> subscriptions = [];
  ProviderSubscription? _subtitleSettingsSubscription;
  SMTCWindows? smtc;

  /// Kept for the wrapper's lifetime alongside [smtc], and never cancelled:
  /// the button stream is an `asBroadcastStream()`, so losing its last listener
  /// closes it permanently and the Windows media keys go dead. See [dispose].
  // ignore: cancel_subscriptions
  StreamSubscription<PressedButton>? _smtcSubscription;

  /// Transport buttons under the taskbar thumbnail preview. Windows builds
  /// these from nothing but what we publish - SMTC doesn't feed them.
  late final WindowsThumbnailControls _thumbnailControls = WindowsThumbnailControls(
    // Same route as the media keys: past the next-up / skip prompts first.
    onPlayPause: () => _handleMediaButtonLater(playbackState.value.playing ? pause : play),
    onStop: () => _handleMediaButtonLater(stop),
  );

  /// Android audio focus. Held from the first play until playback stops, so
  /// other apps' audio pauses and stays paused for the whole session.
  AudioSession? _audioSession;
  bool _audioFocusHeld = false;

  bool initializedWrapper = false;
  bool _isStopped = false;
  bool _isNewPlayback = false;

  /// The position the current playback was last (re)loaded at — the freshest
  /// known truth for the session-start report (the model's startDuration() is
  /// a stale userData snapshot after e.g. a cast handback). Cleared on stop.
  Duration? _lastLoadPosition;
  bool _isAudioQueueMode = false;
  bool _audioQueueTransitioning = false;
  bool _wakelockEnabled = false;

  AudioPrefetchBuffer? _prefetchBuffer;
  List<ItemBaseModel> _mpvPlaylistItems = [];
  int _mpvPlaylistCurrentIndex = 0;
  StreamSubscription<int>? _playlistIndexSub;
  bool _syncingPlaylist = false;
  bool _syncPlaylistPending = false;
  bool _audioQueueRefillInProgress = false;
  bool _audioQueueSourceDepleted = false;
  int _audioQueueNextStartIndex = 0;

  Future<void> init() async {
    if (!initializedWrapper) {
      initializedWrapper = true;
      if (!kIsWeb && Platform.isAndroid) {
        VideoPlayerControlsCallback.setUp(this);
      }
      await AudioService.init(
        builder: () => this,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'uk.jentejan.chudder.channel.playback',
          androidNotificationChannelName: 'Video playback',
          androidNotificationIcon: 'drawable/ic_notification',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          rewindInterval: Duration(seconds: 10),
          fastForwardInterval: Duration(seconds: 15),
          androidNotificationChannelDescription: "Playback",
          androidShowNotificationBadge: true,
        ),
      );
      await _configureAudioSession();
    }

    // The mpv context that is already here is handed back to setup, which
    // clears it rather than building another; see [LibMPV.init].
    final existing = _player;
    final player = canReusePlayer && existing != null
        ? existing
        : switch (ref.read(videoPlayerSettingsProvider).wantedPlayer) {
            PlayerOptions.libMDK => LibMDK(),
            PlayerOptions.libMPV => LibMPV(),
            PlayerOptions.nativePlayer => NativePlayer(),
          };

    setup(player);
  }

  /// Sets up Android audio focus. Asking for a permanent gain is what makes
  /// other apps pause: a transient one only ducks them, and they resume by
  /// themselves the moment it is released.
  Future<void> _configureAudioSession() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      _audioSession = session;
    } catch (error, stackTrace) {
      log('Unable to configure the audio session. Error: $error\n$stackTrace');
    }
  }

  /// Takes audio focus so whatever else is playing on the device stops.
  ///
  /// Focus is kept across our own pauses on purpose - releasing it lets the
  /// other app pick straight back up, and the point is that it stays paused
  /// until the user starts it again themselves.
  Future<void> _takeAudioFocus() async {
    final session = _audioSession;
    if (session == null || _audioFocusHeld) return;
    try {
      _audioFocusHeld = await session.setActive(true);
    } catch (error, stackTrace) {
      log('Unable to take audio focus. Error: $error\n$stackTrace');
    }
  }

  Future<void> _releaseAudioFocus() async {
    final session = _audioSession;
    if (session == null || !_audioFocusHeld) return;
    _audioFocusHeld = false;
    try {
      await session.setActive(false);
    } catch (error, stackTrace) {
      log('Unable to release audio focus. Error: $error\n$stackTrace');
    }
  }

  /// Whether the player that is here can be kept for the next item: the
  /// local mpv backend, alive, and still the backend the settings ask for.
  bool get canReusePlayer {
    final player = _player;
    return player is LibMPV &&
        player.hasLivePlayer &&
        ref.read(videoPlayerSettingsProvider).wantedPlayer == PlayerOptions.libMPV;
  }

  Future<void> dispose({bool releasePlayer = true}) async {
    // Deliberately leaves `smtc` and its button subscription alone. This runs
    // on every playback item load, not just at teardown, and the button stream
    // is an `asBroadcastStream()` - cancelling its last listener closes it for
    // good, so re-listening after a load would silently never fire again.
    unawaited(_releaseAudioFocus());
    _remoteProgressKeepAlive?.cancel();
    _remoteProgressKeepAlive = null;
    _subtitleSettingsSubscription?.close();
    await _playerStateSubscription?.cancel();
    if (releasePlayer) _player?.dispose();
  }

  Future<void> setup(BasePlayer newPlayer) async {
    final oldPlayer = _player;
    if (oldPlayer != null && oldPlayer != newPlayer && _previousPlayer != oldPlayer) {
      // Bounded: a remote player's dispose ends a network session that may
      // never answer (receiver unplugged, SDK wedged). The swap must always
      // complete or the app is stuck "casting" with a dead session.
      try {
        await oldPlayer.dispose().timeout(const Duration(seconds: 8));
      } catch (error) {
        log('setup: old player did not dispose cleanly, continuing swap: $error');
      }
    }

    _player = newPlayer;
    await newPlayer.init(ref.read(videoPlayerSettingsProvider));
    _initPlayer();
    _subscribePlayerState();
    _syncRemoteProgressKeepAlive();
    _syncAndroidPlaybackInfo();
  }

  /// Receiver device volume 0–100 while casting; backs the remote
  /// MediaSession volume provider. Synced from receiver reports when the
  /// device tells us its volume (Jellyfin Cast receiver does).
  int _remoteVolumeLevel = 50;

  /// While casting, mark the Android MediaSession as REMOTE playback with a
  /// volume provider — that's what routes the physical volume keys (even with
  /// the screen off/locked) to the cast device instead of the phone's media
  /// stream, exactly like the official client. Back to local when not casting.
  void _syncAndroidPlaybackInfo() {
    if (kIsWeb || !Platform.isAndroid) return;
    if (isCasting) {
      final reported = (_player as RemotePlayer).remoteVolumeLevel;
      if (reported != null) _remoteVolumeLevel = reported;
      androidPlaybackInfo.add(RemoteAndroidPlaybackInfo(
        volumeControlType: AndroidVolumeControlType.absolute,
        maxVolume: 100,
        volume: _remoteVolumeLevel,
      ));
    } else {
      androidPlaybackInfo.add(LocalAndroidPlaybackInfo());
    }
  }

  @override
  Future<void> androidSetRemoteVolume(int volumeIndex) async {
    if (!isCasting) return;
    _remoteVolumeLevel = volumeIndex.clamp(0, 100);
    await _player?.setVolume(_remoteVolumeLevel.toDouble());
    _syncAndroidPlaybackInfo();
  }

  @override
  Future<void> androidAdjustRemoteVolume(AndroidVolumeDirection direction) async {
    if (!isCasting) return;
    final step = direction == AndroidVolumeDirection.raise
        ? 5
        : direction == AndroidVolumeDirection.lower
            ? -5
            : 0;
    await androidSetRemoteVolume(_remoteVolumeLevel + step);
  }

  /// While a remote player that does NOT own its server session is active
  /// (DLNA, AirPlay, universal Chromecast — the phone reports for them), post
  /// progress on a slow heartbeat regardless of movement. The normal reporting
  /// is edge-driven (>10s position jumps, play/pause transitions), so a paused
  /// renderer reports once and then goes silent until the server reaps the
  /// session and the resume point rots. Not run for the Jellyfin receiver —
  /// that receiver owns its own session.
  Timer? _remoteProgressKeepAlive;

  void _syncRemoteProgressKeepAlive() {
    _remoteProgressKeepAlive?.cancel();
    _remoteProgressKeepAlive = null;
    final player = _player;
    if (player is! RemotePlayer || (player as RemotePlayer).reportsOwnProgress) return;
    _remoteProgressKeepAlive = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (_player is! RemotePlayer) return;
      final model = ref.read(playBackModel);
      final state = _player?.lastState;
      if (model == null || state == null) return;
      try {
        await model.updatePlaybackPosition(state.position, state.playing, ref);
      } catch (error) {
        log('Remote progress keep-alive failed: $error');
      }
    });
  }

  void _initPlayer() {
    _subtitleSettingsSubscription?.close();
    for (var element in subscriptions) {
      element.cancel();
    }
    subscriptions.clear();
    _subscribePlayer();
    _subtitleSettingsSubscription = ref.listen(subtitleSettingsProvider, (_, next) {
      _player?.applySubtitleSettings(next);
    });
  }

  void _subscribePlayerState() {
    _playerStateSubscription?.cancel();
    final player = _player;
    if (player == null) return;

    _playerStateSubscription = player.stateStream.listen((state) {
      if (!_stateController.isClosed) {
        _stateController.add(state);
      }
      // Track receiver-side volume changes (TV remote, other senders) so the
      // phone's volume UI/keys stay in step with the device.
      if (player is RemotePlayer) {
        final reported = (player as RemotePlayer).remoteVolumeLevel;
        if (reported != null && reported != _remoteVolumeLevel) {
          _remoteVolumeLevel = reported;
          _syncAndroidPlaybackInfo();
        }
      }
    });
  }

  Future<void> loadVideo(PlaybackModel model, Duration startPosition, bool play) async {
    _lastLoadPosition = startPosition;
    try {
      if (_player is NativePlayer) {
        final context = ref.read(localizationContextProvider);
        await (_player as NativePlayer).sendPlaybackDataToNative(context, model, startPosition);
      }
      // The cast player's item context is frozen at connect time; point it at
      // the model being loaded so switching media mid-cast reaches the receiver.
      final activePlayer = _player;
      // Same for DLNA: without this, an item started after connecting (or an
      // episode change) loads with the previous item's subtitle selection —
      // or none at all when the cast began idle.
      if (activePlayer is DlnaPlayer) {
        activePlayer.updateTrackSelection(
          subtitleStreamIndex: model.mediaStreams?.defaultSubStreamIndex,
        );
      }
      if (activePlayer is JellyfinReceiverPlayer) {
        activePlayer.updateItem(
          itemStub: {
            'Id': model.item.id,
            'ServerId': ref.read(userProvider)?.credentials.serverId,
            'Name': model.item.name,
            'Type': model.item.jellyType?.value,
            'MediaType': model.isAudioPlayback ? 'Audio' : 'Video',
            'IsFolder': false,
          },
          mediaSourceId: model.mediaStreams?.currentVersionStream?.id ?? model.item.id,
          audioStreamIndex: model.mediaStreams?.defaultAudioStreamIndex,
          subtitleStreamIndex: model.mediaStreams?.defaultSubStreamIndex,
          image: (model.item.images?.backDrop?.firstOrNull ?? model.item.images?.primary)?.imageProvider,
        );
      }
      _isNewPlayback = play;
      await _player?.loadVideo(model.media?.url ?? "", play, startPosition: startPosition);
      _player?.applySubtitleSettings(ref.read(subtitleSettingsProvider));

      final context = ref.read(localizationContextProvider);
      if (context != null) {
        ref.read(windowTitleProvider.notifier).setPlayTitle(model.item.windowTitle(context.localized));
      }
    } finally {
      _isStopped = false;
    }
  }

  Future<void> updateTVGuide(TVGuideModel guide) async {
    if (_player is NativePlayer) {
      (_player as NativePlayer).sendTVGuideModel(guide);
    }
  }

  /// Check if the native Android player is currently active
  bool get isNativePlayerActive => _player is NativePlayer;

  /// Update SyncPlay command state for the native player overlay
  Future<void> updateSyncPlayCommandState(
    bool processing,
    SyncPlayCommandType commandType,
  ) async {
    if (_player is NativePlayer) {
      await (_player as NativePlayer).player.setSyncPlayCommandState(processing, commandType);
    }
  }

  Future<void> _restorePreviousPlayer() async {
    if (_previousPlayer == null) return;
    await setup(_previousPlayer!);
    _previousPlayer = null;
  }

  bool get isCasting => _player is RemotePlayer;
  String? get castDeviceName => _player is RemotePlayer ? (_player as RemotePlayer).deviceName : null;

  /// Whether the active player can actually change playback rate — SyncPlay
  /// uses this to pick SpeedToSync vs SkipToSync drift correction.
  bool get playbackRateSupported => _player?.supportsPlaybackRate ?? true;

  /// Raised for the whole cast-handoff window: the local player's final
  /// pause/position events can fire after the phone's session is closed but
  /// before the remote player is swapped in, which would re-register the
  /// phone's session on the server.
  bool _remoteSessionHandoff = false;

  /// True while the remote device maintains its own server session (the
  /// Jellyfin Cast receiver). The phone must then suppress its own playback
  /// reporting (started/progress/stopped) or the server sees two conflicting
  /// sessions for the same item.
  bool get remoteReportsProgress =>
      _remoteSessionHandoff || (_player is RemotePlayer && (_player as RemotePlayer).reportsOwnProgress);

  /// Hands off the currently playing item to a connected remote [remotePlayer]
  /// (Chromecast or DLNA), keeping the local player around so playback can resume
  /// on disconnect.
  Future<void> startCasting(BasePlayer remotePlayer) async {
    if (isCasting) return;
    // While in a SyncPlay group the handoff runs local-only: the buffering
    // flap and session churn of the swap must not broadcast Buffering or a
    // session stop to the group (which would pause everyone) — and on
    // completion runLocalOnly nudges the cast to the group time.
    if (ref.read(isSyncPlayActiveProvider)) {
      await ref.read(syncPlayProvider.notifier).runLocalOnly(() => _startCastingInner(remotePlayer, true));
    } else {
      await _startCastingInner(remotePlayer, false);
    }
  }

  Future<void> _startCastingInner(BasePlayer remotePlayer, bool syncPlayActive) async {
    final model = ref.read(playBackModel);
    final position = _player?.lastState.position ?? Duration.zero;
    final remoteOwnsSession = remotePlayer is RemotePlayer && (remotePlayer as RemotePlayer).reportsOwnProgress;

    // Suppress the phone's reporting BEFORE pausing: the pause's own state
    // events would otherwise re-register the phone session after we close it.
    if (remoteOwnsSession) _remoteSessionHandoff = true;

    _previousPlayer = _player;
    log('startCasting: handing off to ${remotePlayer.runtimeType} '
        '(local playing=${_player?.lastState.playing ?? false}, pos=${position.inSeconds}s)');
    try {
      await _player?.pause();

      // When the receiver runs its own server session, close the phone's session
      // at the handoff point so the server doesn't keep a stale duplicate (this
      // also saves the resume point). stopCasting re-registers it via play().
      // Skipped in a SyncPlay group: Jellyfin broadcasts the session stop to
      // the group and pauses everyone (same reason loadPlaybackItem nulls the
      // model before stop) — the group governs position there anyway.
      // Closing the phone's session is a server round trip, and the swap to
      // the remote player is local; they used to run one after the other.
      Future<void>? closeSession;
      if (model != null && remoteOwnsSession && !syncPlayActive) {
        closeSession = model.playbackStopped(position, _player?.lastState.duration, ref).then<void>((_) {}).catchError(
          (Object error) {
            log('Failed to close local session on cast handoff: $error');
          },
        );
      }

      await setup(remotePlayer);
      if (closeSession != null) await closeSession;

      // Belt-and-suspenders: the local player can occasionally resume from a late
      // media-kit "playing" event that races the pause during load, leaving audio
      // playing on the phone while we appear "connected" (#5). Pausing an
      // already-paused player is a no-op.
      if (_previousPlayer?.lastState.playing == true) {
        log('startCasting: local player still playing after handoff — re-pausing');
      }
      await _previousPlayer?.pause();

      if (model != null) {
        await loadVideo(model, position, true);
        await play();
      }
    } catch (error) {
      // Roll back the half-finished handoff so isCasting and the reporting
      // suppression can't stay latched onto a session that never started.
      log('startCasting failed — restoring the local player: $error');
      _remoteSessionHandoff = false;
      if (isCasting) await _restorePreviousPlayer();
      _previousPlayer = null;
      rethrow;
    }
  }

  /// Tears down the remote session and resumes playback on the local player at
  /// the position the receiver reached.
  Future<void> stopCasting() async {
    if (!isCasting) return;
    // Same local-only window as startCasting: the swap back must not
    // broadcast Buffering/session churn to a SyncPlay group.
    if (ref.read(isSyncPlayActiveProvider)) {
      await ref.read(syncPlayProvider.notifier).runLocalOnly(_stopCastingInner);
    } else {
      await _stopCastingInner();
    }
  }

  Future<void> _stopCastingInner() async {
    final model = ref.read(playBackModel);
    final position = _player?.lastState.position ?? Duration.zero;

    await _restorePreviousPlayer();
    // Local playback owns the session again — resume reporting so play()
    // re-registers the phone with the server.
    _remoteSessionHandoff = false;

    if (model != null) {
      await loadVideo(model, position, true);
      await play();
    }
  }

  Future<void> openPlayer(BuildContext context) async => _player?.open(context);

  Future<void> _updatePositionWithRetry(PlaybackModel model, Duration position, bool isPlaying) async {
    try {
      await model.updatePlaybackPosition(position, isPlaying, ref);
    } catch (error, stackTrace) {
      log('Failed to send playing: $isPlaying state to server. Retrying once. Error: $error\n$stackTrace');
      try {
        await Future.delayed(const Duration(milliseconds: 250));
        await model.updatePlaybackPosition(position, isPlaying, ref);
      } catch (retryError, retryStackTrace) {
        log('Retry failed for playing: $isPlaying state update. Error: $retryError\n$retryStackTrace');
      }
    }
  }

  void _subscribePlayer() {
    // Guard order matters: `Platform.isWindows` itself reads
    // `Platform._operatingSystem` which is unsupported on Flutter Web
    // and throws. Always check `kIsWeb` first.
    if (!kIsWeb && Platform.isWindows) {
      // Built once and reused for every player. Each SMTCWindows registers its
      // own Windows media session, so making a new one per player swap leaves
      // stale sessions behind holding the metadata of whatever played then.
      final controls = smtc ??= SMTCWindows(
        config: const SMTCConfig(
          fastForwardEnabled: true,
          nextEnabled: false,
          pauseEnabled: true,
          playEnabled: true,
          rewindEnabled: true,
          prevEnabled: false,
          stopEnabled: true,
        ),
      );

      // Outside `subscriptions`, which is torn down on every player swap, and
      // never cancelled - see the note in [dispose].
      _smtcSubscription ??= controls.buttonPressStream.listen((event) {
        switch (event) {
          case PressedButton.play:
            // The keyboard media key toggles through SMTC, so route it
            // past the next-up / skip-segment prompts first.
            //
            // Handled off this callback: everything up to the first await runs
            // inside the Rust event dispatch, and on the skip path that starts
            // a seek whose state updates call straight back into SMTC.
            // Re-entering it leaves it deaf to further presses.
            _handleMediaButtonLater(play);
            break;
          case PressedButton.pause:
            _handleMediaButtonLater(pause);
            break;
          case PressedButton.fastForward:
            fastForward();
            break;
          case PressedButton.rewind:
            rewind();
            break;
          case PressedButton.stop:
            stop();
            break;
          case PressedButton.previous:
            skipToPrevious();
            break;
          case PressedButton.next:
            skipToNext();
            break;
          case PressedButton.record:
            break;
          case PressedButton.channelUp:
            break;
          case PressedButton.channelDown:
            break;
        }
      },
          onError: (Object error, StackTrace stack) =>
              _log.warning('Windows media control button stream failed', error, stack));
    }

    subscriptions.add(_player!.stateStream.listen((value) {
      playbackState.add(playbackState.value.copyWith(
        bufferedPosition: value.buffer,
        processingState: value.buffering ? AudioProcessingState.buffering : AudioProcessingState.ready,
        updatePosition: value.position,
        playing: value.playing,
      ));
      // A throwing Rust call here would otherwise vanish into the zone and
      // leave the media controls quietly stale.
      try {
        smtc?.setPosition(value.position);
        smtc?.setPlaybackStatus(value.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
        unawaited(_thumbnailControls.show(playing: value.playing));
      } catch (error, stack) {
        _log.warning('Updating the Windows media controls failed', error, stack);
      }
      unawaited(_applyWakelock(_shouldKeepScreenOn(value.playing)));
      if (value.completed && !_audioQueueTransitioning) {
        _onAudioTrackCompleted();
      }
    }));
  }

  /// Runs a media button press on a later turn of the event loop, so the
  /// caller's own event dispatch has unwound before playback is touched.
  void _handleMediaButtonLater(Future<void> Function() fallback) {
    Future(() async {
      final consumedByPrompt = await ref.read(videoPlayerProvider.notifier).mediaButtonPressed(fallback);
      if (consumedByPrompt) await _settleTransportState();
    });
  }

  /// A prompt took the press, so the pause SMTC asked for was never applied.
  /// Windows then stops routing media keys until the reported state changes,
  /// and a Bluetooth headset keeps its own model of that state from AVRCP -
  /// which merely reporting a paused/playing flicker did not satisfy.
  ///
  /// So make the transition real: pause and resume for a moment. Everything
  /// downstream sees a genuine transition because there was one.
  ///
  /// SyncPlay is unaffected. These are the raw player controls rather than
  /// `userPause`/`userPlay`, so no group command is sent, and the listener
  /// that infers user intent from the player only fires for a `changeSource`
  /// the native Android player sets - this runs on the Windows SMTC path,
  /// where the player is libMPV. The skip's own seek does reach the group,
  /// which is intended.
  Future<void> _settleTransportState() async {
    if (_player?.lastState.playing != true) return;
    await pause();
    await Future.delayed(const Duration(milliseconds: 150));
    await play();
  }

  /// Media button presses that aren't an explicit play or pause - the
  /// headphone/bluetooth button on Android lands here.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button != MediaButton.media) return super.click(button);
    // The result only matters to the SMTC path, which has a transport state to
    // reconcile; a headset button carries no such expectation.
    await ref.read(videoPlayerProvider.notifier).mediaButtonPressed(() => super.click(button));
  }

  @override
  Future<void> skipToNext() async {
    if (_isAudioQueueMode) {
      final wasRepeatOne = await _disableRepeatOneForSkip();
      if (!wasRepeatOne &&
          _player is LibMPV &&
          _isMpvPlaylistInSync() &&
          _mpvPlaylistItems.length > _mpvPlaylistCurrentIndex + 1) {
        final current = _mpvPlaylistItems[_mpvPlaylistCurrentIndex];
        final next = _mpvPlaylistItems[_mpvPlaylistCurrentIndex + 1];
        if (!_shouldCrossfade(current, next, manual: true)) {
          await (_player as LibMPV).playerNext();
          return;
        }
      }
      await _playNextQueueItem(manual: true);
      return;
    }
    return loadNextVideo();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_isAudioQueueMode) {
      if (_player?.lastState.position != null && _player!.lastState.position >= const Duration(seconds: 3)) {
        await _player?.seek(Duration.zero);
        return;
      }
      final wasRepeatOne = await _disableRepeatOneForSkip();
      if (!wasRepeatOne && _player is LibMPV && _isMpvPlaylistInSync() && _mpvPlaylistCurrentIndex > 0) {
        final current = _mpvPlaylistItems[_mpvPlaylistCurrentIndex];
        final previous = _mpvPlaylistItems[_mpvPlaylistCurrentIndex - 1];
        if (!_shouldCrossfade(current, previous, manual: true)) {
          await (_player as LibMPV).playerPrevious();
          return;
        }
      }
      await _playPreviousQueueItem();
      return;
    }
    return loadPreviousVideo();
  }

  bool _shouldKeepScreenOn(bool playing) {
    final item = ref.read(playBackModel.select((value) => value?.item));
    return playing && item is! AudioModel;
  }

  /// [force] re-applies even when the cached state already matches, since
  /// Android silently clears the keep-screen-on flag while we still think it's set.
  Future<void> _applyWakelock(bool shouldEnable, {bool force = false}) async {
    if (!force && shouldEnable == _wakelockEnabled) return;
    _wakelockEnabled = shouldEnable;
    if (shouldEnable) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  }

  Future<void> reassertWakelock() async =>
      _applyWakelock(_shouldKeepScreenOn(_player?.lastState.playing ?? false), force: true);

  @override
  Future<void> pause() async {
    await _player?.pause();
    final position = _player?.lastState.position ?? Duration.zero;
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      updatePosition: position,
      controls: [MediaControl.play],
    ));
    unawaited(_applyWakelock(false));
    final playerState = _player;
    if (playerState != null) {
      final model = ref.read(playBackModel);
      if (model != null) {
        if (!remoteReportsProgress) {
          await _updatePositionWithRetry(model, position, false);
        }
        await _refreshMediaControls(model: model, playing: false);
      }
    }
    return super.pause();
  }

  @override
  Future<void> play() async {
    final playBackItem = ref.read(playBackModel.select((value) => value?.item));
    if (playBackItem is AudioModel) {
      _isStopped = false;
    }
    unawaited(_applyWakelock(_shouldKeepScreenOn(true)));
    await _takeAudioFocus();

    await _player?.play();

    // Report the freshest position we know: the live player position
    // (pause→resume), else the position this playback was loaded at (the
    // player may still read 0 right after a load), else the model's
    // startDuration() — a userData snapshot that goes stale after e.g. a cast
    // handback, where the receiver progressed the item long past it.
    final livePosition = _player?.lastState.position ?? Duration.zero;
    final currentPosition = livePosition > Duration.zero
        ? livePosition
        : _lastLoadPosition ?? await ref.read(playBackModel.select((value) => value?.startDuration()));
    if (_isNewPlayback || !playbackState.value.playing) {
      _isNewPlayback = false;
      if (!remoteReportsProgress) {
        final model = ref.read(playBackModel);
        if (model != null) unawaited(_reportStarted(model, currentPosition));
      }
    }
    if (playBackItem == null) return;

    final playbackModel = ref.read(playBackModel);
    if (playbackModel != null) {
      await _refreshMediaControls(model: playbackModel, playing: true);
    }

    return super.play();
  }

  Future<void> _refreshMediaControls({PlaybackModel? model, required bool playing}) async {
    if (!ref.read(clientSettingsProvider).enableMediaKeys) return;
    final playbackModel = model ?? ref.read(playBackModel);
    if (playbackModel == null) return;

    final playBackItem = playbackModel.item;
    final poster =
        playBackItem.images?.primary ?? (playBackItem is ItemStreamModel ? playBackItem.parentImages?.primary : null);
    final currentPosition = _player?.lastState.position ?? await playbackModel.startDuration() ?? Duration.zero;

    windowSMTCSetup(playBackItem, currentPosition, playing);

    final hasNextVideo = ref.read(playBackModel.select((value) => value?.nextVideo != null));
    final hasPreviousVideo = ref.read(playBackModel.select((value) => value?.previousVideo != null));

    final queue = playbackModel.queue;
    final currentQueueIndex = queue.indexWhere((entry) => entry.id == playbackModel.item.id);
    final hasAudioQueue = queue.length > 1;
    final hasNextAudio = hasAudioQueue && (currentQueueIndex >= 0 ? currentQueueIndex < queue.length - 1 : true);
    final hasPreviousAudio = _isAudioQueueMode || (hasAudioQueue && (currentQueueIndex > 0 || currentQueueIndex == -1));

    final canSkipNext = hasNextVideo || hasNextAudio;
    final canSkipPrevious = hasPreviousVideo || hasPreviousAudio;

    final isMusic = playBackItem is AudioModel;

    final album = playBackItem is AudioModel ? playBackItem.album : null;
    final artist = playBackItem is AudioModel ? playBackItem.artistModel?.name : null;

    mediaItem.add(MediaItem(
      id: playBackItem.id,
      album: album,
      artist: artist,
      title: playBackItem.title,
      genre: playBackItem.overview.genres.join(', '),
      rating: Rating.newHeartRating(playBackItem.userData.isFavourite),
      duration: playBackItem.overview.runTime ?? const Duration(seconds: 0),
      artUri: poster != null ? _imageDataToUri(poster.path) : null,
    ));
    playbackState.add(PlaybackState(
      playing: playing,
      updatePosition: currentPosition,
      bufferedPosition: _player?.lastState.buffer ?? playbackState.value.bufferedPosition,
      controls: [
        if (playing) MediaControl.pause else MediaControl.play,
        if (canSkipNext) MediaControl.skipToNext,
        if (canSkipPrevious) MediaControl.skipToPrevious,
      ],
      systemActions: {
        if (canSkipNext) MediaAction.skipToNext,
        if (canSkipPrevious) MediaAction.skipToPrevious,
        MediaAction.seek,
        if (!isMusic) MediaAction.fastForward,
        MediaAction.setSpeed,
        if (!isMusic) MediaAction.rewind,
      },
      processingState:
          (_player?.lastState.buffering ?? false) ? AudioProcessingState.buffering : AudioProcessingState.ready,
    ));
  }

  Future<void> windowSMTCSetup(ItemBaseModel playBackItem, Duration currentPosition, bool playing) async {
    final mainContext = ref.read(localizationContextProvider);
    final poster =
        playBackItem.images?.primary ?? (playBackItem is ItemStreamModel ? playBackItem.parentImages?.primary : null);

    //Windows setup
    smtc?.updateMetadata(MusicMetadata(
      title: playBackItem.title,
      artist: mainContext != null ? playBackItem.label(mainContext.localized) : null,
      thumbnail: poster != null ? _imageDataToUri(poster.path).toString() : null,
    ));
    smtc?.updateTimeline(
      PlaybackTimeline(
        startTimeMs: 0,
        endTimeMs: (playBackItem.overview.runTime ?? const Duration(seconds: 0)).inMilliseconds,
        positionMs: currentPosition.inMilliseconds,
        minSeekTimeMs: 0,
        maxSeekTimeMs: (playBackItem.overview.runTime ?? const Duration(seconds: 0)).inMilliseconds,
      ),
    );

    smtc?.enableSmtc();
    smtc?.setPlaybackStatus(playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    unawaited(_thumbnailControls.show(playing: playing));
  }

  /// Silences the player and tears the media session down. Split out of
  /// [stop] because everything below its early returns was skippable, and a
  /// player left running with no UI attached to it cannot be stopped by any
  /// other means — the session keeps the app alive, so it cannot even be
  /// killed.
  Future<void> _silence() async {
    await _player?.stop();
    unawaited(_applyWakelock(false));
    smtc?.setPlaybackStatus(PlaybackStatus.stopped);
    smtc?.clearMetadata();
    smtc?.disableSmtc();
    unawaited(_thumbnailControls.hide());
    await _releaseAudioFocus();
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.completed,
        controls: [],
      ),
    );
  }

  /// The BaseAudioHandler default is `stop()` — which, while casting, sends a
  /// Stop command to the receiver. Android 14+ lets the user swipe away even a
  /// foreground-service media notification, and the system can drop it when
  /// the service leaves the foreground after a pause, so with the default a
  /// dismissed phone notification kills playback on the TV. While casting the
  /// notification is only a remote control; losing it must not touch the
  /// receiver.
  @override
  Future<void> onNotificationDeleted() async {
    if (isCasting) {
      castLog.info('Media notification deleted while casting — ignoring (not stopping the receiver)');
      return;
    }
    await super.onNotificationDeleted();
  }

  /// The stop report of the item that was just left, if it is still on its way.
  Future<void>? _pendingStopReport;

  Future<void> _reportStopped(PlaybackModel model, Duration position, Duration? totalDuration) async {
    try {
      await Future.delayed(const Duration(seconds: 1));
      if (remoteReportsProgress) return;
      await model.playbackStopped(position, totalDuration, ref);
    } catch (e) {
      log('Failed to report playback stopped: $e');
    }
  }

  /// Waits for any report still on its way to the server. For the moments the
  /// server has to know before something else happens - signing out, where a
  /// stop that arrives after the session is gone is a resume point lost.
  Future<void> flushReports() async {
    final pending = _pendingStopReport;
    if (pending != null) await pending;
  }

  /// The start report, and the progress post that gives it a position. Not
  /// waited for by the caller: the player is already running, and the route
  /// used to stay behind a spinner for two round trips of telemetry.
  Future<void> _reportStarted(PlaybackModel model, Duration? position) async {
    try {
      await _pendingStopReport;
      await model.playbackStarted(position ?? Duration.zero, ref);
      // The start post carries no positionTicks, so follow with a progress
      // post - otherwise the server shows the session at 0/stale until the
      // first >10s movement report (~10s later).
      if (position != null && position > Duration.zero) {
        await _updatePositionWithRetry(model, position, true);
      }
    } catch (e) {
      log('Failed to report playback started: $e');
    }
  }

  /// The stop used between one item and the next. [stop] is for the user
  /// pressing stop: it marks the player disposed (which tears down PiP - the
  /// system window cannot be re-entered programmatically), waits a second and
  /// nulls the playback model (which erases every minimized surface). None of
  /// that may happen mid-switch: silence the old item, report its session
  /// closed, and leave all presentation state alone for the incoming load.
  Future<void> stopForItemSwitch() async {
    final playbackModel = ref.read(playBackModel);
    _lastLoadPosition = null;
    final position = _player?.lastState.position ?? ref.read(mediaPlaybackProvider).lastPosition;
    final totalDuration = _player?.lastState.duration;
    await _silence();
    if (playbackModel != null && !remoteReportsProgress) {
      unawaited(playbackModel.playbackStopped(position, totalDuration, ref));
    }
  }

  @override
  Future<void> stop() async {
    if (isCasting) {
      castLog.info('stop() invoked while casting — the receiver will be told to stop', null, StackTrace.current);
    }
    final playbackModel = ref.read(playBackModel);

    // Stop the sound before anything can decide there is nothing to do. Both
    // of the conditions below used to return with the player still playing:
    // no playback model (cancelled before it was set) and an already-latched
    // stop (a load that finished after the first stop and started playing).
    if (playbackModel == null || _isStopped) {
      await _silence();
      return;
    }
    _isStopped = true;
    _lastLoadPosition = null;

    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.disposed));
    ref.read(windowTitleProvider.notifier).setPlayTitle(null);

    // A player that's already gone reports nothing, and posting a stop at zero
    // tells the server to forget the resume point entirely - worse than a
    // slightly stale one. Fall back to the last position we saw.
    final position = _player?.lastState.position ?? ref.read(mediaPlaybackProvider).lastPosition;
    final totalDuration = _player?.lastState.duration;

    // Silence straight after reading the position, not at the end: the report
    // below waits a second and then goes to the network, and none of that is
    // a reason to keep playing sound at someone who pressed stop.
    await _silence();

    // Reported in a moment, and not waited for. The report waits a second so
    // it does not land on top of a progress post, then goes to the network;
    // neither is a reason to hold up whatever is being started next, and
    // this used to sit in front of every play while something else was
    // loaded. The next start report waits on it instead, so the server still
    // hears the two in the order they happened.
    _pendingStopReport = _reportStopped(playbackModel, position, totalDuration);
    _remoteSessionHandoff = false;

    ref.read(playBackModel.notifier).update((_) => null);

    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: Duration.zero));

    if (_isAudioQueueMode) {
      _isAudioQueueMode = false;
      _playlistIndexSub?.cancel();
      _playlistIndexSub = null;
      _prefetchBuffer?.invalidate();
      _prefetchBuffer = null;
      _mpvPlaylistItems = [];
      _mpvPlaylistCurrentIndex = 0;
      _syncingPlaylist = false;
      _syncPlaylistPending = false;
      await _restorePreviousPlayer();
    }

    return super.stop();
  }

  Future<void> playOrPause() async {
    // Hardware media keys, SMTC and the thumbnail bar land here directly —
    // route through the group while SyncPlay is active, or the toggle stays
    // local and the next group command reverts it. userPause/userPlay call
    // state.pause()/play() (not this method), so there is no recursion.
    if (ref.read(isSyncPlayActiveProvider)) {
      if (_player?.lastState.playing == true) {
        await ref.read(videoPlayerProvider.notifier).userPause();
      } else {
        await ref.read(videoPlayerProvider.notifier).userPlay();
      }
      return;
    }
    await _player?.playOrPause();
    final playing = _player?.lastState.playing ?? false;

    final position = _player?.lastState.position ?? Duration.zero;
    playbackState.add(playbackState.value.copyWith(
      playing: playing,
      updatePosition: position,
      controls: [playing ? MediaControl.pause : MediaControl.play],
    ));

    unawaited(_applyWakelock(_shouldKeepScreenOn(playing)));

    final playerState = _player;
    if (playerState != null) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: position));

      final model = ref.read(playBackModel);
      if (model != null) {
        // Same suppression as play()/pause(): while the receiver owns the
        // server session, a progress post from the phone would re-register a
        // duplicate session.
        if (!remoteReportsProgress) {
          await _updatePositionWithRetry(model, position, playerState.lastState.playing);
        }
        await _refreshMediaControls(model: model, playing: playing);
      }
    }
  }

  Uri _imageDataToUri(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    return Uri.file(path);
  }

  bool _isMpvPlaylistInSync() {
    final playbackModel = ref.read(playBackModel);
    if (playbackModel == null) return false;
    if (_mpvPlaylistItems.isEmpty) return false;
    if (_mpvPlaylistCurrentIndex < 0 || _mpvPlaylistCurrentIndex >= _mpvPlaylistItems.length) return false;
    return _mpvPlaylistItems[_mpvPlaylistCurrentIndex].id == playbackModel.item.id;
  }

  /// Applies the selected quality option to the cast receiver. "Original"
  /// maps to a very high cap so compatible files direct-play; "Auto" lets the
  /// receiver detect its own bandwidth. The server still negotiates against
  /// the receiver's device profile, so incompatible streams cannot happen.
  Future<void> applyCastQuality(PlaybackModel model) async {
    final player = _player;
    final selected = model.bitRateOptions.enabledFirst.keys.firstOrNull;
    final maxBitrate = switch (selected) {
      null || Bitrate.auto => null,
      Bitrate.original => 1000000000,
      _ => selected.bitRate,
    };
    if (player is JellyfinReceiverPlayer) {
      await player.setMaxBitrate(maxBitrate);
    } else if (player is DlnaPlayer) {
      // DLNA rebuilds its own stream: a real cap transcodes at that bitrate,
      // "original"/auto keeps the file direct-playing.
      await player.setMaxBitrate(maxBitrate);
    }
  }

  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async =>
      await _player?.setAudioTrack(model, playbackModel) ?? -1;

  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async =>
      await _player?.setSubtitleTrack(model, playbackModel) ?? -1;

  Future<void> setVolume(double volume) async => _player?.setVolume(volume);

  @override
  Future<void> seek(Duration position) {
    _player?.seek(position);
    if (_player?.lastState.playing == false) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(position: position));
    }
    return super.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) {
    _player?.setSpeed(speed);
    return super.setSpeed(speed);
  }

  //Native player calls
  @override
  Future<void> loadNextVideo() async {
    final nextVideo = ref.read(playBackModel.select((value) => value?.nextVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    if (nextVideo != null && !buffering) ref.read(playbackModelHelper).loadNewVideo(nextVideo);
  }

  @override
  Future<void> loadPreviousVideo() async {
    final previousVideo = ref.read(playBackModel.select((value) => value?.previousVideo));
    final buffering = ref.read(mediaPlaybackProvider.select((value) => value.buffering));
    if (previousVideo != null && !buffering) ref.read(playbackModelHelper).loadNewVideo(previousVideo);
  }

  @override
  void onStop() => stop();

  @override
  void swapAudioTrack(int value) async {
    final playbackModel = ref.read(playBackModel);
    final newModel = await playbackModel?.setAudio(
        playbackModel.audioStreams?.firstWhere((element) => element.index == value), this);
    ref.read(playBackModel.notifier).update((state) => newModel);
    if (newModel != null) {
      await ref.read(playbackModelHelper).shouldReload(
            newModel,
            isLocalTrackSwitch: true,
          );
    }
  }

  @override
  void swapSubtitleTrack(int value) async {
    final playbackModel = ref.read(playBackModel);
    final newModel = await playbackModel?.setSubtitle(
        playbackModel.subStreams?.firstWhere((element) => element.index == value), this);
    ref.read(playBackModel.notifier).update((state) => newModel);
    if (newModel != null) {
      await ref.read(playbackModelHelper).shouldReload(
            newModel,
            isLocalTrackSwitch: true,
          );
    }
  }

  @override
  Future<void> loadProgram(GuideChannel selection) async {
    final channelId = selection.channelId;
    final model = await ref.read(liveTvProvider.notifier).fetchDashboard();
    final channel = model.channels.firstWhereOrNull((c) => c.id == channelId);
    if (channel != null) {
      await ref.read(playbackModelHelper).loadTVChannel(channel);
    }
  }

  @override
  Future<List<GuideProgram>> fetchProgramsForChannel(String channelId) async {
    final channel =
        (await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: channelId)).body as ChannelModel;

    final programs = await ref.read(liveTvProvider.notifier).fetchProgramsForChannel(channel);

    final context = ref.read(localizationContextProvider);

    return programs
        .map((p) => GuideProgram(
              id: p.id,
              channelId: channelId,
              name: p.name,
              startMs: p.startDate.millisecondsSinceEpoch,
              endMs: p.endDate.millisecondsSinceEpoch,
              primaryPoster: p.images?.primary?.path,
              overview: p.overview,
              subTitle: context != null ? p.subLabel(context.localized) : null,
            ))
        .toList();
  }

  // SyncPlay-aware user actions from native player
  @override
  void onUserPlay() {
    ref.read(videoPlayerProvider.notifier).userPlay();
  }

  @override
  void onUserPause() {
    ref.read(videoPlayerProvider.notifier).userPause();
  }

  @override
  void onUserSeek(int positionMs) {
    ref.read(videoPlayerProvider.notifier).userSeek(Duration(milliseconds: positionMs));
  }

  Future<Uint8List?> takeScreenshot() {
    final player = _player;

    if (player == null) {
      return Future.value(null);
    }

    return player.takeScreenshot();
  }
}

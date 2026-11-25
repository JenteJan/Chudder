import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:audio_session/audio_session.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;
import 'package:media_kit/media_kit.dart' as mpv;
import 'package:media_kit_video/media_kit_video.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/providers/settings/subtitle_settings_provider.dart';
import 'package:chudder/screens/video_player/video_player_route.dart';
import 'package:chudder/util/subtitle_position_calculator.dart';
import 'package:chudder/util/subtitle_track_selection.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/mpv_properties.dart'
    if (dart.library.html) 'package:chudder/stubs/web/mpv_properties_web.dart';
import 'package:chudder/wrappers/players/player_states.dart';
import 'package:chudder/wrappers/players/windows_hdr.dart';

// Lands in cast_log.txt, where the subtitle picker's choices can be read
// back after a session.
final _log = logging.Logger('Playback');

/// Subtitle formats that are pictures rather than text: PGS from Blu-rays,
/// VobSub and DVB from DVDs and broadcasts.
///
/// Both vocabularies are listed. The server names a DVD track `dvdsub` and
/// mpv names the same track `dvd_subtitle`, and the name that arrives here is
/// whichever side the track came from - so a list holding only one of the two
/// made a picture track look like text every time mpv answered.
const _bitmapSubtitleCodecs = {
  'pgssub',
  'pgs',
  'hdmv_pgs_subtitle',
  'dvdsub',
  'vobsub',
  'dvd_subtitle',
  'dvbsub',
  'dvb_subtitle',
  'xsub',
};

bool isBitmapSubtitleCodec(String codec) => _bitmapSubtitleCodecs.contains(codec.toLowerCase());

/// The picture subtitles that were drawn for a television: a few hundred
/// pixels wide, blocky once a window stretches them. A Blu-ray's PGS is not
/// one of them - it is sharp at full size and blurring it only softens it.
const _lowResolutionSubtitleCodecs = {'dvdsub', 'vobsub', 'dvd_subtitle', 'dvbsub', 'dvb_subtitle', 'xsub'};

/// How much of a blur softens a low resolution subtitle, on mpv's 0 to 3
/// scale - roughly what the same subtitle looked like on a television.
const _pictureSubtitleBlur = 1.0;

class LibMPV extends BasePlayer {
  mpv.Player? _player;
  VideoController? _controller;
  String _currentSubtitleCodec = '';

  /// What a picture subtitle should look like. Kept because the settings can
  /// change while one is on screen, and because a track selected later has to
  /// be drawn the same way.
  SubtitleSettingsModel _subtitleSettings = const SubtitleSettingsModel();
  bool _pictureSubtitle = false;
  String _pictureSubtitleCodec = '';
  int? _appliedSubtitlePosition;
  double? _appliedSubtitleBlur;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  StreamSubscription<bool>? _onCompleted;

  bool _replayGainFallbackLogged = false;
  VideoPlayerSettingsModel _settings = VideoPlayerSettingsModel();

  RestartableTimer? _retryTimer;

  /// Broken-timestamp fallback, see [_onMpvLog].
  int _invalidTimestampWarnings = 0;
  DateTime? _invalidTimestampWindowStart;
  bool _fixedFrameRateTiming = false;
  static const _invalidTimestampThreshold = 8;
  static const _invalidTimestampWindow = Duration(seconds: 5);
  DateTime _firstLoadAttempt = DateTime.now();
  final Duration _maxRetryDuration = const Duration(minutes: 1);
  final Duration _currentRetryDuration = const Duration(seconds: 5);
  Completer<void>? _loadCompleter;
  final List<StreamSubscription> _playerStreamSubs = [];
  double _preferredVolume = 100;
  int _crossfadeGeneration = 0;
  Timer? _fadeTimer;
  Duration get playPauseFadeDuration => const Duration(milliseconds: 175);
  AudioSession? _audioSession;

  bool _musicPaused = false;

  /// Play and pause at once, without the fade.
  bool instantTransport = false;

  Future<void> setupAudioSession() async {
    _audioSession = await AudioSession.instance;
    await _audioSession?.configure(const AudioSessionConfiguration.music());
  }

  /// Whether there is a live mpv context that [init] could keep.
  bool get hasLivePlayer => _player != null;

  /// The settings that decide how the mpv context is built. Anything else
  /// can be applied to a context that already exists.
  static bool _sameContext(VideoPlayerSettingsModel a, VideoPlayerSettingsModel b) =>
      a.bufferSize == b.bufferSize && a.useLibass == b.useLibass && a.hardwareAccel == b.hardwareAccel;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    final existing = _player;
    if (existing != null && _sameContext(settings, _settings)) {
      // The same context, cleared. A new mpv context per play - a fresh
      // texture, hardware decoding negotiated again, the property round
      // trips below - was a black gap in front of every item; stopping the
      // one that exists leaves it ready for the next open.
      _settings = settings;
      _fadeTimer?.cancel();
      _fadeTimer = null;
      _crossfadeGeneration++;
      _onCompleted?.cancel();
      _onCompleted = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      _loadCompleter = null;
      await existing.stop();
      setState(PlayerState());
      await _applyReplayGainSettings();
      await _applyPictureSettings();
      await _applyBitmapSubtitleRendering('');
      return;
    }

    _settings = settings;
    dispose();

    mpv.MediaKit.ensureInitialized();

    _player = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        title: "uk.jentejan.chudder",
        libassAndroidFont: libassFallbackFont,
        libass: !kIsWeb && settings.useLibass,
        bufferSize: settings.bufferSize * 1024 * 1024, // MPV uses buffer size in bytes
        // Warnings are needed for the broken-timestamp fallback in [_onMpvLog].
        logLevel: mpv.MPVLogLevel.warn,
      ),
    );

    if (_player != null) {
      _controller = VideoController(
        _player!,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: settings.hardwareAccel,
        ),
      );
      _hdrOutput = false;
      _hdrContent = false;
      WindowsHdr.paperWhiteNits.removeListener(_onPaperWhite);
      WindowsHdr.paperWhiteNits.addListener(_onPaperWhite);
      WindowsHdr.display.removeListener(_updateHdr);
      WindowsHdr.display.addListener(_updateHdr);
      _setupPlayerStreams(_player!);
      _playerStreamSubs.add(_player!.stream.log.listen(_onMpvLog));
      _playerStreamSubs.add(_player!.stream.videoParams.listen(_onVideoParams));
    }

    if (_player?.platform is mpv.NativePlayer) {
      final nativePlayer = _player!.platform as dynamic;
      await nativePlayer.setProperty('force-seekable', 'yes');
      await nativePlayer.setProperty('gapless-audio', 'yes');
      await nativePlayer.setProperty('cache', 'yes');
      await nativePlayer.setProperty('demuxer-max-bytes', '150M');
      await nativePlayer.setProperty('network-timeout', '60');
      await nativePlayer.setProperty('stream-buffer-size', '4M');
      await nativePlayer.setProperty('prefetch-playlist', 'yes');

      if (defaultTargetPlatform == TargetPlatform.android) {
        await nativePlayer.setProperty('ao', 'audiotrack');
      }

      setupAudioSession();
    }

    await _applyReplayGainSettings();
    await _applyPictureSettings();
  }

  /// Dithering, and debanding when the user has it on.
  ///
  /// Most HEVC and every HDR file is 10-bit, and the picture ends up in an
  /// 8-bit texture or surface (SDR on Windows, all of Android). Rounded
  /// without dithering, smooth gradients - dark scenes, skies, tone-mapped
  /// HDR - turn into visible steps. `dither-depth=auto` dithers to whatever
  /// the output holds, so the 16-bit HDR texture gets next to nothing.
  /// This is mpv's own default, which media_kit switches off on Android.
  /// It costs one lookup in a small noise texture per pixel, in a pass that
  /// runs anyway; a GPU that cannot hold that texture falls back to ordered
  /// dithering. Measured with tool-made gradients (chudder-lab/bench/dither):
  /// without it a 10-bit ramp shows as 77 px wide steps; with it the steps
  /// are gone, and "fruit" leaves less pattern behind than "ordered".
  ///
  /// Debanding is separate: it smooths steps that are already in the file
  /// (8-bit encodes), and costs real GPU time, so it is the user's choice.
  Future<void> _applyPictureSettings() async {
    if (_player?.platform is! mpv.NativePlayer) return;
    final native = _player!.platform as dynamic;
    try {
      await native.setProperty('dither', 'fruit');
      await native.setProperty('dither-depth', 'auto');
      await native.setProperty('deband', _settings.debanding ? 'yes' : 'no');
    } catch (error) {
      log('Unable to apply dithering/debanding: $error');
    }
  }

  @override
  Future<void> setDebanding(bool enabled) async {
    _settings = _settings.copyWith(debanding: enabled);
    if (_player?.platform is! mpv.NativePlayer) return;
    await (_player!.platform as dynamic).setProperty('deband', enabled ? 'yes' : 'no');
  }

  /// Whether the window and the video output are in HDR (Windows, on an
  /// engine with HDR support; see [WindowsHdr]).
  bool _hdrOutput = false;

  /// The HDR mode last switched to.
  bool _hdrWanted = false;

  /// Whether the file is HDR video (PQ or HLG, as mpv reads it).
  bool _hdrContent = false;

  /// Switches run one after another, each on the latest state.
  Future<void> _hdrSwitches = Future.value();

  /// HDR video switches the window to an HDR swap chain and the output to
  /// linear light while the window's display is in HDR; anything else
  /// switches both back. A file that has not reported yet (no transfer
  /// function) changes nothing, so going from one HDR episode to the next
  /// does not flicker through SDR.
  void _onVideoParams(mpv.VideoParams params) {
    final gamma = params.gamma;
    if (gamma == null || gamma.isEmpty) return;
    _hdrContent = gamma == 'pq' || gamma == 'hlg';
    _updateHdr();
  }

  /// HDR goes on or off to match the file and the display: also when the
  /// window moves to another display mid-film, or HDR is switched on or off
  /// in Windows' settings.
  void _updateHdr() {
    _hdrSwitches = _hdrSwitches.then((_) async {
      final enabled = _hdrContent && _controller != null && await WindowsHdr.displayHdr();
      if (_hdrContent && !enabled && !_hdrWanted) {
        log('LibMPV: HDR video on a display that is not in HDR; staying SDR');
      }
      await _setHdrOutput(enabled);
    }).catchError((Object error) => log('LibMPV: HDR switch failed: $error'));
  }

  void _stopHdr() {
    _hdrContent = false;
    if (_hdrWanted) _updateHdr();
  }

  /// The HDR brightness setting changed: the output keeps the level while
  /// SDR and applies it at once while HDR.
  void _onPaperWhite() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.platform.future.then(
      (output) => (output as dynamic).setHdrPaperWhite(WindowsHdr.paperWhiteNits.value) as Future<void>,
    ));
  }

  Future<void> _setHdrOutput(bool enabled) async {
    if (enabled == _hdrWanted) return;
    _hdrWanted = enabled;
    final controller = _controller;
    if (controller == null || !await WindowsHdr.supported()) return;
    final output = await controller.platform.future as dynamic;
    if (enabled) {
      await output.setHdrPaperWhite(WindowsHdr.paperWhiteNits.value);
      // The window first: an HDR texture in an SDR window would clip.
      if (!await WindowsHdr.setHdr(true)) return;
      final ok = await output.setHdr(true) as bool;
      if (!ok) {
        await WindowsHdr.setHdr(false);
        return;
      }
      _hdrOutput = true;
      WindowsHdr.active.value = true;
      log('LibMPV: HDR output on');
    } else {
      if (_hdrOutput) await output.setHdr(false);
      await WindowsHdr.setHdr(false);
      _hdrOutput = false;
      WindowsHdr.active.value = false;
      log('LibMPV: HDR output off');
    }
  }

  @override
  Future<void> dispose() async {
    unawaited(_audioSession?.setActive(false));
    WindowsHdr.paperWhiteNits.removeListener(_onPaperWhite);
    WindowsHdr.display.removeListener(_updateHdr);
    _stopHdr();
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _crossfadeGeneration++;
    _cancelPlayerStreams();
    _onCompleted?.cancel();
    _onCompleted = null;
    _player?.stop();
    _player?.dispose();
    _player = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void setState(PlayerState state) {
    if (state.playing && _musicPaused) {
      _musicPaused = false;
    }
    final newState = state.update(
      playing: !_musicPaused,
    );
    lastState = newState;
    _stateController.add(newState);
  }

  void _cancelPlayerStreams() {
    for (final sub in _playerStreamSubs) {
      sub.cancel();
    }
    _playerStreamSubs.clear();
  }

  void _setupPlayerStreams(mpv.Player player) {
    _playerStreamSubs.addAll([
      player.stream.playing.listen((value) {
        setState(lastState.update(playing: value));
      }),
      player.stream.buffering.listen((value) => setState(lastState.update(buffering: value))),
      player.stream.position.listen((value) => setState(lastState.update(position: value))),
      player.stream.duration.listen((value) => setState(lastState.update(duration: value))),
      player.stream.volume.listen((value) {
        setState(lastState.update(volume: value));
      }),
      player.stream.rate.listen((value) => setState(lastState.update(rate: value))),
      player.stream.buffer.listen((value) => setState(lastState.update(buffer: value))),
      player.stream.completed.listen((value) => setState(lastState.update(completed: value))),
    ]);
  }

  Future<void> crossfadeToUrl(String url, Duration startPosition, {double? replayGainDb}) async {
    if (!_settings.enableCrossfade || !VideoPlayerSettingsModel.crossfadeSupportedOnCurrentPlatform) {
      await _applyReplayGainSettings(trackGainDb: replayGainDb);
      await loadVideo(url, true, startPosition: startPosition);
      return;
    }

    final oldPlayer = _player;
    if (oldPlayer == null) {
      await loadVideo(url, true, startPosition: startPosition);
      return;
    }

    const stepMs = 16;
    final steps = math.max(1, _settings.crossfadeDurationMs ~/ stepMs);

    final incomingPlayer = mpv.Player(
      configuration: mpv.PlayerConfiguration(
        title: "uk.jentejan.chudder",
        libassAndroidFont: libassFallbackFont,
        libass: !kIsWeb && _settings.useLibass,
        bufferSize: _settings.bufferSize * 1024 * 1024,
      ),
    );

    if (incomingPlayer.platform is mpv.NativePlayer) {
      final native = incomingPlayer.platform as dynamic;
      await native.setProperty('force-seekable', 'yes');
      await native.setProperty('gapless-audio', 'weak');
      if (defaultTargetPlatform == TargetPlatform.android) {
        await native.setProperty('ao', 'audiotrack');
      }
      await native.setProperty('start', '${startPosition.inMilliseconds / 1000}');
    }

    await _applyReplayGainSettings(trackGainDb: replayGainDb, targetPlayer: incomingPlayer);
    _fadeTimer?.cancel();
    _fadeTimer = null;
    await incomingPlayer.setVolume(0.0);
    await incomingPlayer.open(mpv.Media(url), play: true);

    final generation = ++_crossfadeGeneration;
    final fromVolume = oldPlayer.state.volume.clamp(0.0, 100.0);

    bool aborted = false;
    for (var i = 1; i <= steps; i++) {
      if (generation != _crossfadeGeneration) {
        aborted = true;
        break;
      }
      final progress = i / steps;
      await oldPlayer.setVolume(fromVolume * (1.0 - progress));
      await incomingPlayer.setVolume(_preferredVolume * progress);
      if (i < steps) await Future.delayed(const Duration(milliseconds: stepMs));
    }

    if (aborted || generation != _crossfadeGeneration) {
      incomingPlayer.stop();
      incomingPlayer.dispose();
      return;
    }

    _cancelPlayerStreams();
    _player = incomingPlayer;
    _controller = null;
    _setupPlayerStreams(incomingPlayer);

    _retryTimer?.cancel();
    _retryTimer = null;
    _loadCompleter = null;

    oldPlayer.stop();
    oldPlayer.dispose();

    setState(lastState.update(
      playing: incomingPlayer.state.playing,
      buffering: incomingPlayer.state.buffering,
      position: incomingPlayer.state.position,
      duration: incomingPlayer.state.duration,
      volume: _preferredVolume,
      buffer: incomingPlayer.state.buffer,
      completed: false,
    ));
  }

  /// Some files carry decode-order timestamps on a B-frame stream - an mp4
  /// muxed without composition offsets, for one. ffmpeg's own decoders repair
  /// that from the packet dts, but the MediaCodec decoder on Android hands mpv
  /// no dts at all, so mpv sees the timestamps run backwards, drops the "late"
  /// frames and plays at half the frame rate. mpv's fixed-frame-rate timing
  /// mode ignores the decoder timestamps and shows frames in output order at
  /// the container's rate, which is exactly right for such a file, so switch
  /// to it once the warnings pile up. Reset per file in [loadVideo].
  void _onMpvLog(mpv.PlayerLog entry) {
    if (_fixedFrameRateTiming || !entry.text.startsWith('Invalid video timestamp')) return;
    final now = DateTime.now();
    final windowStart = _invalidTimestampWindowStart;
    if (windowStart == null || now.difference(windowStart) > _invalidTimestampWindow) {
      _invalidTimestampWindowStart = now;
      _invalidTimestampWarnings = 0;
    }
    if (++_invalidTimestampWarnings < _invalidTimestampThreshold) return;
    _fixedFrameRateTiming = true;
    log('LibMPV: decoder timestamps are broken, switching to fixed-frame-rate timing');
    unawaited(_setCorrectPts(false));
  }

  Future<void> _setCorrectPts(bool enabled) async {
    if (_player?.platform is! mpv.NativePlayer) return;
    // Through `dynamic`, as the other property writes here are: the web
    // build compiles against a stub NativePlayer without `setProperty`.
    await (_player!.platform as dynamic).setProperty('correct-pts', enabled ? 'yes' : 'no');
  }

  @override
  Future<void> setVideoOutputEnabled(bool enabled) async {
    if (_player?.platform is! mpv.NativePlayer) return;
    await (_player!.platform as dynamic).setProperty('vid', enabled ? 'auto' : 'no');
  }

  @override
  bool get supportsSubtitleDelay => _player?.platform is mpv.NativePlayer;

  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    if (_player?.platform is! mpv.NativePlayer) return;
    await (_player!.platform as dynamic).setProperty('sub-delay', (delay.inMilliseconds / 1000).toStringAsFixed(3));
  }

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    _loadCompleter = Completer<void>();
    // What is reported as playing is the last thing asked for, and a file
    // opened paused is asked not to play. Without this a group's load - which
    // opens paused and waits for the group - went on reading as playing from
    // the item before, and SyncPlay threw away the resume meant to start it
    // as one it had already carried out.
    _musicPaused = !play;
    _seekTarget = null;
    // A new file starts at the volume the user set. A pause fades mpv's own
    // volume down to nothing before it pauses, and only a play() fades it
    // back up - but the next file opens playing without one, so after any
    // pause (a SyncPlay group pauses before every next episode) it started
    // silent, with every volume control still showing the level it was at.
    _fadeTimer?.cancel();
    _fadeTimer = null;
    await _player?.setVolume(_preferredVolume);
    // mpv keeps a subtitle delay across files; each video starts at the
    // timing its file has.
    await setSubtitleDelay(Duration.zero);
    _firstLoadAttempt = DateTime.now();
    _audioPick++;
    _subtitlePick++;
    _loggedTrackLists = false;

    _invalidTimestampWarnings = 0;
    _invalidTimestampWindowStart = null;
    if (_fixedFrameRateTiming) {
      _fixedFrameRateTiming = false;
      await _setCorrectPts(true);
    }

    // The start goes on the Media: media_kit sets it as the file loads. A
    // `start` set beforehand is wiped by the unload of whatever was open -
    // the previous item, or this one on a retry - and the file opened at 0:00.
    // Not on the web: there media_kit only starts a direct file at it (an HLS
    // stream ignores it), and reports every position as at least the start, so
    // the seek below saw a film at 0:00 as already there and never went.
    await setStartPosition(startPosition);
    final mediaStart = kIsWeb ? null : startPosition;

    await _prepareVideoSurface();
    await _player?.open(mpv.Media(url, start: mediaStart), play: play);

    _retryTimer?.cancel();
    _retryTimer = null;

    final loading = _loadCompleter;
    _retryTimer = RestartableTimer(
      _currentRetryDuration,
      () async {
        await Future.delayed(const Duration(milliseconds: 150));
        // The file may have come in during the wait. Opening it again then
        // threw away where it had started, after the backup seek was spent:
        // a resume that began at the right place jumped back to 0:00.
        if (loading?.isCompleted != false || !identical(loading, _loadCompleter)) return;
        if (DateTime.now().isAfter(_firstLoadAttempt.add(_maxRetryDuration))) {
          log("Max retry duration reached, stopping retries.");
          _retryTimer?.cancel();
          _retryTimer = null;
        } else {
          log("Retrying to load video $url");
          await setStartPosition(startPosition);
          await _player?.open(mpv.Media(url, start: mediaStart), play: play);
          _retryTimer?.reset();
        }
      },
    );

    // Wait for the player to be ready
    if (_loadCompleter?.isCompleted == false) {
      StreamSubscription? subBuffering;
      StreamSubscription? subDuration;

      void onReady() {
        if (_loadCompleter?.isCompleted == true) return;
        _finishedLoading();
        subBuffering?.cancel();
        subDuration?.cancel();
      }

      subBuffering = _player?.stream.buffering.listen((event) {
        if (event == false && (_player?.state.duration ?? Duration.zero) > Duration.zero) {
          onReady();
        }
      });
      subDuration = _player?.stream.duration.listen((event) {
        if (event > Duration.zero) onReady();
      });
    }

    if (startPosition != Duration.zero && kIsWeb) {
      // The browser starts every file at 0:00; it goes to the start as soon as
      // it knows the length, before much of the beginning has played.
      final player = _player;
      final loading = _loadCompleter;
      unawaited(player?.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 15))
          .then((_) async {
        if (!identical(loading, _loadCompleter) || !identical(player, _player)) return;
        await player.seek(startPosition);
      }).catchError((_) {}));
    } else if (startPosition != Duration.zero) {
      // A backup seek for a start mpv did not take. Judged on the first
      // position mpv reports, not on the moment the file is known: by then
      // mpv is still on its way to the start and reads 0:00, and a second
      // seek threw away the download it had begun - seconds of nothing on a
      // phone before the picture came.
      final player = _player;
      final loading = _loadCompleter;
      unawaited(player?.stream.position
          .firstWhere((position) => position > Duration.zero)
          .timeout(const Duration(seconds: 15))
          .then((position) async {
        if (!identical(loading, _loadCompleter) || !identical(player, _player)) return;
        if (position.inSeconds < startPosition.inSeconds - 5) await player.seek(startPosition);
      }).catchError((_) {}));
    }
    return setState(lastState.update(buffering: true));
  }

  /// Apply ReplayGain normalization for the given [item] before loading it.
  /// Call this before [loadVideo] when starting an audio queue item.
  Future<void> applyReplayGainForItem(ItemBaseModel? item) async {
    double? gainDb;
    if (item is AudioModel) {
      final gain = item.normalizationGain;
      if (gain != null && !gain.isNaN && !gain.isInfinite) {
        gainDb = gain.clamp(-60.0, 20.0).toDouble();
      }
    }
    await _applyReplayGainSettings(trackGainDb: gainDb);
  }

  double get _replayGainVolumeOffsetDb {
    return _settings.replayGainVolumeLevel.replayGainOffsetDb;
  }

  Future<void> _applyReplayGainSettings({double? trackGainDb, mpv.Player? targetPlayer}) async {
    final player = targetPlayer ?? _player;
    if (player?.platform is! mpv.NativePlayer) {
      return;
    }

    final nativePlayer = player!.platform as dynamic;

    if (!_settings.enableReplayGain) {
      try {
        await nativePlayer.setProperty('af', '');
      } catch (_) {
        // Best effort clear.
      }
      return;
    }

    final replayGainOffsetDb = clampReplayGainDb(_replayGainVolumeOffsetDb);
    final replayGainFallbackDb = _settings.replayGainVolumeLevel.adjustedReplayGainDb(trackGainDb);

    try {
      await nativePlayer.setProperty('replaygain', 'track');
      await nativePlayer.setProperty('replaygain-clip', 'yes');
      await nativePlayer.setProperty('replaygain-fallback', '$replayGainFallbackDb');
      await nativePlayer.setProperty('replaygain-preamp', '$replayGainOffsetDb');
      await nativePlayer.setProperty('af', '');
      _replayGainFallbackLogged = false;
    } catch (error, stackTrace) {
      if (!_replayGainFallbackLogged) {
        log('ReplayGain unsupported by current mpv backend, falling back to loudnorm. $error\n$stackTrace');
      }
      _replayGainFallbackLogged = true;

      try {
        final gainFilter = ',volume=${replayGainFallbackDb}dB';
        await nativePlayer.setProperty('af', 'format=stereo,loudnorm$gainFilter');
      } catch (fallbackError, fallbackStackTrace) {
        log('Unable to set loudnorm fallback filter. $fallbackError\n$fallbackStackTrace');
      }
    }
  }

  Future<void> setStartPosition(Duration position) async {
    if (_player?.platform is mpv.NativePlayer) {
      await (_player?.platform as dynamic).setProperty(
        'start',
        '${position.inMilliseconds / 1000}',
      );
    }
  }

  void _finishedLoading() {
    _loadCompleter?.complete();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  @override
  Future<void> open(BuildContext context) async => Navigator.of(context, rootNavigator: true).push(VideoPlayerRoute());

  List<mpv.SubtitleTrack> get subTracks => _player?.state.tracks.subtitle ?? [];
  mpv.SubtitleTrack get subtitleTrack => _player?.state.track.subtitle ?? mpv.SubtitleTrack.no();

  List<mpv.AudioTrack> get audioTracks => _player?.state.tracks.audio ?? [];
  mpv.AudioTrack get audioTrack => _player?.state.track.audio ?? mpv.AudioTrack.no();

  void _startPlaybackFade(bool fadingIn) {
    final player = _player;
    if (player == null) return;

    _fadeTimer?.cancel();

    if (!_settings.enablePlayPauseFade || instantTransport) {
      if (fadingIn) {
        player.play();
      } else {
        player.pause();
      }
      return;
    }

    const stepMs = 16;
    final steps = playPauseFadeDuration.inMilliseconds ~/ stepMs;
    final stepSize = _preferredVolume / steps;

    if (fadingIn) player.play();

    // Counted as well as measured: the fade reads the volume back from the
    // player, and a pause must not depend on that reading ever reaching zero.
    var ticks = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: stepMs), (timer) {
      final p = _player;
      if (p == null) {
        timer.cancel();
        return;
      }
      final overdue = ++ticks > steps + 2;
      if (fadingIn) {
        final next = overdue ? _preferredVolume : (p.state.volume + stepSize).clamp(0.0, _preferredVolume);
        p.setVolume(next);
        if (next >= _preferredVolume) timer.cancel();
      } else {
        final next = overdue ? 0.0 : (p.state.volume - stepSize).clamp(0.0, 100.0);
        p.setVolume(next);
        if (next <= 0.0) {
          timer.cancel();
          p.pause();
        }
      }
    });
  }

  @override
  Future<void> pause() async {
    _musicPaused = true;
    setState(lastState.update(playing: false));
    unawaited(_audioSession?.setActive(false));
    _startPlaybackFade(false);
  }

  @override
  Future<void> play() async {
    _musicPaused = false;
    setState(lastState.update(playing: true));
    unawaited(_audioSession?.setActive(true));
    _startPlaybackFade(true);
  }

  @override
  Future<void> playOrPause() async {
    if ((_player?.state.playing ?? lastState.playing) == true) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _seekTarget = position;
    await _player?.seek(position);
    if (_musicPaused) _watchPausedBuffering();
  }

  /// Where the last seek was sent, until the next file.
  Duration? _seekTarget;

  /// Whether mpv has arrived where it was last sent. Asked straight after a
  /// seek it has often not begun on it yet and still says it is not seeking,
  /// from where it was: taken at its word, a phone's one-second seek was
  /// measured as none at all.
  Future<bool> _landed(dynamic native) async {
    if (await native.getProperty('seeking') as String != 'no') return false;
    final target = _seekTarget;
    if (target == null) return true;
    final at = double.tryParse(await native.getProperty('time-pos') as String);
    return at != null && (at - target.inMilliseconds / 1000).abs() < 1.0;
  }

  /// Wait until mpv, paused, has what it needs to start playing the moment
  /// it is told to: no seek under way and a stretch of the film in hand.
  ///
  /// Knowing a file's tracks is not that. A file opened part-way through
  /// still has to fetch and decode from there, and a phone told to play
  /// before it had showed a black picture for two seconds - while its group,
  /// which had been told it was ready, played on without it.
  Future<void> waitUntilPlayable({Duration timeout = const Duration(seconds: 4)}) async {
    final player = _player;
    if (player == null || player.platform is! mpv.NativePlayer) return;
    final native = player.platform as dynamic;
    final deadline = DateTime.now().add(timeout);
    // Timed into the log in its two halves, landing on the position and
    // having film in hand, so a slow start can be read rather than guessed at.
    final timer = Stopwatch()..start();
    int? landedAfter;
    var cached = 0.0;
    while (DateTime.now().isBefore(deadline) && identical(_player, player)) {
      try {
        final landed = await _landed(native);
        cached = double.tryParse(await native.getProperty('demuxer-cache-duration') as String) ?? 0;
        final idle = await native.getProperty('demuxer-cache-idle') as String;
        if (landed) {
          landedAfter ??= timer.elapsedMilliseconds;
          // Half a second in hand is enough to start on: on a connection
          // that can carry the film at all it is refilled faster than it
          // is played.
          if (cached >= 0.5 || (idle == 'yes' && cached > 0)) break;
          // And mpv does not always say what it has. Landed, it has decoded
          // the picture it stands on; a seek to the edge of what was cached
          // then read nothing in hand for four seconds, on a player that
          // started at once when told to, and its group stood still for it.
          if (timer.elapsedMilliseconds - landedAfter > 400) break;
        }
      } catch (_) {
        // Not there to be asked yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    _log.info('playable: on its position after ${landedAfter ?? '-'}ms, '
        '${cached.toStringAsFixed(1)}s in hand after ${timer.elapsedMilliseconds}ms');
  }

  Timer? _pausedBufferPoll;

  /// A paused mpv goes on reporting that it is buffering until its cache is
  /// full, long after the seek has landed and there is plenty to play - and
  /// a SyncPlay group waits on exactly that report before it resumes, two
  /// seconds on a phone for every seek. So while paused, mpv is asked what
  /// it actually has: the seek done and a stretch of the film in hand is
  /// ready, whatever the flag says.
  void _watchPausedBuffering() {
    _pausedBufferPoll?.cancel();
    final player = _player;
    if (player == null || player.platform is! mpv.NativePlayer) return;
    final native = player.platform as dynamic;
    var ticks = 0;
    var asking = false;
    _pausedBufferPoll = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (++ticks > 120 || !identical(_player, player) || !_musicPaused) {
        timer.cancel();
        return;
      }
      if (asking) return;
      if (!lastState.buffering) {
        // The seek may not have raised it yet.
        if (ticks > 6) timer.cancel();
        return;
      }
      asking = true;
      try {
        final landed = await _landed(native);
        final cached = double.tryParse(await native.getProperty('demuxer-cache-duration') as String) ?? 0;
        final idle = await native.getProperty('demuxer-cache-idle') as String;
        if (landed && (cached >= 0.5 || idle == 'yes') && timer.isActive && _musicPaused) {
          timer.cancel();
          setState(lastState.update(buffering: false));
        }
      } catch (_) {
        // Not answered this round; asked again on the next.
      } finally {
        asking = false;
      }
    });
  }

  // mpv parses tracks asynchronously after open(); at playback start the list is still empty, so a
  // positional lookup would miss and leave mpv on its own default pick. Wait (capped) for [index].
  // media_kit's web player never lists a file's tracks, so there it would only ever time out.
  Future<void> _awaitTrack(int index, int Function(mpv.Tracks) count) async {
    final player = _player;
    if (player == null || index < 0 || count(player.state.tracks) > index + 2) return;
    if (player.platform is! mpv.NativePlayer) return;
    await player.stream.tracks
        .firstWhere((tracks) => count(tracks) > index + 2)
        .timeout(const Duration(seconds: 5), onTimeout: () => player.state.tracks);
  }

  /// The id of the track mpv has selected for [property] (`aid`, `sid`), or
  /// null when it cannot be asked.
  Future<String?> _currentTrack(String property) async {
    final player = _player;
    if (player == null || player.platform is! mpv.NativePlayer) return null;
    try {
      return await (player.platform as dynamic).getProperty(property) as String;
    } catch (_) {
      return null;
    }
  }

  /// Bumped by every pick and every load, so a pick still waiting for a track
  /// list gives way to a newer pick of the same kind, or to the next file.
  int _audioPick = 0;
  int _subtitlePick = 0;

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    final wantedAudioStream = model ?? playbackModel.defaultAudioStream;
    if (wantedAudioStream == null) return -1;
    final pick = ++_audioPick;
    if (wantedAudioStream.index == AudioStreamModel.no().index) {
      _log.info('Audio off: the model asked for no track '
          '(model index ${playbackModel.mediaStreams?.defaultAudioStreamIndex})');
      await _player?.setAudioTrack(mpv.AudioTrack.no());
    } else {
      // The model's list carries an "off" entry first, so its position is one
      // ahead of the file's own tracks.
      final index = (playbackModel.audioStreams?.indexOf(wantedAudioStream) ?? -1) - 1;
      if (index < 0) {
        _log.warning('Audio ${wantedAudioStream.index} "${wantedAudioStream.displayTitle}" '
            'is not in the model\'s list; leaving the track alone');
        return wantedAudioStream.index;
      }
      await _awaitTrack(index, (tracks) => tracks.audio.length);
      if (pick != _audioPick) return wantedAudioStream.index;
      final internalTracks = audioTracks.getRange(2, audioTracks.length).toList();
      final audioTrack = internalTracks.elementAtOrNull(index);
      _log.info('Audio ${wantedAudioStream.index} "${wantedAudioStream.displayTitle}": '
          'mpv has ${internalTracks.length}, picked ${audioTrack == null ? 'nothing' : 'track $index'}');
      // Not when mpv is on it already, as it is for any file with one
      // audio track: choosing it again rebuilds the audio output, which on
      // a phone is half a second at the front of every start.
      if (audioTrack != null && await _currentTrack('aid') != audioTrack.id) {
        await _player?.setAudioTrack(audioTrack);
      }
    }
    return wantedAudioStream.index;
  }

  @override
  Future<void> setSpeed(double speed) async => _player?.setRate(speed);

  /// The tracks that came out of the media file, in its own order.
  ///
  /// The first two entries of mpv's list are its "auto" and "no" pseudo
  /// tracks. A subtitle file loaded during playback is not always appended
  /// after the file's own tracks: the one the server marks as default is
  /// loaded while mpv is still opening the stream, so it takes the first id
  /// and pushes every track of the file itself one place along. Loaded files
  /// are tagged on the way in and left out here, which is what makes counting
  /// the rest mean anything.
  List<mpv.SubtitleTrack> _containerSubTracks([List<mpv.SubtitleTrack>? all]) {
    final tracks = all ?? subTracks;
    if (tracks.length <= 2) return const <mpv.SubtitleTrack>[];
    return withoutLoadedSubtitles(tracks.sublist(2), (track) => track.title);
  }

  /// Bumped when a subtitle file changes on the server, so the next
  /// selection loads it again instead of finding the old copy by its tag.
  int _subtitleGeneration = 0;

  @override
  void forgetLoadedSubtitles() => _subtitleGeneration++;

  /// mpv's `sub-add` adds a track every time it is called, so selecting the
  /// same file twice would leave two of them behind. The tag it is given on
  /// the way in is what a second selection finds it by, and what keeps it out
  /// of [_containerSubTracks].
  Future<void> _selectExternalSubtitle(SubStreamModel stream) async {
    final tag = loadedSubtitleTag(stream, generation: _subtitleGeneration);
    final loaded = subTracks.firstWhereOrNull((track) => track.title == tag);
    if (loaded != null) {
      await _player?.setSubtitleTrack(loaded);
    } else {
      await _player?.setSubtitleTrack(mpv.SubtitleTrack.uri(stream.url!, title: tag));
    }
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (_player == null) return -1;
    final wantedSubtitle = model ?? playbackModel.defaultSubStream;
    final pick = ++_subtitlePick;
    if (wantedSubtitle == null || wantedSubtitle.index == SubStreamModel.no().index) {
      await _player?.setSubtitleTrack(mpv.SubtitleTrack.no());
      await _applyBitmapSubtitleRendering('');
      return -1;
    }
    _currentSubtitleCodec = wantedSubtitle.codec;

    final container = containerSubtitleStreams(playbackModel.subStreams);
    final containerIndex = containerIndexOf(container, wantedSubtitle);
    if (containerIndex >= 0) {
      await _awaitTrack(containerIndex, (tracks) => _containerSubTracks(tracks.subtitle).length + 2);
    }
    if (pick != _subtitlePick) return wantedSubtitle.index;

    final tracks = _containerSubTracks();
    final choice = resolveSubtitlePick(
      streams: playbackModel.subStreams,
      wanted: wantedSubtitle,
      playerTrackCount: tracks.length,
    );

    _log.info('Subtitle ${wantedSubtitle.index} "${wantedSubtitle.displayTitle}" (${wantedSubtitle.codec}'
        '${wantedSubtitle.isExternal ? ', file' : ''}): ${container.length} in the container, '
        'mpv has ${tracks.length}, picked $choice');
    _logTrackLists(container, tracks);

    // Counting is the fallback, not the answer: mpv lists a file's subtitle
    // tracks in its own order, so a stream is looked up by what both sides
    // know about it first.
    int? trackIndex = choice.trackIndex;
    if (trackIndex != null) {
      final matched = matchSubtitleTrack(
        container: container,
        wanted: wantedSubtitle,
        tracks: tracks
            .map((track) => PlayerSubtitleTrack(language: track.language ?? '', title: track.title ?? ''))
            .toList(),
      );
      if (matched != null && matched != trackIndex) {
        _log.info('Subtitle #${wantedSubtitle.index} is mpv track $matched, not $trackIndex');
        trackIndex = matched;
      }
    }

    final track = trackIndex == null ? null : tracks.elementAtOrNull(trackIndex);
    if (track != null) {
      await _player?.setSubtitleTrack(track);
    } else if (choice.loadFile) {
      await _selectExternalSubtitle(wantedSubtitle);
    } else {
      _log.warning('Subtitle ${wantedSubtitle.index} has no track in the stream and no file to load');
    }
    // What mpv ended up on decides who draws the subtitle, not what was asked
    // for: mpv draws a picture subtitle itself while the app draws text, so a
    // text track with picture rendering switched on is drawn twice, once by
    // each.
    await _applyBitmapSubtitleRendering(track?.codec ?? wantedSubtitle.codec);
    unawaited(_logSettledSubtitle(wantedSubtitle));
    return wantedSubtitle.index;
  }

  /// The server's list and mpv's, side by side.
  ///
  /// Both are counted the same way, so a track that sits in a different place
  /// in one than in the other is what a picker entry playing somebody else's
  /// lines looks like from here.
  void _logTrackLists(List<SubStreamModel> container, List<mpv.SubtitleTrack> tracks) {
    if (_loggedTrackLists || tracks.isEmpty) return;
    _loggedTrackLists = true;
    _log.info('server subtitles: ${container.mapIndexed(
          (i, stream) => '$i=#${stream.index} ${stream.language}/${stream.codec} "${stream.title}"',
        ).join(' | ')}');
    _log.info('mpv subtitles: ${tracks.mapIndexed(
          (i, track) => '$i=id${track.id} ${track.language}/${track.codec} "${track.title}"',
        ).join(' | ')}');
  }

  bool _loggedTrackLists = false;

  /// The size the next video is expected to have, from the server's
  /// metadata, for [loadVideo] to make the video output ready ahead of it.
  (int, int)? videoSizeHint;

  /// On Android the video surface is made at the video's size. Made once the
  /// file shows its size, it restarted the decoder - a second seek and decode
  /// on a resume, about a second and a half on a phone before the picture.
  Future<void> _prepareVideoSurface() async {
    final hint = videoSizeHint;
    videoSizeHint = null;
    if (hint == null || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final (width, height) = hint;
    if (width <= 0 || height <= 0) return;
    try {
      final platform = await _controller?.platform.future.timeout(const Duration(seconds: 2));
      // Dynamic while a media_kit_video without prepareVideoSize can still
      // be the one built against: there it is skipped, as before.
      await (platform as dynamic)?.prepareVideoSize(width, height);
    } on NoSuchMethodError {
      // An older media_kit_video: the surface is made when the video shows its size.
    } catch (e) {
      log('video surface could not be prepared: $e');
    }
  }

  /// What mpv settled on, read back from mpv itself a moment after the switch.
  ///
  /// Tells a track that was never switched to apart from one that was, and
  /// says whether mpv is drawing the subtitle as well as the app is.
  Future<void> _logSettledSubtitle(SubStreamModel wanted) async {
    final platform = _player?.platform;
    if (platform is! mpv.NativePlayer) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final properties = <String, String>{};
      for (final name in const [
        'sid',
        'secondary-sid',
        'sub-visibility',
        'current-tracks/sub/lang',
        'current-tracks/sub/codec',
        'current-tracks/sub/title',
        'current-tracks/sub/external',
      ]) {
        properties[name] = await getMpvProperty(platform, name);
      }
      _log.info('mpv settled for #${wanted.index} "${wanted.displayTitle}": '
          '${properties.entries.map((e) => '${e.key}=${e.value}').join(', ')}');
    } catch (error) {
      _log.warning('Could not read back mpv subtitle state: $error');
    }
  }

  /// Lets mpv draw a bitmap subtitle itself.
  ///
  /// Without libass, subtitles are drawn by the app as text from what mpv
  /// decodes, and mpv's own rendering is off. A bitmap track decodes to no
  /// text at all, so a film whose only subtitle is a Blu-ray PGS track was
  /// played with the track selected and nothing on screen. mpv can draw those
  /// without libass; it is switched on for them and off again for text, which
  /// would otherwise be drawn twice.
  Future<void> _applyBitmapSubtitleRendering(String codec) async {
    if (_settings.useLibass) return;
    final platform = _player?.platform;
    if (platform is! mpv.NativePlayer) return;
    final bitmap = isBitmapSubtitleCodec(codec);
    _pictureSubtitle = bitmap;
    _pictureSubtitleCodec = codec.toLowerCase();
    try {
      await setMpvProperty(platform, 'sub-visibility', bitmap ? 'yes' : 'no');
    } catch (e) {
      log('sub-visibility could not be set: $e');
    }
    if (bitmap) await _applyPictureSubtitleLook();
  }

  /// What can be asked of a subtitle that is a picture: where it sits, and
  /// how hard its edges are.
  ///
  /// The rest of what the subtitle settings carry - the font, the size, the
  /// outline, the background - was drawn into the picture by whoever made the
  /// disc and cannot be reached from here.
  ///
  /// [SubtitleText] puts the app's own text a fraction of the frame up from
  /// the bottom, while mpv counts `sub-pos` down from the top with 100 at the
  /// bottom edge, so the same fraction lands both in the same place.
  Future<void> _applyPictureSubtitleLook({int? subPos}) async {
    if (_settings.useLibass) return;
    final platform = _player?.platform;
    if (platform is! mpv.NativePlayer) return;
    final position = subPos ?? SubtitlePositionCalculator.mpvSubtitlePosition(_subtitleSettings.verticalOffset);
    final blur = _lowResolutionSubtitleCodecs.contains(_pictureSubtitleCodec) ? _pictureSubtitleBlur : 0.0;
    if (position == _appliedSubtitlePosition && blur == _appliedSubtitleBlur) return;
    try {
      if (position != _appliedSubtitlePosition) {
        await setMpvProperty(platform, 'sub-pos', '$position');
        _appliedSubtitlePosition = position;
      }
      if (blur != _appliedSubtitleBlur) {
        await setMpvProperty(platform, 'sub-gauss', blur.toStringAsFixed(1));
        _appliedSubtitleBlur = blur;
      }
    } catch (e) {
      log('picture subtitle look could not be set: $e');
    }
  }

  /// The settings can be changed while a subtitle is on screen - the offset
  /// slider is dragged over the film it moves - so a picture one is redrawn
  /// as they arrive, the way the app redraws its own text.
  @override
  void applySubtitleSettings(SubtitleSettingsModel settings) {
    _subtitleSettings = settings;
    if (_pictureSubtitle) unawaited(_applyPictureSubtitleLook());
  }

  @override
  Future<void> addToPlaylist(String url) async => _player?.add(mpv.Media(url));

  @override
  Future<void> removeFromPlaylist(int index) async => _player?.remove(index);

  @override
  Future<void> playerNext() async => _player?.next();

  @override
  Future<void> playerPrevious() async => _player?.previous();

  @override
  Stream<int> get playlistIndexStream => _player?.stream.playlist.map((p) => p.index) ?? const Stream<int>.empty();

  @override
  Future<void> stop() async {
    unawaited(_audioSession?.setActive(false));
    _stopHdr();
    return _player?.stop();
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    return _player?.screenshot(format: "image/png", includeLibassSubtitles: true);
  }

  @override
  Widget? videoWidget(
    Key key,
    BoxFit fit, {
    FilterQuality filterQuality = FilterQuality.low,
  }) =>
      _controller == null
          ? null
          : Video(
              key: key,
              controller: _controller!,
              wakelock: false,
              // What a video does when the app leaves the screen is decided
              // in MediaControlsWrapper. Left on, this paused the player
              // underneath everything that keeps track of it.
              pauseUponEnteringBackgroundMode: false,
              fill: Colors.transparent,
              fit: fit,
              filterQuality: filterQuality,
              subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
              controls: NoVideoControls,
            );

  @override
  Widget? subtitles(
    bool showOverlay, {
    GlobalKey? controlsKey,
  }) =>
      _controller != null
          ? _VideoSubtitles(
              controller: _controller!,
              showOverlay: showOverlay,
              controlsKey: controlsKey,
              currentSubtitleCodec: _currentSubtitleCodec,
            )
          : null;

  @override
  Future<void> setVolume(double volume) async {
    // A volume set in the middle of a pause's fade ends the fade, and the
    // pause was the last thing the fade did: it never reached the player,
    // which played on at full volume while everything above it said paused.
    // On a phone every change of the system volume lands here - the volume
    // keys, and the hand-over when Bluetooth headphones drop away.
    final fadingOut = (_fadeTimer?.isActive ?? false) && _musicPaused;
    _fadeTimer?.cancel();
    _preferredVolume = volume.clamp(0.0, 100.0);
    if (fadingOut) await _player?.pause();
    await _player?.setVolume(_preferredVolume);
  }

  @override
  Future<void> loop(bool loop) async {
    if (loop && _onCompleted == null) {
      _onCompleted = _player?.stream.completed.listen((completed) {
        if (completed) {
          _player?.play();
        }
      });
    } else {
      _onCompleted?.cancel();
    }
  }
}

class _VideoSubtitles extends ConsumerStatefulWidget {
  final VideoController controller;
  final bool showOverlay;
  final GlobalKey? controlsKey;
  final String currentSubtitleCodec;

  const _VideoSubtitles({
    required this.controller,
    this.showOverlay = false,
    this.controlsKey,
    this.currentSubtitleCodec = '',
  });

  @override
  _VideoSubtitlesState createState() => _VideoSubtitlesState();
}

class _VideoSubtitlesState extends ConsumerState<_VideoSubtitles> {
  late List<String> subtitle;
  String _cachedSubtitleText = '';
  List<String>? _lastSubtitleList;
  StreamSubscription<List<String>>? subscription;

  double? _cachedMenuHeight;

  @override
  void initState() {
    super.initState();
    subtitle = widget.controller.player.state.subtitle;
    subscription = widget.controller.player.stream.subtitle.listen((value) {
      if (mounted) {
        setState(() {
          subtitle = value;
          _lastSubtitleList = null;
        });
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _measureMenuHeight();

    final settings = ref.watch(subtitleSettingsProvider);
    final padding = MediaQuery.paddingOf(context);

    if (!const ListEquality().equals(subtitle, _lastSubtitleList)) {
      _lastSubtitleList = List<String>.from(subtitle);
      _cachedSubtitleText = subtitle.where((line) => line.trim().isNotEmpty).map((line) => line.trim()).join('\n');
    }

    final text = _cachedSubtitleText;

    final bool isLibassEnabled = widget.controller.player.platform?.configuration.libass ?? false;

    // A picture subtitle is drawn by mpv rather than here, at the position
    // setting (see [LibMPV.applySubtitleSettings]), and it stays there while
    // the controls are up. mpv moves a picture by the whole shift wherever on
    // the frame it sits, and where it sits cannot be read back - lifted for
    // the controls, it jumped far higher than they reached.
    if (!isLibassEnabled && isBitmapSubtitleCodec(widget.currentSubtitleCodec)) {
      return const SizedBox.shrink();
    }

    if (isLibassEnabled) {
      // On desktop (Linux/Windows/macOS), mpv burns ALL subtitle formats into the video when libass is enabled.
      // On mobile (Android/iOS), only ASS/SSA subs are burned in by libass; other formats need the Flutter overlay.
      final bool isDesktop = defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS;
      if (isDesktop) {
        return const SizedBox.shrink();
      }
      final currentSubCodec = widget.currentSubtitleCodec.toLowerCase();
      final bool isAssSubtitle = currentSubCodec.contains('ass') || currentSubCodec.contains('ssa');
      if (isAssSubtitle || text.isEmpty) {
        return const SizedBox.shrink();
      }
    } else if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return SubtitleText(
      subModel: settings,
      padding: padding,
      offset: settings.verticalOffset,
      controlsHeight: _controlsHeight(context),
      text: text,
    );
  }

  /// How tall the controls stand while they are up, 0 while away. Before
  /// they were first measured, a sixth of the screen is assumed.
  double _controlsHeight(BuildContext context) {
    if (!widget.showOverlay) return 0;
    return _cachedMenuHeight ?? MediaQuery.sizeOf(context).height * 0.15;
  }

  void _measureMenuHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controlsKey == null) return;

      final newHeight = SubtitlePositionCalculator.controlsReach(context, widget.controlsKey);

      if (newHeight != _cachedMenuHeight && newHeight != null) {
        setState(() {
          _cachedMenuHeight = newHeight;
        });
      }
    });
  }
}

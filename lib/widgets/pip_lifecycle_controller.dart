import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/pip_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/widgets/shared/pip_next_up_strip.dart';
import 'package:chudder/wrappers/pip_manager.dart';

class PipLifecycleController extends ConsumerStatefulWidget {
  const PipLifecycleController({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PipLifecycleController> createState() => _PipLifecycleControllerState();
}

class _PipLifecycleControllerState extends ConsumerState<PipLifecycleController> with WidgetsBindingObserver {
  /// Android-only bridge for the PiP window's RemoteActions (play/pause and
  /// next episode). We push {hasNext, playing} down; taps come back up as
  /// "action" calls and are routed through the same user paths every other
  /// control uses.
  static const _pipActionsChannel = MethodChannel('uk.jentejan.chudder/pip_actions');

  bool get _androidPipActions => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (pipPlatformSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyCurrent());
    }
    if (_androidPipActions) {
      WidgetsBinding.instance.addObserver(this);
      _pipActionsChannel.setMethodCallHandler((call) async {
        if (call.method == 'pipMode') {
          final inPip = call.arguments == true;
          ref.read(pipManagerProvider).reportState(inPip);
          if (!inPip) _setLeaving(false);
          return null;
        }
        if (call.method == 'userLeaving') {
          _onUserLeaving();
          return null;
        }
        if (call.method != 'action') return null;
        switch (call.arguments as String?) {
          case 'playPause':
            await ref.read(videoPlayerProvider.notifier).userPlayOrPause();
          case 'next':
            await ref.read(videoPlayerProvider).loadNextVideo();
          case 'stop':
            await ref.read(videoPlayerProvider).stop();
        }
        return null;
      });
    }
  }

  Timer? _leavingTimeout;

  /// Home was pressed. With a minimized video about to be taken into PiP the
  /// video goes over the whole app now, a frame or two ahead of the system
  /// shrinking it, so the window is the picture from the start instead of
  /// the page with a tiny player in its corner.
  void _onUserLeaving() {
    if (!mounted) return;
    final minimized = ref.read(mediaPlaybackProvider).state == VideoPlayerState.minimized;
    final autoEnter = ref.read(videoPlayerSettingsProvider).enablePictureInPicture;
    final isAudioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? true;
    if (!minimized || !autoEnter || isAudioPlayback) return;
    _setLeaving(true);
    // The hint also comes when the app itself opens something over it (a
    // share sheet, a permission prompt), and then no PiP follows.
    _leavingTimeout = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (!(ref.read(pipStateProvider).asData?.value ?? false)) _setLeaving(false);
    });
  }

  void _setLeaving(bool value) {
    _leavingTimeout?.cancel();
    _leavingTimeout = null;
    if (!mounted || ref.read(pipLeavingProvider) == value) return;
    ref.read(pipLeavingProvider.notifier).state = value;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back in the app, or gone from the screen without a window: either way
    // the leaving is over.
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.hidden) _setLeaving(false);
  }

  @override
  void dispose() {
    _leavingTimeout?.cancel();
    if (_androidPipActions) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _pushPipActionState() async {
    if (!_androidPipActions) return;
    try {
      await _pipActionsChannel.invokeMethod('updateState', {
        'hasNext': ref.read(playBackModel)?.nextVideo != null,
        'playing': ref.read(mediaPlaybackProvider).playing,
      });
    } catch (_) {
      // Older builds without the native side; nothing to do.
    }
  }

  void _applyCurrent() {
    if (!mounted) return;
    final state = ref.read(mediaPlaybackProvider).state;
    final autoEnter = ref.read(videoPlayerSettingsProvider).enablePictureInPicture;
    final isAudioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? false;
    _apply(state, autoEnter, isAudioPlayback: isAudioPlayback);
  }

  void _apply(
    VideoPlayerState state,
    bool autoEnter, {
    required bool isAudioPlayback,
  }) {
    final manager = ref.read(pipManagerProvider);
    final autoEnterAllowed = autoEnter && !isAudioPlayback;
    if (state == VideoPlayerState.fullScreen || state == VideoPlayerState.minimized) {
      // The window takes the video's real shape - a scope movie letterboxed
      // inside a hardcoded 16:9 postage stamp wasted half the pixels.
      // Android clamps PiP ratios to [1/2.39, 2.39]; stay inside that.
      final stream = ref.read(playBackModel)?.mediaStreams?.videoStreams.firstOrNull;
      var ratio = (stream != null && stream.width > 0 && stream.height > 0) ? stream.width / stream.height : 16 / 9;
      ratio = ratio.clamp(1 / 2.39, 2.39);

      // The hint makes the OS morph the window out of the video's on-screen
      // rectangle (the centered AR-fit within the physical screen) instead
      // of jump-cutting.
      Rect? hint;
      final view = View.maybeOf(context);
      if (view != null) {
        final screen = view.physicalSize;
        if (screen.width > 0 && screen.height > 0) {
          final screenRatio = screen.width / screen.height;
          final fitted = screenRatio > ratio
              ? Size(screen.height * ratio, screen.height)
              : Size(screen.width, screen.width / ratio);
          hint = Rect.fromCenter(
            center: Offset(screen.width / 2, screen.height / 2),
            width: fitted.width,
            height: fitted.height,
          );
        }
      }

      manager.enable(
        aspectWidth: (ratio * 1000).roundToDouble(),
        aspectHeight: 1000,
        autoEnter: autoEnterAllowed,
        sourceRectHint: hint,
      );
    } else {
      manager.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!pipPlatformSupported) {
      return widget.child;
    }
    ref.listen<VideoPlayerState>(
      mediaPlaybackProvider.select((v) => v.state),
      (previous, next) {
        if (previous == next) return;
        final autoEnter = ref.read(videoPlayerSettingsProvider).enablePictureInPicture;
        final isAudioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? false;
        _apply(next, autoEnter, isAudioPlayback: isAudioPlayback);
      },
    );
    ref.listen<bool>(
      videoPlayerSettingsProvider.select((v) => v.enablePictureInPicture),
      (previous, next) {
        if (previous == next) return;
        final state = ref.read(mediaPlaybackProvider).state;
        final isAudioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? false;
        _apply(state, next, isAudioPlayback: isAudioPlayback);
      },
    );
    ref.listen<bool>(
      playBackModel.select((value) => value?.isAudioPlayback ?? false),
      (previous, next) {
        if (previous == next) return;
        final state = ref.read(mediaPlaybackProvider).state;
        final autoEnter = ref.read(videoPlayerSettingsProvider).enablePictureInPicture;
        _apply(state, autoEnter, isAudioPlayback: next);
      },
    );
    ref.listen<String?>(
      playBackModel.select((v) => v?.item.id),
      (previous, next) {
        if (previous != next) _applyCurrent();
      },
    );
    if (_androidPipActions) {
      ref.listen<String?>(
        playBackModel.select((v) => v?.nextVideo?.id),
        (previous, next) {
          if (previous != next) _pushPipActionState();
        },
      );
      ref.listen<bool>(
        mediaPlaybackProvider.select((v) => v.playing),
        (previous, next) {
          if (previous != next) _pushPipActionState();
        },
      );
    }

    final inPip = ref.watch(pipStateProvider).asData?.value ?? false;
    final leaving = ref.watch(pipLeavingProvider);
    final state = ref.watch(mediaPlaybackProvider.select((v) => v.state));
    final showVideo = (inPip || leaving) && state == VideoPlayerState.minimized;
    // Over the app rather than instead of it: taking the app out of the tree
    // threw away every page's state, to be built again on the way back.
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (showVideo) const _PipVideo(),
      ],
    );
  }
}

/// The playing video and nothing else, filling the app while it is - or is
/// about to be - a PiP window with the player minimized.
class _PipVideo extends ConsumerWidget {
  const _PipVideo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(videoPlayerProvider);
    final video = player.videoWidget(const ValueKey('pip_minimized_video'), BoxFit.contain);
    final subtitle = player.subtitleWidget(false);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video != null) video,
          if (subtitle != null) subtitle,
          const PipNextUpStrip(),
        ],
      ),
    );
  }
}

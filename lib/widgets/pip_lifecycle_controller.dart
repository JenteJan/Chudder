import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/pip_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/widgets/shared/pip_next_up_strip.dart';
import 'package:fladder/wrappers/pip_manager.dart';

class PipLifecycleController extends ConsumerStatefulWidget {
  const PipLifecycleController({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PipLifecycleController> createState() => _PipLifecycleControllerState();
}

class _PipLifecycleControllerState extends ConsumerState<PipLifecycleController> {
  /// Android-only bridge for the PiP window's RemoteActions (play/pause and
  /// next episode). We push {hasNext, playing} down; taps come back up as
  /// "action" calls and are routed through the same user paths every other
  /// control uses.
  static const _pipActionsChannel = MethodChannel('nl.jknaapen.fladder/pip_actions');

  bool get _androidPipActions => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (pipPlatformSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyCurrent());
    }
    if (_androidPipActions) {
      _pipActionsChannel.setMethodCallHandler((call) async {
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
    _apply(state, autoEnter);
  }

  void _apply(VideoPlayerState state, bool autoEnter) {
    final manager = ref.read(pipManagerProvider);
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
        autoEnter: autoEnter,
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
        _apply(next, autoEnter);
      },
    );
    ref.listen<bool>(
      videoPlayerSettingsProvider.select((v) => v.enablePictureInPicture),
      (previous, next) {
        if (previous == next) return;
        final state = ref.read(mediaPlaybackProvider).state;
        _apply(state, next);
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
    final state = ref.watch(mediaPlaybackProvider.select((v) => v.state));
    if (inPip && state == VideoPlayerState.minimized) {
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
    return widget.child;
  }
}

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/account_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/player_controls_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/player_shortcuts.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/input_handler.dart';
import 'package:fladder/util/localization_helper.dart';

/// Controller to trigger the seek indicator from outside (e.g., double-tap).
/// The parent widget creates this controller and passes it to [VideoPlayerSeekIndicator],
/// then calls [seekBack] or [seekForward] to trigger the indicator.
class SeekIndicatorController {
  VoidCallback? _seekBack;
  VoidCallback? _seekForward;

  void seekBack() => _seekBack?.call();
  void seekForward() => _seekForward?.call();
}

class VideoPlayerSeekIndicator extends ConsumerStatefulWidget {
  final SeekIndicatorController? controller;

  const VideoPlayerSeekIndicator({this.controller, super.key});
  @override
  ConsumerState<ConsumerStatefulWidget> createState() => VideoPlayerSeekIndicatorState();
}

class VideoPlayerSeekIndicatorState extends ConsumerState<VideoPlayerSeekIndicator> {
  RestartableTimer? timer;

  bool visible = false;
  int seekPosition = 0;

  @override
  void initState() {
    super.initState();
    widget.controller?._seekBack = seekBack;
    widget.controller?._seekForward = seekForward;
  }

  void onSeekEnd() {
    setState(() {
      visible = false;
    });
    timer?.cancel();
    timer = null;
    ref.read(pendingSeekSecondsProvider.notifier).state = 0;
    if (seekPosition == 0) return;
    final mediaPlayback = ref.read(mediaPlaybackProvider);
    final newPosition = (mediaPlayback.position.inSeconds + seekPosition).clamp(0, mediaPlayback.duration.inSeconds);
    ref.read(videoPlayerProvider).seek(Duration(seconds: newPosition));
  }

  void onSeekStart(int value) {
    if (timer == null) {
      timer = RestartableTimer(const Duration(milliseconds: 500), () => onSeekEnd());
      setState(() {
        seekPosition = 0;
      });
    } else {
      timer?.reset();
    }
    setState(() {
      visible = true;
      seekPosition += value;
    });
    ref.read(pendingSeekSecondsProvider.notifier).state = seekPosition;
  }

  @override
  void dispose() {
    // The controls outlive this widget; a total left behind would leave the
    // scrubber parked somewhere the player never went.
    final pending = ref.read(pendingSeekSecondsProvider.notifier);
    Future.microtask(() => pending.state = 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isForward = seekPosition > 0;
    final displayValue = seekPosition.abs();

    // Seeking by arrow belongs to a player with nothing on top of it. This
    // handler listens to the raw keyboard, which runs before focus is
    // consulted at all - so with the controls up and a remote moving between
    // them, it took the presses meant for navigating and seeked instead.
    // Also while the next-episode card is up: its buttons are navigated with
    // the same arrows this would otherwise turn into a seek.
    final standAside = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad &&
        (ref.watch(playerControlsVisibleProvider) || ref.watch(nextUpVisibleProvider));

    return InputHandler<VideoHotKeys>(
      autoFocus: false,
      listenRawKeyboard: true,
      keyMap: ref
          .watch(videoPlayerSettingsProvider.select((value) => value.currentShortcuts))
          .withoutPlainArrows(when: standAside),
      keyMapResult: (result) => _onKey(result),
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 500),
          opacity: (visible && seekPosition != 0) ? 1 : 0,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 12,
                  children: [
                    Icon(
                      isForward ? IconsaxPlusLinear.forward : IconsaxPlusLinear.backward,
                      color: Colors.white,
                    ),
                    Text(
                      "$displayValue ${context.localized.seconds(displayValue)}",
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void seekBack() {
    final seconds = -ref.read(userProvider
        .select((value) => (value?.userSettings?.skipBackDuration ?? UserSettings().skipBackDuration).inSeconds));
    onSeekStart(seconds);
  }

  void seekForward() {
    final seconds = ref.read(userProvider
        .select((value) => (value?.userSettings?.skipForwardDuration ?? UserSettings().skipForwardDuration).inSeconds));
    onSeekStart(seconds);
  }

  bool _onKey(VideoHotKeys value) {
    switch (value) {
      case VideoHotKeys.seekForward:
        seekForward();
        return true;
      case VideoHotKeys.seekBack:
        seekBack();
        return true;
      default:
        return false;
    }
  }
}

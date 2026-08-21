import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/components/video_volume_slider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/full_screen_player_launcher.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/player_bar_shared.dart';

/// Where the user dragged the window to (top-left corner, logical pixels).
/// Null until they move it — it then starts in the bottom-right corner. Kept
/// in a provider so the position survives the scaffold rebuilding around it.
final floatingVideoWindowOffsetProvider = StateProvider<Offset?>((ref) => null);

double floatingVideoWindowWidth(BuildContext context) => switch (AdaptiveLayout.viewSizeOf(context)) {
      ViewSize.phone => 200,
      ViewSize.tablet => 260,
      _ => 320,
    };

/// Whether the minimized player shows as the small draggable window instead of
/// the bottom bar. Only when there is a picture worth keeping an eye on: audio,
/// items without a video stream and casting keep the bar, which has the seek
/// bar and queue controls those need. A d-pad can't drag a window around
/// either, so TV keeps the bar as well.
bool useFloatingVideoWindow(BuildContext context, WidgetRef ref) {
  if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) return false;
  if (ref.watch(castProvider.select((value) => value.isConnected))) return false;
  if (ref.watch(playBackModel.select((value) => value?.item)) is AudioModel) return false;
  return ref.watch(playBackModel.select((value) => value?.mediaStreams?.videoStreams.isNotEmpty == true));
}

/// The minimized video player: a small window floating over the app that can be
/// dragged anywhere, showing play/pause, stop and mute when hovered.
class FloatingVideoWindow extends ConsumerStatefulWidget {
  const FloatingVideoWindow({super.key});

  @override
  ConsumerState<FloatingVideoWindow> createState() => _FloatingVideoWindowState();
}

class _FloatingVideoWindowState extends ConsumerState<FloatingVideoWindow> with FullScreenPlayerLauncher {
  static const _margin = 12.0;
  static const _ratio = 16 / 9;

  bool _showControls = false;
  Timer? _hideControls;

  @override
  void dispose() {
    _hideControls?.cancel();
    super.dispose();
  }

  void _setControlsVisible(bool value, {bool autoHide = false}) {
    _hideControls?.cancel();
    // Without a mouse there is no "exit" to hide on, so a tap shows the
    // controls and they fade out again on their own.
    if (value && autoHide) {
      _hideControls = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
    if (_showControls != value) {
      setState(() => _showControls = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final pointer = AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(floatingVideoWindowWidth(context), constraints.maxWidth - _margin * 2);
        final height = width / _ratio;

        final minX = padding.left + _margin;
        final maxX = max(minX, constraints.maxWidth - padding.right - _margin - width);
        final minY = padding.top + _margin;
        final maxY = max(minY, constraints.maxHeight - padding.bottom - _margin - height);

        Offset clamp(Offset offset) => Offset(
              offset.dx.clamp(minX, maxX),
              offset.dy.clamp(minY, maxY),
            );

        final stored = ref.watch(floatingVideoWindowOffsetProvider);
        // Start in the bottom-right corner, roughly where the bar used to sit,
        // and re-clamp on every build so resizing the app can't strand the
        // window off screen.
        final offset = clamp(stored ?? Offset(maxX, maxY));

        return Stack(
          children: [
            Positioned(
              left: offset.dx,
              top: offset.dy,
              width: width,
              height: height,
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                onEnter: (_) => _setControlsVisible(true),
                onExit: (_) => _setControlsVisible(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) =>
                      ref.read(floatingVideoWindowOffsetProvider.notifier).state = clamp(offset + details.delta),
                  onTap: () => pointer ? openFullScreenPlayer() : _setControlsVisible(!_showControls, autoHide: true),
                  onDoubleTap: pointer ? null : openFullScreenPlayer,
                  child: Material(
                    elevation: 12,
                    color: Colors.black,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: FladderTheme.defaultShape.borderRadius,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Hero(
                          tag: videoPlayerHeroTag,
                          child: ref.read(videoPlayerProvider).videoWidget(
                                    const ValueKey("floating_window_video"),
                                    BoxFit.contain,
                                  ) ??
                              const SizedBox.shrink(),
                        ),
                        IgnorePointer(
                          ignoring: !_showControls,
                          child: AnimatedOpacity(
                            opacity: _showControls ? 1 : 0,
                            duration: const Duration(milliseconds: 125),
                            child: _FloatingVideoWindowControls(onExpand: openFullScreenPlayer),
                          ),
                        ),
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: _FloatingVideoWindowProgress(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingVideoWindowControls extends ConsumerWidget {
  const _FloatingVideoWindowControls({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(mediaPlaybackProvider.select((value) => value.playing));
    final volume = ref.watch(videoPlayerSettingsProvider.select((value) => value.volume));

    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: IconButton(
              tooltip: "Expand player",
              iconSize: 18,
              color: Colors.white,
              visualDensity: VisualDensity.compact,
              onPressed: onExpand,
              icon: const Icon(Icons.open_in_full_rounded),
            ),
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  color: Colors.white,
                  onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
                  icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                IconButton(
                  color: Colors.white,
                  onPressed: () => ref.read(videoPlayerProvider).stop(),
                  icon: const Icon(IconsaxPlusBold.stop),
                ),
                IconButton(
                  color: Colors.white,
                  onPressed: () => ref.read(videoPlayerSettingsProvider.notifier).toggleMute(),
                  icon: Icon(volumeIcon(volume)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingVideoWindowProgress extends ConsumerWidget {
  const _FloatingVideoWindowProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(mediaPlaybackProvider.select((value) => (
          position: value.position,
          duration: value.duration,
        )));
    return LinearProgressIndicator(
      minHeight: 3,
      backgroundColor: Colors.black.withValues(alpha: 0.25),
      color: Theme.of(context).colorScheme.primary,
      value: playback.duration.inMilliseconds > 0
          ? (playback.position.inMilliseconds / playback.duration.inMilliseconds).clamp(0, 1)
          : 0,
    );
  }
}

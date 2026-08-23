import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// Keeps the window draggable by its title-bar strip even while a modal
/// (bottom sheet, dialog, cast picker) is open.
///
/// The in-page [DragToMoveArea] lives inside routed screens, so every modal
/// barrier sits on top of it and dragging dies with the modal — which feels
/// broken for a Windows app. This mounts a transparent strip ABOVE the
/// navigator (via the MaterialApp builder), so it outranks every route and
/// barrier. It claims only pan gestures: taps fall through to whatever is
/// underneath (window buttons, app bar, modal content), so unlike
/// DragToMoveArea there's no double-tap handler delaying clicks.
class WindowDragStrip extends ConsumerWidget {
  const WindowDragStrip({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return child;
    final platform = defaultTargetPlatform;
    // Matches the platforms whose DefaultTitleBar drags via window_manager.
    if (platform != TargetPlatform.windows && platform != TargetPlatform.linux) return child;
    final arguments = ref.watch(argumentsStateProvider);
    if (arguments.htpcMode || arguments.leanBackMode) return child;
    // Fullscreen video draws edge to edge with no window chrome — the strip
    // would steal pans from the player's top controls.
    final fullScreen = ref.watch(mediaPlaybackProvider.select((value) => value.fullScreen));

    return Stack(
      children: [
        child,
        if (!fullScreen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: defaultTitleBarHeight,
            child: Row(
              children: [
                // Main strip: claims the gesture on pointer-down, so window
                // dragging beats overlays that also grab horizontal drags —
                // an open navigation drawer's drag-to-close otherwise wins
                // the arena and slides the drawer instead of the window.
                // Nothing interactive lives under this span of the title bar.
                Expanded(
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    gestures: {
                      _EagerPanGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
                        () => _EagerPanGestureRecognizer(),
                        (recognizer) => recognizer.onStart = (_) => windowManager.startDragging(),
                      ),
                    },
                  ),
                ),
                // Window-button zone (minimize/maximize/close): keep the
                // polite pan that lets clicks pass through.
                SizedBox(
                  width: 160,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => windowManager.startDragging(),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A pan recognizer that wins the gesture arena the moment the pointer goes
/// down, instead of waiting to out-drag competing recognizers. Used for the
/// title-bar strip, where a drag must always mean "move the window" even when
/// an open drawer or sheet has its own full-screen drag recognizers.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

import 'package:flutter/foundation.dart';
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
            ),
          ),
      ],
    );
  }
}

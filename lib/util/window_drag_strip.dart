import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';

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
                const Expanded(child: _DraggableCaptionSpan()),
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

/// The span of the title bar that moves the window, and maximises it - or puts
/// it back - on a double click, the way every other Windows window does.
///
/// The second click is counted here rather than left to a
/// [DoubleTapGestureRecognizer]: the pan recogniser below accepts the gesture
/// the moment the pointer goes down, which settles the arena and rejects every
/// other recogniser in it before a second tap could ever arrive. That is why
/// the double click did nothing, even though the [DragToMoveArea] underneath
/// this strip has handled it all along - the strip is above the navigator and
/// swallowed it first. A [Listener] takes no part in the arena, so it sees both
/// presses without taking the drag away from anything.
class _DraggableCaptionSpan extends StatefulWidget {
  const _DraggableCaptionSpan();

  @override
  State<_DraggableCaptionSpan> createState() => _DraggableCaptionSpanState();
}

class _DraggableCaptionSpanState extends State<_DraggableCaptionSpan> {
  Duration? _lastDownAt;
  Offset? _lastDownPosition;

  /// A double click has been seen and is waiting for the button to come up.
  bool _toggleOnRelease = false;

  void _handlePointerDown(PointerDownEvent event) {
    // The left button only. Double right-click on a caption bar is the system
    // menu's business, and it only worked at all because the pan recogniser
    // ignores anything but the primary button - so nothing grabbed the window
    // and both presses arrived here.
    if (event.buttons != kPrimaryButton) {
      _lastDownAt = null;
      _lastDownPosition = null;
      return;
    }

    final previousAt = _lastDownAt;
    final previousPosition = _lastDownPosition;
    _lastDownAt = event.timeStamp;
    _lastDownPosition = event.position;

    if (previousAt == null || previousPosition == null) return;
    // Two presses close together in both time and place: anything slower or
    // further apart is two separate clicks on the bar.
    if (event.timeStamp - previousAt > kDoubleTapTimeout) return;
    if ((event.position - previousPosition).distance > kDoubleTapSlop) return;

    // Cleared so a third press starts counting again rather than pairing with
    // this one and toggling straight back.
    _lastDownAt = null;
    _lastDownPosition = null;
    // On the release, not here. Windows will not change a window's state while
    // the button that asked is still down and the pointer captured: the call
    // was made and simply did nothing, which is why the title bar's own button
    // - which acts on release - always worked and this never did.
    _toggleOnRelease = true;
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (!_toggleOnRelease) return;
    _toggleOnRelease = false;
    unawaited(_toggleMaximized());
  }

  Future<void> _toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Translucent, or this never sees a pointer at all. The gesture detector
      // below is itself translucent and childless: such a box puts itself in
      // the hit-test result but answers `false` to the hit test, so a listener
      // that defers to its child - the default - concludes nothing was hit,
      // stays out of the chain, and its onPointerDown is never called. That is
      // why the double click did nothing here whatever it was wired to.
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (_) => _toggleOnRelease = false,
      child: RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _EagerPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
            () => _EagerPanGestureRecognizer(),
            (recognizer) {
              // Only once the pointer has actually moved, and once per gesture.
              //
              // This used to hand the window over in onStart, which - the
              // recogniser having accepted the arena on pointer-down - is the
              // press itself, before any movement. `startDragging` puts Windows
              // into its own modal move loop for the caption, and while that
              // loop owns the mouse the second press of a double click is not
              // delivered here at all: the window moved fine and double click
              // to maximise never fired. A click that does not move now stays
              // an ordinary click.
              recognizer.onStart = (details) {
                recognizer.draggingWindow = false;
                recognizer.dragOrigin = details.globalPosition;
              };
              recognizer.onUpdate = (details) {
                // A double click is already under way: this press ends in a
                // maximise, so the window must not also be picked up and moved.
                // Letting it meant the second press started a caption drag for
                // the few pixels a hand moves between pressing and releasing,
                // and the window lurched before it snapped - which the title
                // bar's own button never does, having no drag in it at all.
                if (_toggleOnRelease) return;
                if (recognizer.draggingWindow) return;
                final origin = recognizer.dragOrigin;
                // Far enough to mean it. Without a threshold the pixel or two
                // of jitter in an ordinary double click was movement enough:
                // the window went into Windows' own caption move loop on the
                // first press, and the second was delivered to that loop
                // instead of to us, so the double click never completed. This
                // is why it worked with the right button, which the pan
                // recogniser ignores altogether.
                if (origin != null && (details.globalPosition - origin).distance < _windowDragSlop) return;
                recognizer.draggingWindow = true;
                windowManager.startDragging();
              };
            },
          ),
        },
      ),
    );
  }
}

/// How far the pointer has to travel before a press on the title bar becomes a
/// drag of the window.
///
/// Comfortably past the jitter of a click - Windows itself uses about four
/// pixels - and well under the [kDoubleTapSlop] the second press of a double
/// click is allowed, so the two cannot be mistaken for one another.
const _windowDragSlop = 6.0;

/// A pan recognizer that wins the gesture arena the moment the pointer goes
/// down, instead of waiting to out-drag competing recognizers. Used for the
/// title-bar strip, where a drag must always mean "move the window" even when
/// an open drawer or sheet has its own full-screen drag recognizers.
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  /// Whether this gesture has already handed the window to Windows, so the
  /// move loop is entered once rather than on every update.
  bool draggingWindow = false;

  /// Where the press started, to measure how far it has come.
  Offset? dragOrigin;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

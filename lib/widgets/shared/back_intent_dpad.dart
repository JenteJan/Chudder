import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'package:auto_route/auto_route.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_helper.dart';

class BackIntentDpad extends StatelessWidget {
  final Widget child;

  /// How to go back. Defaults to popping whatever router this sits in; the
  /// app-wide instance passes the root router, because it is mounted above
  /// any router scope and has none in its context.
  final VoidCallback? onBack;

  /// Going forward, where there is a history to go forward through. Only the
  /// app-wide instance supplies this: a router cannot redo a pop on its own,
  /// so the routes that were left have to be remembered separately.
  final VoidCallback? onForward;

  const BackIntentDpad({required this.child, this.onBack, this.onForward, super.key});

  /// The pointer whose back-click has already been answered.
  ///
  /// These nest - the player's sits inside the app-wide one - and a single
  /// click reaches every listener on the way out, which would pop once per
  /// listener. Flutter dispatches innermost first, so the deepest one claims
  /// the pointer and the rest stand down.
  static int? _handledPointer;

  @override
  Widget build(BuildContext context) {
    if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch) {
      return child;
    }
    return Listener(
      onPointerDown: (event) {
        final isBack = (event.buttons & kBackMouseButton) != 0;
        final isForward = (event.buttons & kForwardMouseButton) != 0;
        if (!isBack && !isForward) return;
        if (isEditableTextFocused()) return;

        // Claim the pointer only when this instance will actually act on it.
        // The nested instances handle back but not forward, and claiming a
        // forward click just to drop it swallowed the press before the
        // app-wide handler - the only one that knows the history - could see
        // it.
        if (isForward) {
          final forward = onForward;
          if (forward == null) return;
          if (_handledPointer == event.pointer) return;
          _handledPointer = event.pointer;
          forward();
          return;
        }

        if (_handledPointer == event.pointer) return;
        _handledPointer = event.pointer;
        _goBack(context);
      },
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }

          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            if (isEditableTextFocused()) {
              return KeyEventResult.ignored;
            } else {
              _goBack(context);
              return KeyEventResult.handled;
            }
        }

          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }

  void _goBack(BuildContext context) {
    final back = onBack;
    if (back != null) {
      back();
      return;
    }
    context.maybePop();
  }
}

class BackIntent extends Intent {
  const BackIntent();
}

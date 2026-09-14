import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chudder/screens/shared/flat_button.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';

final acceptKeys = {
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.accept,
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.space,
};

class FocusProvider extends InheritedWidget {
  final bool hasFocus;
  final bool autoFocus;

  const FocusProvider({
    super.key,
    this.hasFocus = false,
    this.autoFocus = false,
    required super.child,
  });

  static bool of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<FocusProvider>();
    return widget?.hasFocus ?? false;
  }

  static bool autoFocusOf(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<FocusProvider>();
    return widget?.autoFocus ?? false;
  }

  @override
  bool updateShouldNotify(FocusProvider oldWidget) {
    return oldWidget.hasFocus != hasFocus;
  }
}

class FocusButton extends StatefulWidget {
  final Widget? child;
  final bool autoFocus;
  final FocusNode? focusNode;
  final List<Widget> focusedOverlays;
  final List<Widget> overlays;
  final Function(bool value)? onHover;
  final Function()? onTap;
  final Function()? onLongPress;
  final Function(TapDownDetails)? onSecondaryTapDown;
  final bool darkOverlay;
  final bool visualizeFocus;
  final bool forceFocusOutline;
  final Function(bool focus)? onFocusChanged;
  final BorderRadiusGeometry? borderRadius;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  const FocusButton({
    this.child,
    this.autoFocus = false,
    this.focusNode,
    this.focusedOverlays = const [],
    this.overlays = const [],
    this.onHover,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.darkOverlay = true,
    this.visualizeFocus = true,
    this.forceFocusOutline = false,
    this.onFocusChanged,
    this.borderRadius,
    this.onKeyEvent,
    super.key,
  });

  @override
  State<FocusButton> createState() => FocusButtonState();
}

class FocusButtonState extends State<FocusButton> {
  late FocusNode focusNode = widget.focusNode ?? FocusNode();
  ValueNotifier<bool> onHover = ValueNotifier(false);
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  bool _keyDownActive = false;

  static const Duration _kLongPressTimeout = Duration(milliseconds: 500);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!node.hasFocus) return KeyEventResult.ignored;

    if (widget.onKeyEvent != null) {
      final result = widget.onKeyEvent!(node, event);
      if (result == KeyEventResult.handled) return result;
    }

    if (acceptKeys.contains(event.logicalKey)) {
      if (event is KeyDownEvent) {
        if (_keyDownActive) return KeyEventResult.ignored;
        _keyDownActive = true;
        _startLongPressTimer();
      } else if (event is KeyUpEvent) {
        if (!_keyDownActive) return KeyEventResult.ignored;
        if (_longPressTriggered) {
          _resetKeyState();

          return KeyEventResult.ignored;
        }
        _cancelLongPressTimer();
        _keyDownActive = false;
        widget.onTap?.call();
      }
    }
    return KeyEventResult.ignored;
  }

  void _startLongPressTimer() {
    _longPressTriggered = false;
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_kLongPressTimeout, () {
      _longPressTriggered = true;
      widget.onLongPress?.call();
      _resetKeyState();
    });
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _resetKeyState() {
    _cancelLongPressTimer();
    _keyDownActive = false;
    _longPressTriggered = false;
  }

  /// Whether there is anything to press - the same condition [build] uses to
  /// decide whether this is a button at all.
  static bool _interactive(FocusButton widget) =>
      widget.onTap != null || widget.onLongPress != null || widget.onSecondaryTapDown != null;

  @override
  void didUpdateWidget(FocusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A button given nothing to do returns its bare child, taking the Focus
    // widget below out of the tree: the pad moves on and no onFocusChange
    // arrives to say the ring is no longer ours. Left set, it is drawn again
    // the moment the button can be pressed once more - on a control the
    // selection left long ago. Callers that null onTap while they work (a
    // request in flight, an entry that is already the selected one) all did
    // this.
    if (!_interactive(widget) && _interactive(oldWidget)) {
      onHover.value = false;
    }
  }

  @override
  void dispose() {
    _resetKeyState();
    if (lastMainFocus == focusNode) {
      lastMainFocus = null;
    }
    if (widget.focusNode == null) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.autoFocus && !focusNode.hasFocus) {
        focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // The ring follows a notifier that only changes when onFocusChange runs,
    // and that runs on a *change*. A button can end up holding the selection
    // without one ever arriving for the state it is now in - focus restored
    // onto it while the cards around it were being rebuilt - and then the node
    // has the selection while the ring is still switched off. Nothing shows
    // until the next press makes a real change, which is late and looks like
    // the selection appearing from nowhere. Only ever switched on here: off is
    // for the notifier's other job, the mouse leaving.
    if (focusNode.hasFocus && !onHover.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusNode.hasFocus && !onHover.value) onHover.value = true;
      });
    }

    if (widget.onTap == null && widget.onLongPress == null && widget.onSecondaryTapDown == null) {
      return widget.child ?? const SizedBox.shrink();
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (event) => onHover.value = true,
      onExit: (event) {
        onHover.value = false;
        if (widget.onHover != null) {
          widget.onHover?.call(false);
        }
      },
      onHover: widget.onHover != null ? (event) => widget.onHover?.call(true) : null,
      child: Focus(
        focusNode: focusNode,
        autofocus: widget.autoFocus,
        canRequestFocus: widget.onTap != null || widget.onLongPress != null || widget.onSecondaryTapDown != null,
        skipTraversal: widget.onTap == null && widget.onLongPress == null && widget.onSecondaryTapDown != null,
        onFocusChange: (value) {
          widget.onFocusChanged?.call(value);
          if (value) {
            lastMainFocus = focusNode;
          }
          onHover.value = value;
        },
        onKeyEvent: _handleKey,
        child: ExcludeFocus(
          child: ValueListenableBuilder(
            valueListenable: onHover,
            builder: (context, value, child) {
              final hasFocus = widget.forceFocusOutline ? true : value;
              final radius = widget.borderRadius ?? FladderTheme.smallShape.borderRadius;
              // The one ring every selected thing wears - see [FocusRing] -
              // over a wash of the same colour, so the mark reads on artwork
              // that happens to be the ring's own tone at the edge.
              return FocusRing(
                visible: hasFocus && widget.visualizeFocus,
                borderRadius: radius,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(borderRadius: radius),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: radius,
                    color: widget.darkOverlay && widget.visualizeFocus
                        ? focusRingColor(Theme.of(context).colorScheme).withValues(alpha: hasFocus ? 0.12 : 0.0)
                        : null,
                  ),
                  child: FlatButton(
                    onTap: widget.onTap,
                    onSecondaryTapDown: widget.onSecondaryTapDown,
                    onLongPress: widget.onLongPress,
                    child: widget.child,
                    overlays: [
                      if (widget.overlays.isNotEmpty) ...widget.overlays,
                      if (widget.focusedOverlays.isNotEmpty)
                        Positioned.fill(
                          child: _FocusedOverlays(
                            visible: hasFocus,
                            children: widget.focusedOverlays,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// What a button shows only while it is hovered or selected, faded in and out.
///
/// Built only while it can be seen. It used to sit in every button at opacity
/// 0, and opacity 0 skips painting but not building or layout: every poster on
/// a page built its play and options buttons, tooltip and all, for the one card
/// the pointer might be over.
class _FocusedOverlays extends StatefulWidget {
  const _FocusedOverlays({required this.visible, required this.children});

  final bool visible;
  final List<Widget> children;

  @override
  State<_FocusedOverlays> createState() => _FocusedOverlaysState();
}

class _FocusedOverlaysState extends State<_FocusedOverlays> with SingleTickerProviderStateMixin {
  late final AnimationController _opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_statusChanged);

  void _statusChanged(AnimationStatus status) {
    // Faded all the way out: stop building the overlays until they are wanted.
    if (status.isDismissed) setState(() {});
  }

  @override
  void didUpdateWidget(_FocusedOverlays oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _opacity.forward();
    } else {
      _opacity.reverse();
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _opacity.isDismissed) return const SizedBox.shrink();
    return FadeTransition(
      opacity: _opacity,
      child: Stack(children: widget.children),
    );
  }
}

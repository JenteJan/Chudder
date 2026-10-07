import 'dart:async';

import 'package:flutter/foundation.dart';
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
    final radius = widget.borderRadius ?? FladderTheme.smallShape.borderRadius;
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
        // The selection is this button's and nothing inside it takes it: not
        // the ink well, not the controls that fade in over a hovered card.
        descendantsAreFocusable: false,
        onFocusChange: (value) {
          widget.onFocusChanged?.call(value);
          if (value) {
            lastMainFocus = focusNode;
          }
          onHover.value = value;
        },
        onKeyEvent: _handleKey,
        // Everything under here is built once and left alone: being hovered
        // or selected repaints the mark over the button, and only the
        // controls that appear with it listen for more than that. A grid
        // builds a row of these every few frames of a fling, and almost none
        // of them is ever hovered or selected.
        child: _FocusHighlight(
          highlight: onHover,
          forced: widget.forceFocusOutline,
          ring: widget.visualizeFocus,
          wash: widget.darkOverlay && widget.visualizeFocus,
          borderRadius: radius,
          // The same rounded cut the container used to make from its
          // decoration, as a rounded rectangle rather than a path. A
          // container clips to its decoration's outline as a general
          // path, which the renderer has to turn into geometry for
          // every card on screen; a rounded rectangle is a shape it
          // has its own quicker way to clip to.
          child: ClipRRect(
            borderRadius: radius,
            clipBehavior: Clip.hardEdge,
            child: FlatButton(
              onTap: widget.onTap,
              onSecondaryTapDown: widget.onSecondaryTapDown,
              onLongPress: widget.onLongPress,
              // Never the ink well's to hold, so never its ring to draw.
              focusRing: false,
              child: widget.child,
              overlays: [
                if (widget.overlays.isNotEmpty) ...widget.overlays,
                if (widget.focusedOverlays.isNotEmpty)
                  Positioned.fill(
                    child: ValueListenableBuilder(
                      valueListenable: onHover,
                      builder: (context, value, child) => _FocusedOverlays(
                        visible: widget.forceFocusOutline || value,
                        children: widget.focusedOverlays,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark of a hovered or selected button: the ring every selected thing
/// wears - see [FocusRing] - over a wash of the same colour, so the mark reads
/// on artwork that happens to be the ring's own tone at the edge.
///
/// Painted over the child, and nothing but painted. It used to be a ring
/// widget around an animated container, each with an animation of its own
/// that every button set up and almost none ever ran; here the one animation
/// is made the first time there is something to show.
class _FocusHighlight extends StatefulWidget {
  const _FocusHighlight({
    required this.highlight,
    required this.forced,
    required this.ring,
    required this.wash,
    required this.borderRadius,
    required this.child,
  });

  final ValueListenable<bool> highlight;

  /// Shown whatever [highlight] says.
  final bool forced;
  final bool ring;
  final bool wash;
  final BorderRadiusGeometry borderRadius;
  final Widget child;

  @override
  State<_FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<_FocusHighlight> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _shown;

  bool get _visible => widget.forced || widget.highlight.value;

  @override
  void initState() {
    super.initState();
    widget.highlight.addListener(_changed);
    // Already marked when it is first built: there, not fading in.
    if (_visible) _start(1);
  }

  @override
  void didUpdateWidget(_FocusHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlight != widget.highlight) {
      oldWidget.highlight.removeListener(_changed);
      widget.highlight.addListener(_changed);
    }
    _animate();
  }

  void _start(double value) {
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200), value: value);
    _controller = controller;
    _shown = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
  }

  void _changed() {
    if (_controller == null) {
      if (!_visible) return;
      setState(() => _start(0));
    }
    _animate();
  }

  void _animate() {
    final controller = _controller;
    if (controller == null) {
      if (_visible) _start(1);
      return;
    }
    if (_visible) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.highlight.removeListener(_changed);
    _shown?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null || !(widget.ring || widget.wash)) {
      return CustomPaint(child: widget.child);
    }
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      foregroundPainter: _FocusHighlightPainter(
        shown: shown,
        radius: widget.borderRadius.resolve(Directionality.of(context)),
        ring: widget.ring ? focusRingColor(colors) : null,
        wash: widget.wash ? focusRingColor(colors) : null,
        edge: focusRingEdgeColor(colors),
      ),
      child: widget.child,
    );
  }
}

class _FocusHighlightPainter extends CustomPainter {
  _FocusHighlightPainter({
    required this.shown,
    required this.radius,
    required this.ring,
    required this.wash,
    required this.edge,
  }) : super(repaint: shown);

  final Animation<double> shown;
  final BorderRadius radius;
  final Color? ring;
  final Color? wash;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = shown.value;
    if (opacity == 0) return;
    final wash = this.wash;
    if (wash != null) {
      canvas.drawRRect(radius.toRRect(Offset.zero & size), Paint()..color = wash.withValues(alpha: 0.12 * opacity));
    }
    final ring = this.ring;
    if (ring != null) {
      FocusRingPainter(opacity: opacity, radius: radius, ring: ring, edge: edge).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(_FocusHighlightPainter old) =>
      old.shown != shown || old.radius != radius || old.ring != ring || old.wash != wash || old.edge != edge;
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
    return AnimatedBuilder(
      animation: _opacity,
      child: FadeTransition(
        opacity: _opacity,
        child: Stack(children: widget.children),
      ),
      // A control that cannot be seen cannot be pressed. These are built the
      // moment the pointer arrives and lie over the card, and a fade does not
      // stop a press reaching what is under it - so moving onto a poster and
      // pressing it straight away hit a play button that was not there yet
      // instead of opening the card, and only behaved once the quarter second
      // of fading was over.
      builder: (context, child) => IgnorePointer(ignoring: !_opacity.isCompleted, child: child),
    );
  }
}

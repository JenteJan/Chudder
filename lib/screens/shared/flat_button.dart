import 'package:flutter/material.dart';

import 'package:fladder/theme.dart';
import 'package:fladder/widgets/shared/focus_ring.dart';

class FlatButton extends StatefulWidget {
  final Widget? child;
  final bool autoFocus;
  final FocusNode? focusNode;
  final Function(bool value)? onFocusChange;
  final Function()? onTap;
  final Function()? onLongPress;
  final Function()? onDoubleTap;
  final Function(TapDownDetails details)? onSecondaryTapDown;
  final BorderRadius? borderRadiusGeometry;
  final Color? splashColor;
  final double elevation;
  final bool showFeedback;
  final Clip clipBehavior;
  final List<Widget> overlays;
  const FlatButton({
    this.child,
    this.onFocusChange,
    this.focusNode,
    this.autoFocus = false,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.borderRadiusGeometry,
    this.splashColor,
    this.elevation = 0,
    this.showFeedback = true,
    this.clipBehavior = Clip.none,
    this.overlays = const [],
    super.key,
  });

  @override
  State<FlatButton> createState() => _FlatButtonState();
}

class _FlatButtonState extends State<FlatButton> {
  /// Whether the ink well itself holds the selection. Inside a [FocusButton]
  /// it never does - that widget keeps the focus node and excludes this one -
  /// so the ring here only ever shows on a bare button used on its own: a
  /// synced episode, the user's avatar, a chapter.
  bool _focused = false;

  bool get _hasInteraction => widget.onTap != null || widget.onLongPress != null || widget.onDoubleTap != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasInteraction) {
      return widget.child ?? Container();
    }
    final radius = widget.borderRadiusGeometry ?? BorderRadius.circular(10);
    return FocusRing(
      visible: _focused,
      borderRadius: radius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child ?? Container(),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              clipBehavior: widget.clipBehavior,
              borderRadius: widget.borderRadiusGeometry ?? FladderTheme.defaultShape.borderRadius,
              elevation: 0,
              child: InkWell(
                autofocus: widget.autoFocus,
                focusNode: widget.focusNode,
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onFocusChange: (value) {
                  if (value != _focused) setState(() => _focused = value);
                  widget.onFocusChange?.call(value);
                },
                onDoubleTap: widget.onDoubleTap,
                onSecondaryTapDown: widget.onSecondaryTapDown,
                borderRadius: radius,
                // The ring is the mark; Material's wash under it is not wanted.
                focusColor: Colors.transparent,
                splashColor: widget.splashColor ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                hoverColor: widget.showFeedback ? null : Colors.transparent,
                splashFactory: InkSparkle.splashFactory,
              ),
            ),
          ),
          ...widget.overlays,
        ],
      ),
    );
  }
}

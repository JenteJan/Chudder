import 'dart:async';

import 'package:flutter/material.dart';

/// A label that appears beside its child while the pointer is over it.
///
/// The tooltip is placed by [CompositedTransformFollower], which anchors it to
/// the child without anybody having to know how big it is. It used to be
/// measured instead: every tooltip kept a second, live copy of its content
/// parked a thousand pixels off screen, built and laid out on every single
/// rebuild for the sole purpose of reading its size. The navigation bar wraps
/// every one of its entries in one of these, so the bar was built twice over,
/// forever, to show a label that appears on hover.
class CustomTooltip extends StatefulWidget {
  final Widget child;
  final Widget? tooltipContent;
  final double offset;
  final TooltipPosition position;
  final Duration showDelay;

  const CustomTooltip({
    required this.child,
    required this.tooltipContent,
    this.offset = 12,
    this.position = TooltipPosition.top,
    this.showDelay = const Duration(milliseconds: 125),
    super.key,
  });

  @override
  CustomTooltipState createState() => CustomTooltipState();
}

enum TooltipPosition { top, bottom, left, right }

class CustomTooltipState extends State<CustomTooltip> {
  OverlayEntry? _overlayEntry;
  Timer? _tooltipTimer;
  final LayerLink _link = LayerLink();

  void _showTooltip() {
    _tooltipTimer?.cancel();

    _tooltipTimer = Timer(widget.showDelay, () {
      if (!mounted || _overlayEntry != null) return;
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    });
  }

  void _hideTooltip() {
    _tooltipTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Which corner of the tooltip meets which corner of the child, and how far
  /// off it sits.
  (Alignment target, Alignment follower, Offset offset) get _anchors => switch (widget.position) {
        TooltipPosition.top => (Alignment.topCenter, Alignment.bottomCenter, Offset(0, -widget.offset)),
        TooltipPosition.bottom => (Alignment.bottomCenter, Alignment.topCenter, Offset(0, widget.offset)),
        TooltipPosition.left => (Alignment.centerLeft, Alignment.centerRight, Offset(-widget.offset, 0)),
        TooltipPosition.right => (Alignment.centerRight, Alignment.centerLeft, Offset(widget.offset, 0)),
      };

  OverlayEntry _createOverlayEntry() {
    final (target, follower, offset) = _anchors;

    return OverlayEntry(
      builder: (context) => Positioned(
        // Where the follower actually lands is decided by the link; this only
        // gives it somewhere to start from.
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: target,
          followerAnchor: follower,
          offset: offset,
          child: Material(
            color: Colors.transparent,
            child: widget.tooltipContent,
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant CustomTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A tooltip on screen while its content changes would otherwise keep
    // showing the old one until the pointer left.
    if (widget.tooltipContent == null && _overlayEntry != null) {
      _hideTooltip();
    } else {
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooltipContent == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => _showTooltip(),
      onExit: (_) => _hideTooltip(),
      child: CompositedTransformTarget(
        link: _link,
        child: widget.child,
      ),
    );
  }

  @override
  void dispose() {
    _tooltipTimer?.cancel();
    _hideTooltip(); // Ensure the tooltip is hidden on dispose
    super.dispose();
  }
}

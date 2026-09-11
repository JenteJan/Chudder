import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

/// A small panel that hangs directly under whatever opens it.
///
/// A filter chip used to open a sheet at the far edge of the screen, or a
/// dialog in the middle of it - nowhere near the chip, and one tap to open,
/// one to change, one to close. This puts the panel right under the chip,
/// opens it on hover when there is a pointer, and closes it again when the
/// pointer has wandered off both the chip and the panel. Nothing else on the
/// page is covered or blocked while it is open: a tap elsewhere both closes
/// it and lands where it was aimed.
///
/// On a remote the same panel opens on select, takes the selection into
/// itself, and gives it back to the chip when back is pressed or the
/// selection walks out of the panel.
class AnchoredPopover extends StatefulWidget {
  /// The chip. Handed a way to open and close, and whether it is open now.
  final Widget Function(BuildContext context, AnchoredPopoverController controller) anchorBuilder;

  /// What hangs under it.
  final Widget Function(BuildContext context, AnchoredPopoverController controller) popoverBuilder;

  /// Whether resting the pointer on the anchor opens it.
  final bool openOnHover;

  final double width;
  final double maxHeight;

  /// Called after the panel has gone, whichever way.
  final VoidCallback? onClosed;

  const AnchoredPopover({
    required this.anchorBuilder,
    required this.popoverBuilder,
    this.openOnHover = true,
    this.width = 300,
    this.maxHeight = 420,
    this.onClosed,
    super.key,
  });

  @override
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

/// Opens and closes an [AnchoredPopover] from the outside.
class AnchoredPopoverController {
  final _AnchoredPopoverState _state;
  AnchoredPopoverController._(this._state);

  bool get isOpen => _state._portal.isShowing;
  void open() => _state._open();
  void close() => _state._close();
  void toggle() => isOpen ? close() : open();
}

final Set<LogicalKeyboardKey> _closers = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.browserBack,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.gameButtonB,
};

class _AnchoredPopoverState extends State<AnchoredPopover> with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnchoredPopoverController _controller = AnchoredPopoverController._(this);
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));

  /// One group per popover, so a tap on its own anchor is never "outside".
  final Object _tapGroup = Object();

  /// The panel's own scope, so a remote's selection can be moved into it and
  /// noticed leaving it.
  final FocusScopeNode _panelScope = FocusScopeNode(debugLabel: 'popover');

  /// Where the selection was when the panel opened, to give it back to.
  FocusNode? _returnFocus;

  Timer? _openTimer;
  Timer? _closeTimer;
  bool _anchorHovered = false;
  bool _panelHovered = false;

  /// Where the panel hangs from, decided when it opens: under the anchor and
  /// flush with its left edge unless that would run off the screen.
  Alignment _targetAnchor = Alignment.bottomLeft;
  Alignment _followerAnchor = Alignment.topLeft;
  double _panelMaxHeight = 420;

  @override
  void dispose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _fade.dispose();
    _panelScope.dispose();
    super.dispose();
  }

  void _place() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);

    final roomBelow = screen.height - padding.bottom - (origin.dy + size.height) - 12;
    final roomAbove = origin.dy - padding.top - 12;
    final below = roomBelow >= 200 || roomBelow >= roomAbove;
    _panelMaxHeight = (below ? roomBelow : roomAbove).clamp(120.0, widget.maxHeight);

    final fitsRight = origin.dx + widget.width <= screen.width - 8;
    _targetAnchor = below
        ? (fitsRight ? Alignment.bottomLeft : Alignment.bottomRight)
        : (fitsRight ? Alignment.topLeft : Alignment.topRight);
    _followerAnchor = below
        ? (fitsRight ? Alignment.topLeft : Alignment.topRight)
        : (fitsRight ? Alignment.bottomLeft : Alignment.bottomRight);
  }

  bool get _isDPad => AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

  void _open() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (_portal.isShowing) return;
    _place();
    setState(() => _portal.show());
    _fade.forward(from: 0);
    if (_isDPad) {
      // Into the panel: the chip keeps nothing to do with the selection
      // while its panel is up.
      _returnFocus = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_portal.isShowing) return;
        _panelScope.requestFocus();
        _panelScope.nextFocus();
      });
    }
  }

  void _close() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (!_portal.isShowing) return;
    final returnTo = _returnFocus;
    _returnFocus = null;
    if (returnTo != null && returnTo.canRequestFocus && returnTo.context?.mounted == true) {
      returnTo.requestFocus();
    }
    _fade.reverse().whenComplete(() {
      if (!mounted || _fade.status != AnimationStatus.dismissed) return;
      setState(() => _portal.hide());
      widget.onClosed?.call();
    });
  }

  void _hoverChanged() {
    if (!widget.openOnHover) return;
    final hovered = _anchorHovered || _panelHovered;
    if (hovered) {
      _closeTimer?.cancel();
      if (!_portal.isShowing && _anchorHovered) {
        _openTimer ??= Timer(const Duration(milliseconds: 220), () {
          _openTimer = null;
          if (mounted && _anchorHovered) _open();
        });
      }
    } else {
      _openTimer?.cancel();
      _openTimer = null;
      _closeTimer?.cancel();
      _closeTimer = Timer(const Duration(milliseconds: 320), () {
        if (mounted && !_anchorHovered && !_panelHovered) _close();
      });
    }
  }

  /// Back, escape or backspace inside the panel closes it.
  KeyEventResult _onPanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_closers.contains(event.logicalKey)) return KeyEventResult.ignored;
    _close();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: _targetAnchor,
              followerAnchor: _followerAnchor,
              offset: Offset(0, _targetAnchor.y > 0 ? 6 : -6),
              child: Align(
                alignment: _followerAnchor,
                child: MouseRegion(
                  onEnter: (_) {
                    _panelHovered = true;
                    _hoverChanged();
                  },
                  onExit: (_) {
                    _panelHovered = false;
                    _hoverChanged();
                  },
                  child: TapRegion(
                    groupId: _tapGroup,
                    onTapOutside: (_) => _close(),
                    child: FadeTransition(
                      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
                      child: FocusScope(
                        node: _panelScope,
                        onKeyEvent: _onPanelKey,
                        onFocusChange: (focused) {
                          // A selection that has walked out of the panel on a
                          // remote is done with it.
                          if (!focused && _isDPad && _portal.isShowing) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !_panelScope.hasFocus) _close();
                            });
                          }
                        },
                        child: Material(
                          elevation: 8,
                          shadowColor: Colors.black.withValues(alpha: 0.5),
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: widget.width,
                              minWidth: widget.width,
                              maxHeight: _panelMaxHeight,
                            ),
                            child: widget.popoverBuilder(context, _controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _tapGroup,
          child: MouseRegion(
            onEnter: (_) {
              _anchorHovered = true;
              _hoverChanged();
            },
            onExit: (_) {
              _anchorHovered = false;
              _hoverChanged();
            },
            child: widget.anchorBuilder(context, _controller),
          ),
        ),
      ),
    );
  }
}

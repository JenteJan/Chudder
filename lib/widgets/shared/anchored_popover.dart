import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';

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
///
/// On a touch screen it opens on tap and stays inside the screen and above
/// the keyboard. There the tap that closes it is taken by the panel rather
/// than passed on - a finger has no hover to see what it is about to hit -
/// and the system back gesture closes it before it leaves the page.
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

  /// Opens the panel, or closes it - unless hovering just opened it, when
  /// the press is left alone. A pointer that rests on a chip opens its panel
  /// before the click that was meant to open it lands, and that click was
  /// closing the panel again the moment it appeared.
  void toggle() {
    if (!isOpen) return open();
    if (_state._settlingAfterHover) return;
    close();
  }
}

/// How long after a hover has opened the panel a press on the chip is taken
/// as the press that meant to open it, and does nothing.
const Duration _hoverSettle = Duration(seconds: 2);

final Set<LogicalKeyboardKey> _closers = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.goBack,
  LogicalKeyboardKey.browserBack,
  LogicalKeyboardKey.backspace,
  LogicalKeyboardKey.gameButtonB,
};

class _AnchoredPopoverState extends State<AnchoredPopover> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  late final AnchoredPopoverController _controller = AnchoredPopoverController._(this);
  // Made up front: left lazy, a panel that never opened made its controller
  // in dispose(), where looking up the ticker mode throws.
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  }

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

  /// Set while a panel that hovering opened is too new for a press on the
  /// chip to mean anything; never set after an open by press.
  bool _settlingAfterHover = false;
  Timer? _settleTimer;

  /// Whether the panel hangs below the anchor or above it, decided when it
  /// opens so it does not jump sides while open.
  bool _below = true;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _settleTimer?.cancel();
    _fade.dispose();
    _panelScope.dispose();
    super.dispose();
  }

  /// The keyboard coming or going changes the room the panel has.
  @override
  void didChangeMetrics() {
    if (mounted && _portal.isShowing) setState(() {});
  }

  Rect? _anchorRect() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Room above and below the anchor, clear of the bars and the keyboard.
  /// The keyboard is read from the view itself: a [Scaffold] hides it from
  /// the [MediaQuery] its body sees.
  ({double above, double below}) _room(Rect anchor) {
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final keyboard = MediaQueryData.fromView(View.of(context)).viewInsets.bottom;
    return (
      above: anchor.top - padding.top - 12,
      below: screen.height - math.max(padding.bottom, keyboard) - anchor.bottom - 12,
    );
  }

  bool get _isDPad => AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

  void _open({bool fromHover = false}) {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (_portal.isShowing) return;
    _settleTimer?.cancel();
    _settlingAfterHover = fromHover;
    if (fromHover) _settleTimer = Timer(_hoverSettle, () => _settlingAfterHover = false);
    final anchor = _anchorRect();
    if (anchor != null) {
      final room = _room(anchor);
      _below = room.below >= 200 || room.below >= room.above;
    }
    WidgetsBinding.instance.addObserver(this);
    setState(() => _portal.show());
    _fade.forward(from: 0);
    if (_isDPad) {
      // Into the panel: the chip keeps nothing to do with the selection
      // while its panel is up.
      _returnFocus = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_portal.isShowing) return;
        final initial = _initialControl();
        if (initial != null) {
          initial.requestFocus();
          // Brought into view: the current choice can sit below the fold of
          // a long list, and a selection the panel opened on but did not
          // show looked like no selection at all.
          final initialContext = initial.context;
          if (initialContext != null) Scrollable.ensureVisible(initialContext, alignment: 0.5);
        } else {
          _panelScope.requestFocus();
          _panelScope.nextFocus();
        }
      });
    }
  }

  void _close() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    if (!_portal.isShowing) return;
    _settleTimer?.cancel();
    _settlingAfterHover = false;
    final returnTo = _returnFocus;
    _returnFocus = null;
    if (returnTo != null && returnTo.canRequestFocus && returnTo.context?.mounted == true) {
      returnTo.requestFocus();
    }
    _fade.reverse().whenComplete(() {
      if (!mounted || _fade.status != AnimationStatus.dismissed) return;
      WidgetsBinding.instance.removeObserver(this);
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
          if (mounted && _anchorHovered) _open(fromHover: true);
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

  /// Keys inside the panel.
  ///
  /// Back, escape or backspace close it - backspace only outside the search
  /// box, where it deletes. On a pad the arrows never get stuck in it: up and
  /// down walk the panel and up off its top leaves it for the chip; left and
  /// right move along a line of controls, and off either end of one leave the
  /// panel for the chip beside this one, the way they would with the panel
  /// shut. A search box keeps left and right for its caret until the caret is
  /// at that end of the text.
  KeyEventResult _onPanelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final focused = FocusManager.instance.primaryFocus;
    final editable = focused?.context?.findAncestorStateOfType<EditableTextState>();

    if (_closers.contains(key)) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (editable != null && key == LogicalKeyboardKey.backspace) return KeyEventResult.ignored;
      _close();
      return KeyEventResult.handled;
    }

    if (!_isDPad || focused == null) return KeyEventResult.ignored;
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;

    if (editable != null && (direction == TraversalDirection.left || direction == TraversalDirection.right)) {
      final value = editable.textEditingValue;
      final caret = value.selection;
      final atEnd = caret.isCollapsed &&
          (direction == TraversalDirection.left ? caret.baseOffset <= 0 : caret.baseOffset >= value.text.length);
      if (!atEnd) return KeyEventResult.ignored;
    }

    final target = _panelNeighbour(focused, direction);
    if (target != null) {
      target.requestFocus();
      final targetContext = target.context;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 120),
          alignmentPolicy: direction == TraversalDirection.up
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
      return KeyEventResult.handled;
    }

    switch (direction) {
      case TraversalDirection.up:
        _close();
      case TraversalDirection.left || TraversalDirection.right:
        final chip = _returnFocus;
        _close();
        if (chip != null && chip.context?.mounted == true) chip.focusInDirection(direction);
      case TraversalDirection.down:
        break;
    }
    return KeyEventResult.handled;
  }

  /// The controls in the panel that can take the selection and are on screen
  /// or about to be: built, laid out, and not a group around other controls.
  Iterable<(FocusNode, Rect)> _panelControls() sync* {
    for (final node in _panelScope.traversalDescendants) {
      if (!node.canRequestFocus || node.descendants.any((child) => child.canRequestFocus)) continue;
      final rect = _liveRect(node);
      if (rect != null) yield (node, rect);
    }
  }

  /// The nearest control in the panel beyond [from]'s edge in [direction]:
  /// the nearest line up or down, preferring what lines up with [from]; or
  /// the nearest on the same line sideways. Null at the panel's edge.
  FocusNode? _panelNeighbour(FocusNode from, TraversalDirection direction) {
    final origin = _liveRect(from);
    if (origin == null) return null;
    final vertical = direction == TraversalDirection.up || direction == TraversalDirection.down;

    // Everything beyond the edge, with how far beyond.
    final beyond = <(FocusNode, Rect, double)>[];
    for (final (node, rect) in _panelControls()) {
      if (identical(node, from)) continue;
      final gap = switch (direction) {
        TraversalDirection.up => origin.top - rect.bottom,
        TraversalDirection.down => rect.top - origin.bottom,
        TraversalDirection.left => origin.left - rect.right,
        TraversalDirection.right => rect.left - origin.right,
      };
      if (gap < -4) continue;
      if (!vertical && !(rect.bottom > origin.top + 4 && rect.top < origin.bottom - 4)) continue;
      beyond.add((node, rect, gap));
    }
    if (beyond.isEmpty) return null;
    final nearest = beyond.map((c) => c.$3).reduce(math.min);
    if (!vertical) return beyond.firstWhere((c) => c.$3 == nearest).$1;

    // The nearest line, then along it whatever lines up with [from]'s start.
    FocusNode? best;
    var bestScore = double.infinity;
    for (final (node, rect, gap) in beyond) {
      if (gap > nearest + 12) continue;
      final overlaps = rect.right > origin.left && rect.left < origin.right;
      final score = (rect.left - origin.left).abs() + (overlaps ? 0 : 100000);
      if (score < bestScore) {
        best = node;
        bestScore = score;
      }
    }
    return best;
  }

  /// Where the selection starts when a pad opens the panel: the control the
  /// panel marked with [PopoverInitialFocus], else its topmost control that
  /// is not a text box or the header's clear button.
  FocusNode? _initialControl() {
    final controls = _panelControls().toList();
    for (final (node, _) in controls) {
      if (node.context?.findAncestorWidgetOfExactType<PopoverInitialFocus>() != null) return node;
    }
    (FocusNode, Rect)? top;
    for (final control in controls) {
      final context = control.$1.context;
      if (context?.findAncestorStateOfType<EditableTextState>() != null) continue;
      if (context?.findAncestorWidgetOfExactType<PopoverHeader>() != null) continue;
      if (top == null ||
          control.$2.top < top.$2.top - 4 ||
          ((control.$2.top - top.$2.top).abs() <= 4 && control.$2.left < top.$2.left)) {
        top = control;
      }
    }
    return top?.$1 ?? controls.firstOrNull?.$1;
  }

  static Rect? _liveRect(FocusNode node) {
    final context = node.context;
    if (context is! Element || !context.mounted) return null;
    final box = context.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<bool> _onBack() async {
    _close();
    return true;
  }

  Widget _buildPanel(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final touch = AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch;
    final anchor = _anchorRect() ?? Rect.zero;
    final room = _room(anchor);

    // Never wider than the screen, and slid sideways to stay on it: flush
    // with the anchor's left edge where there is room, pushed in where not.
    const margin = 8.0;
    final width = math.min(widget.width, screenWidth - margin * 2);
    final left = anchor.left.clamp(margin, math.max(margin, screenWidth - margin - width));
    final maxHeight = (_below ? room.below : room.above).clamp(120.0, widget.maxHeight);
    final targetAnchor = _below ? Alignment.bottomLeft : Alignment.topLeft;
    final followerAnchor = _below ? Alignment.topLeft : Alignment.bottomLeft;

    Widget overlay = Stack(
      children: [
        if (touch)
          // Takes the tap that closes the panel, so it does not also open
          // whatever was under the finger.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => _close(),
            ),
          ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: targetAnchor,
          followerAnchor: followerAnchor,
          offset: Offset(left - anchor.left, _below ? 6 : -6),
          child: Align(
            alignment: followerAnchor,
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
                          maxWidth: width,
                          minWidth: width,
                          maxHeight: maxHeight,
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
    );

    // The system back gesture closes the panel rather than the page under it.
    if (Router.maybeOf(context)?.backButtonDispatcher != null) {
      overlay = BackButtonListener(onBackButtonPressed: _onBack, child: overlay);
    }
    return Positioned.fill(child: overlay);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildPanel,
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

/// Marks where a pad's selection starts when the panel opens - the choice
/// that is current, say, rather than the top of the list.
class PopoverInitialFocus extends StatelessWidget {
  final Widget child;
  const PopoverInitialFocus({required this.child, super.key});

  @override
  Widget build(BuildContext context) => child;
}

/// A panel's title, with a clear button beside it when there is anything to
/// clear.
class PopoverHeader extends StatelessWidget {
  final Widget title;
  final VoidCallback? onClear;

  const PopoverHeader({required this.title, this.onClear, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title,
              ),
            ),
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(IconsaxPlusLinear.close_circle, size: 16),
                label: Text(context.localized.clear),
              ),
          ],
        ),
      ),
    );
  }
}

/// One choice in a panel.
///
/// Every panel draws its choices the same way, and the way the rest of the
/// app draws a selected thing: filled with the primary container and ticked.
/// A choice that sits among others that can be ticked at the same time shows
/// an empty tick while it is off, so the list reads as a set of switches
/// rather than one pick. The pad's selection is the app's one ring. Rows are
/// finger-sized on a touch screen and tighter elsewhere.
class PopoverOption extends StatefulWidget {
  final Widget label;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  const PopoverOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.multiSelect = false,
    super.key,
  });

  @override
  State<PopoverOption> createState() => _PopoverOptionState();
}

class _PopoverOptionState extends State<PopoverOption> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final touch = AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch;
    final radius = FladderTheme.smallShape.borderRadius;
    final foreground = widget.selected ? colors.onPrimaryContainer : colors.onSurface;
    final tick = widget.selected
        ? Icon(IconsaxPlusBold.tick_circle, size: 20, color: foreground)
        : widget.multiSelect
            ? Icon(IconsaxPlusLinear.tick_circle, size: 20, color: foreground.withValues(alpha: 0.35))
            : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: FocusRing(
        visible: _focused,
        borderRadius: radius,
        child: Material(
          color: widget.selected ? colors.primaryContainer : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            focusColor: Colors.transparent,
            onFocusChange: (value) => setState(() => _focused = value),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: touch ? 48 : 38),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: IconTheme.merge(
                        data: IconThemeData(color: foreground, size: 20),
                        child: DefaultTextStyle.merge(
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: foreground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: widget.label,
                        ),
                      ),
                    ),
                    if (tick != null) tick,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

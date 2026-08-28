import 'package:flutter/material.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';

class FocusRow extends StatefulWidget {
  final Widget child;
  final double ensureVisibleAlignment;
  final FocusNode? focusNode;
  final WidgetOrderTraversalPolicy? traversalPolicy;
  final bool escapeToNavBar;
  final void Function(FocusNode groupNode)? onGroupFocused;
  final void Function(bool hasFocus)? onFocusChange;

  const FocusRow({
    required this.child,
    this.ensureVisibleAlignment = 0.5,
    this.focusNode,
    this.traversalPolicy,
    this.onGroupFocused,
    this.onFocusChange,
    this.escapeToNavBar = true,
    super.key,
  });

  @override
  State<FocusRow> createState() => _FocusRowState();
}

class _FocusRowState extends State<FocusRow> {
  late FocusNode _groupNode;
  FocusNode? _lastChild;

  bool _clearedByVertical = false;

  bool get _ownsNode => widget.focusNode == null;

  late final VoidCallback _focusManagerListener;

  @override
  void initState() {
    super.initState();
    _groupNode = widget.focusNode ?? FocusNode();

    _focusManagerListener = _handleFocusManagerChange;
    FocusManager.instance.addListener(_focusManagerListener);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_focusManagerListener);
    if (_ownsNode) _groupNode.dispose();
    super.dispose();
  }

  void _handleFocusManagerChange() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f != _groupNode && _groupNode.descendants.contains(f)) {
      _lastChild = f;
    }
  }

  void _clearOnVertical() {
    _lastChild = null;
    _clearedByVertical = true;
  }

  void _focusFirstChild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nodes = _childNodes(_groupNode);
      if (nodes.isEmpty) return;

      if (widget.onGroupFocused != null) {
        widget.onGroupFocused!(_groupNode);
        return;
      }

      // Already on one of this row's buttons - a vertical move that chose it
      // by geometry, or the way back to the one that was left - then that is
      // the selection, not the first button of the row.
      final already = FocusManager.instance.primaryFocus;
      if (already != null && already != _groupNode && _groupNode.descendants.contains(already)) {
        _lastChild = already;
        _clearedByVertical = false;
        try {
          already.context?.ensureVisible(alignment: widget.ensureVisibleAlignment);
        } catch (_) {}
        return;
      }

      FocusNode target;

      if (_lastChild != null &&
          !_clearedByVertical &&
          _lastChild!.canRequestFocus &&
          _lastChild!.context?.mounted == true) {
        target = _lastChild!;
      } else {
        target = nodes.first;
        _lastChild = target;
      }

      target.requestFocus();
      try {
        target.context?.ensureVisible(alignment: widget.ensureVisibleAlignment);
      } catch (_) {}

      _clearedByVertical = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: widget.traversalPolicy ??
          _RowFocusPolicy(
            groupNode: _groupNode,
            onVertical: _clearOnVertical,
            escapeToNavBar: widget.escapeToNavBar,
          ),
      child: Focus(
        focusNode: _groupNode,
        onFocusChange: (value) {
          widget.onFocusChange?.call(value);
          if (value && AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
            _focusFirstChild();
          }
        },
        child: widget.child,
      ),
    );
  }
}

/// Which line of a wrapped row a node sits on: its vertical centre, in bands
/// coarse enough that buttons of different heights on one line agree.
int _lineOf(FocusNode node) => (node.rect.center.dy / 24).round();

List<FocusNode> _childNodes(FocusNode node) =>
    node.descendants.where((n) => n.canRequestFocus && n.context != null).toList()
      ..sort((a, b) => a.rect.left.compareTo(b.rect.left));

class _RowFocusPolicy extends WidgetOrderTraversalPolicy {
  final VoidCallback? onVertical;
  final FocusNode groupNode;
  final bool escapeToNavBar;

  _RowFocusPolicy({this.onVertical, required this.groupNode, required this.escapeToNavBar});

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final towardsSidebar = isRtl ? TraversalDirection.right : TraversalDirection.left;
    final parent = currentNode.parent;
    // Reading order: line by line, then left to right. A row that has wrapped
    // - play and the pickers on one line, favourite and the rest on the next -
    // sorted by x alone zig-zagged between the lines on every press.
    final nodes = parent == null
        ? <FocusNode>[]
        : parent.descendants.where((n) => n.canRequestFocus && n.context != null).toList()
      ..sort((a, b) {
        final line = _lineOf(a).compareTo(_lineOf(b));
        return line != 0 ? line : a.rect.left.compareTo(b.rect.left);
      });

    if (nodes.isEmpty) return super.inDirection(currentNode, direction);
    final index = nodes.indexOf(currentNode);
    if (index == -1) return super.inDirection(currentNode, direction);

    switch (direction) {
      case TraversalDirection.left:
        if (index > 0) {
          nodes[index - 1].requestFocus();
        } else if (direction == towardsSidebar) {
          lastMainFocus = currentNode;
          if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true && escapeToNavBar) {
            final cb = FocusTraversalPolicy.defaultTraversalRequestFocusCallback;
            cb(navBarNode);
          }
        }
        return true;
      case TraversalDirection.right:
        if (index < nodes.length - 1) {
          nodes[index + 1].requestFocus();
        } else if (direction == towardsSidebar) {
          lastMainFocus = currentNode;
          if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true && escapeToNavBar) {
            final cb = FocusTraversalPolicy.defaultTraversalRequestFocusCallback;
            cb(navBarNode);
          }
        }
        return true;
      case TraversalDirection.up:
      case TraversalDirection.down:
        onVertical?.call();
        // Out of the row, from the row as a whole: the page's policy answers
        // for the group node, whose own children are never candidates. Asking
        // the parent node to move instead came straight back into this row -
        // down out of the play row went nowhere at all.
        // Another line of this same row first, when it has wrapped: the
        // button above or below this one, by geometry. Only then out of the
        // row.
        final sameRow = verticalNeighbour(currentNode, direction, candidates: nodes);
        if (sameRow != null) {
          sameRow.requestFocus();
          return true;
        }
        // From the row as a whole, but remembering this button: the way back
        // should land here, not on the first button of the row.
        if (pageVerticalMove(groupNode, direction, origin: currentNode)) return true;
        return super.inDirection(groupNode, direction);
    }
  }
}

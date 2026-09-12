import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/screens/library_search/widgets/alphabet_scrubber.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';

class GridFocusTraveler extends ConsumerStatefulWidget {
  final int currentIndex;
  final int itemCount;
  final int crossAxisCount;
  final Function(BuildContext context, int selectedIndex, int index) itemBuilder;
  final SliverGridDelegate gridDelegate;

  const GridFocusTraveler({
    this.currentIndex = 0,
    required this.itemCount,
    required this.crossAxisCount,
    required this.itemBuilder,
    required this.gridDelegate,
    super.key,
  });

  @override
  ConsumerState<GridFocusTraveler> createState() => _GridFocusTravelerState();
}

class _GridFocusTravelerState extends ConsumerState<GridFocusTraveler> {
  late int selectedIndex = widget.currentIndex;
  bool _initializedFocus = false;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: GridFocusTravelerPolicy(
        crossAxisCount: widget.crossAxisCount,
        onChanged: (value) {
          selectedIndex = value;
        },
      ),
      child: Builder(
        builder: (context) {
          if (!_initializedFocus && AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              // The grid takes the selection when its page opens, not when it
              // is built again under a selection already on the page: a filter
              // that empties the grid and then fills it again - Favourites
              // with none, then "not favourites" - dragged the selection off
              // the chip that was pressed and onto the first card.
              if (_selectionElsewhereOnPage(context)) {
                _initializedFocus = true;
                return;
              }
              final parent = Focus.of(context);
              final nodes = _childNodes(parent);
              if (nodes.isNotEmpty) {
                nodes.first.requestFocus();
                setState(() {
                  selectedIndex = 0;
                  _initializedFocus = true;
                });
              }
            });
          }

          return SliverGrid.builder(
            gridDelegate: widget.gridDelegate,
            itemCount: widget.itemCount,
            itemBuilder: (context, index) {
              return FocusProvider(
                child: Builder(
                  builder: (context) => widget.itemBuilder(context, selectedIndex, index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Whether something on the grid's own page already has the selection: a
/// live control on the same route, not the page's scope or a node that is
/// only there to catch keys.
bool _selectionElsewhereOnPage(BuildContext gridContext) {
  final focused = FocusManager.instance.primaryFocus;
  final focusedContext = focused?.context;
  if (focused == null || focusedContext == null || !focusedContext.mounted) return false;
  if (focused is FocusScopeNode || focused.skipTraversal || !isLiveFocusNode(focused)) return false;
  final route = ModalRoute.of(gridContext);
  return route != null && ModalRoute.of(focusedContext) == route;
}

/// The grid's cells in reading order: line by line, left to right.
///
/// By the centre of each cell, in bands, not by its top edge. A selected card
/// is drawn a little larger than its neighbours (see [FocusScale]), and its
/// rectangle grows with it - so sorted by top edge the selected card came
/// first on its line whatever column it was in, and "right" from it went to
/// the card at the start of the line, which then became the selected one and
/// sorted first in its turn. The selection could not get past the second
/// column. A card's centre does not move when it grows.
List<FocusNode> _childNodes(FocusNode node) {
  int line(FocusNode n) => (n.rect.center.dy / 24).round();
  return node.descendants.where((n) => n.canRequestFocus && isLiveFocusNode(n)).toList()
    ..sort((a, b) {
      final dy = line(a).compareTo(line(b));
      return dy != 0 ? dy : a.rect.center.dx.compareTo(b.rect.center.dx);
    });
}

class GridFocusTravelerPolicy extends WidgetOrderTraversalPolicy {
  final int crossAxisCount;
  final Function(int value) onChanged;

  GridFocusTravelerPolicy({
    required this.crossAxisCount,
    required this.onChanged,
  });

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final parent = currentNode.parent;
    if (parent == null) {
      return super.inDirection(currentNode, direction);
    }

    final nodes = _childNodes(parent);

    final current = nodes.indexOf(currentNode);
    if (current == -1) {
      return super.inDirection(currentNode, direction);
    }

    final itemCount = nodes.length;
    final row = current ~/ crossAxisCount;
    final col = current % crossAxisCount;
    final rowCount = (itemCount / crossAxisCount).ceil();

    int? next;
    switch (direction) {
      case TraversalDirection.left:
        if (col > 0) next = current - 1;
        break;
      case TraversalDirection.right:
        if (col < crossAxisCount - 1 && current + 1 < itemCount) {
          next = current + 1;
        }
        break;
      case TraversalDirection.up:
        if (row > 0) next = current - crossAxisCount;
        break;
      case TraversalDirection.down:
        if (row < rowCount - 1) {
          final candidate = current + crossAxisCount;
          if (candidate < itemCount) next = candidate;
        }
        break;
    }

    if (next != null) {
      final target = nodes[next];
      target.requestFocus();
      onChanged(next);
      return true;
    }

    if (direction == TraversalDirection.left && col == 0) {
      lastMainFocus = currentNode;
      focusNavBar();
      return true;
    }

    // Off the right edge is the letter strip, when the grid has one.
    if (direction == TraversalDirection.right) {
      final strip = alphabetScrubberNode;
      if (strip != null && strip.context?.mounted == true) {
        lastMainFocus = currentNode;
        strip.requestFocus();
        return true;
      }
    }

    // Out of the grid - up to the search row, down past its last line - by
    // the page's own search, over live nodes only. Flutter's search weighed
    // the stale nodes a list leaves behind, and could land on one that is not
    // on screen.
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      return pageVerticalMove(currentNode, direction);
    }
    return super.inDirection(currentNode, direction);
  }
}

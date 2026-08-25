import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/sticky_header_text.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/focus_row.dart';

/// The rows currently on screen, so that something drawn on top of them can
/// push one along.
///
/// The side navigation bar covers the start of every row on the page. What is
/// under it is the part of the row you have already scrolled past, and it can
/// be seen through the bar's gradient — so it looks tappable, and a tap that
/// lands between the bar's buttons used to fall through onto a poster nobody
/// could properly see. Scrolling that part back into view is what the tap
/// meant, and it is what the row's own left arrow already does.
abstract final class HorizontalListOverlayTaps {
  static final List<_HorizontalListState> _rows = [];

  static void _register(_HorizontalListState row) => _rows.add(row);

  static void _unregister(_HorizontalListState row) => _rows.remove(row);

  /// The row under [globalPosition], if one is there.
  ///
  /// Searched newest first: a row on the page you are looking at is registered
  /// after the ones on the page you opened it from.
  static _HorizontalListState? _rowAt(Offset globalPosition) {
    for (final row in _rows.reversed) {
      if (!row.mounted) continue;
      if (!(ModalRoute.of(row.context)?.isCurrent ?? true)) continue;

      final box = row.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;

      if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPosition)) return row;
    }
    return null;
  }

  /// Whether a tap there would have a row to act on.
  ///
  /// Asked before the tap is taken rather than after: something covering the
  /// page may only claim the taps it can actually do something with, and has
  /// to let the rest reach whatever is underneath.
  static bool hasRowAt(Offset globalPosition) => _rowAt(globalPosition) != null;

  /// Steps the row under [globalPosition] back by one screenful, as its own
  /// arrow would. Returns whether there was a row there to step.
  static bool nudgeRowAt(Offset globalPosition) {
    final row = _rowAt(globalPosition);
    row?._nudge(-1);
    return row != null;
  }
}

/// How tall [HorizontalList] makes itself for a given item shape.
///
/// Shared so that a placeholder standing in for a row that has not arrived can
/// reserve the exact height the row will take, and the page does not jump when
/// it does.
double horizontalListHeight(BuildContext context, WidgetRef ref, {double? dominantRatio}) =>
    ((AdaptiveLayout.poster(context).size * ref.watch(clientSettingsProvider.select((value) => value.posterSize))) /
        math.pow((dominantRatio ?? 1.0), 0.55)) *
    0.72;

/// The gap [HorizontalList] leaves between its items.
const double horizontalListItemGap = 8.0;

/// The bar above a row: its name and whatever sits beside it on the left, and
/// a slot at the far end.
///
/// Pulled out of [HorizontalList] so that a section which swaps a row for
/// something that is not a row - the show page's episodes, between the row and
/// the list - can put the identical bar above both. Anything rebuilt by hand
/// drifts by a few pixels, and a control that moves when you use it is the one
/// thing a view switch must not do.
class HorizontalListTitleBar extends StatelessWidget {
  final EdgeInsets contentPadding;
  final String? label;
  final String? subtext;
  final VoidCallback? onLabelClick;
  final List<Widget> titleActions;
  final List<Widget> trailingTitleActions;

  const HorizontalListTitleBar({
    required this.contentPadding,
    this.label,
    this.subtext,
    this.onLabelClick,
    this.titleActions = const [],
    this.trailingTitleActions = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: contentPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (label != null)
                  Flexible(
                    child: ExcludeFocus(
                      child: StickyHeaderText(
                        label: label ?? "",
                        onClick: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad ? null : onLabelClick,
                      ),
                    ),
                  ),
                if (subtext != null)
                  Flexible(
                    child: ExcludeFocus(
                      child: Text(
                        subtext!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                      ),
                    ),
                  ),
                ...titleActions
              ],
            ),
          ),
          ...trailingTitleActions,
        ].addPadding(const EdgeInsets.symmetric(horizontal: 6)),
      ),
    );
  }
}

class HorizontalList<T> extends ConsumerStatefulWidget {
  final bool autoFocus;
  final String? label;
  final List<Widget> titleActions;

  /// Put at the far end of the title bar, away from the name.
  final List<Widget> trailingTitleActions;
  final VerticalDirection? titleActionsPosition;
  final Function()? onLabelClick;
  final String? subtext;
  final List<T> items;
  final int? startIndex;

  /// The scroll arrows and the jump-to-current dot in the header's top right.
  /// Off for a row that sits at the very top of a screen, where they collide
  /// with the chrome in that corner.
  final bool showScrollControls;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final Function(int index)? onFocused;
  final bool scrollToEnd;
  final EdgeInsets contentPadding;
  final double? dominantRatio;
  final double? height;
  final bool shrinkWrap;
  final double Function(int index)? itemWidthBuilder;
  final ValueChanged<bool>? onFocusChange;

  const HorizontalList({
    this.autoFocus = false,
    required this.items,
    required this.itemBuilder,
    this.onFocused,
    this.startIndex,
    this.showScrollControls = true,
    this.height,
    this.label,
    this.titleActions = const [],
    this.trailingTitleActions = const [],
    this.titleActionsPosition = VerticalDirection.up,
    this.onLabelClick,
    this.scrollToEnd = false,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    this.subtext,
    this.shrinkWrap = false,
    this.dominantRatio,
    this.itemWidthBuilder,
    this.onFocusChange,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HorizontalListState();
}

class _HorizontalListState extends ConsumerState<HorizontalList> with TickerProviderStateMixin {
  final FocusNode parentNode = FocusNode();
  FocusNode? lastFocused;
  final GlobalKey _firstItemKey = GlobalKey();
  final GlobalKey _listViewKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final contentPadding = horizontalListItemGap;
  double? contentWidth;
  double? _firstItemWidth;
  bool hasFocus = false;

  /// The arrows only exist while the pointer is over the row, the way the
  /// dashboard's banner does it — a row you are not pointing at should not be
  /// wearing two buttons.
  bool _hovered = false;

  /// How much of an item is picture rather than the title under it. The arrows
  /// centre on the picture, which is the band your eye reads as the row.
  double _artworkFraction = 1.0;

  AnimationController? _scrollAnimation;

  @override
  void initState() {
    super.initState();
    _measureFirstItem();
    // Only the arrows listen, so a scroll doesn't rebuild the row itself.
    _scrollController.addListener(_updateScrollEdges);
    HorizontalListOverlayTaps._register(this);
  }

  /// Whether there is anything left to scroll to, each way. Notifiers rather
  /// than state: a row of posters has no business rebuilding on every frame of
  /// a scroll just to fade an arrow.
  final ValueNotifier<bool> _canScrollBack = ValueNotifier(false);
  final ValueNotifier<bool> _canScrollOn = ValueNotifier(false);

  void _updateScrollEdges() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _canScrollBack.value = position.pixels > position.minScrollExtent + 1;
    _canScrollOn.value = position.pixels < position.maxScrollExtent - 1;
  }

  /// One screenful and a bit less, the same step the old header arrows took.
  void _nudge(int direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final itemWidth = (_firstItemWidth ?? 0) + contentPadding;

    // As many whole items as fit, and landing on an item edge — a fixed
    // fraction of the screen left a poster cut in half at the margin, which is
    // the part that looked wrong next to the banner's clean steps.
    final double target;
    if (itemWidth > 1) {
      final step = math.max(1, position.viewportDimension ~/ itemWidth) * itemWidth;
      target = ((position.pixels + direction * step) / itemWidth).round() * itemWidth;
    } else {
      target = position.pixels + direction * position.viewportDimension * 0.8;
    }

    _scrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant HorizontalList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.height != widget.height) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureFirstItem();
      });
    }
    // A row whose contents are picked elsewhere - the show page's episodes,
    // where a season is chosen below the row - gets told where to be after it
    // was built, not only when.
    if (widget.startIndex != null && widget.startIndex != oldWidget.startIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToPosition(widget.startIndex!, duration: const Duration(milliseconds: 250));
      });
    }
  }

  @override
  void dispose() {
    HorizontalListOverlayTaps._unregister(this);
    _scrollController.removeListener(_updateScrollEdges);
    _canScrollBack.dispose();
    _canScrollOn.dispose();
    _scrollAnimation?.dispose();
    super.dispose();
  }

  void _measureFirstItem() {
    if (_firstItemWidth != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemContext = _firstItemKey.currentContext;
      if (itemContext != null) {
        final box = itemContext.findRenderObject() as RenderBox;
        _firstItemWidth = box.size.width;
        _measureArtwork(box);
        // Where the row begins, so it is placed rather than moved: animating
        // this meant every row on a page slid itself into position the moment
        // the page opened, which reads as the page still settling.
        _scrollToPosition(widget.startIndex ?? 0, instant: true);
      }

      if ((FocusProvider.autoFocusOf(context) || widget.autoFocus) &&
          AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad) {
        final nodesOnSameRow = _nodesInRow(parentNode);
        final initialNode = _nodeForItemIndex(context, nodesOnSameRow, widget.startIndex ?? 0);
        initialNode?.requestFocus();
      }
    });
  }

  /// An item that stacks a picture over a title is a column as tall as the
  /// item itself, and its first child is the picture. An item that is all
  /// picture has no such column and keeps the whole height.
  void _measureArtwork(RenderBox item) {
    if (!item.hasSize || item.size.height <= 0) return;

    RenderFlex? column;
    void visit(RenderObject node) {
      if (column != null) return;
      if (node is RenderFlex &&
          node.direction == Axis.vertical &&
          node.hasSize &&
          (node.size.height - item.size.height).abs() < 1) {
        column = node;
        return;
      }
      node.visitChildren(visit);
    }

    item.visitChildren(visit);

    final picture = column?.firstChild;
    if (picture is! RenderBox || !picture.hasSize) return;

    final fraction = (picture.size.height / item.size.height).clamp(0.2, 1.0);
    if (mounted && (fraction - _artworkFraction).abs() > 0.01) {
      setState(() => _artworkFraction = fraction);
    }
  }

  final Duration scrollMinDuration = const Duration(milliseconds: 75);
  final Duration scrollMaxDuration = const Duration(milliseconds: 275);

  Duration _durationForInterval(int? intervalMillis) {
    if (intervalMillis == null) return scrollMaxDuration;

    const minInterval = 50;
    const maxInterval = 300;

    final clamped = intervalMillis.clamp(minInterval, maxInterval);
    final t = (clamped - minInterval) / (maxInterval - minInterval);
    final minMs = scrollMinDuration.inMilliseconds;
    final maxMs = scrollMaxDuration.inMilliseconds;
    final ms = (minMs + t * (maxMs - minMs)).round();
    return Duration(milliseconds: ms);
  }

  double _cumulativeOffset(int index) {
    final widthBuilder = widget.itemWidthBuilder;
    if (widthBuilder == null) {
      return index * ((_firstItemWidth ?? 0) + contentPadding);
    }
    double offset = 0;
    for (var i = 0; i < index; i++) {
      offset += widthBuilder(i) + contentPadding;
    }
    return offset;
  }

  /// Where the row is actually allowed to sit.
  ///
  /// Worth having in one place because every path here sets the offset by hand
  /// - a position outside the extent is not refused, it is sprung back from,
  /// which is the bounce.
  double _clampToExtent(double offset) {
    final position = _scrollController.position;
    return offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// Puts the row back inside its extent once the extent is known for certain.
  ///
  /// A lazily built list does not know how long it is: until the items are laid
  /// out, [ScrollPosition.maxScrollExtent] is extrapolated from the handful
  /// that are. Landing on the last episode of a show means jumping to that
  /// estimate, and when the real items turn out a little narrower than the
  /// guess, the position we jumped to is suddenly past the end - so the row
  /// springs back, having appeared to overshoot.
  void _settleWithinExtent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.pixels > position.maxScrollExtent || position.pixels < position.minScrollExtent) {
        _scrollController.jumpTo(_clampToExtent(position.pixels));
      }
    });
  }

  Future<void> _scrollToPosition(int index, {Duration? duration, bool instant = false}) async {
    if (_firstItemWidth == null || !_scrollController.hasClients) return;

    final target = _clampToExtent(_cumulativeOffset(index));

    _scrollAnimation?.stop();

    if (instant) {
      if (_scrollController.hasClients) _scrollController.jumpTo(target);
      _settleWithinExtent();
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: duration ?? scrollMaxDuration,
    );

    _scrollAnimation = controller;

    final tween = Tween<double>(
      begin: _scrollController.offset,
      end: target,
    );

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.fastOutSlowIn,
    );

    controller.addListener(() {
      // Re-clamped per frame rather than once up front: the extent can still
      // be settling while this runs, and an animation is just as able to walk
      // the row off the end as a jump is.
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_clampToExtent(tween.evaluate(animation)));
      }
    });

    await controller.forward();
    _settleWithinExtent();

    if (_scrollAnimation == controller) _scrollAnimation = null;
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPointer = AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer;
    // The extents aren't known until the list has laid out once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateScrollEdges();
    });
    final titleBarWidget = HorizontalListTitleBar(
      contentPadding: widget.contentPadding,
      label: widget.label,
      subtext: widget.subtext,
      onLabelClick: widget.onLabelClick,
      titleActions: widget.titleActions,
      trailingTitleActions: widget.trailingTitleActions,
    );
    final hasLabel = widget.label != null || widget.titleActions.isNotEmpty || widget.trailingTitleActions.isNotEmpty;
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (hasLabel && widget.titleActionsPosition == VerticalDirection.up) titleBarWidget,
          FocusRow(
            focusNode: parentNode,
            traversalPolicy: HorizontalRailFocus(
              parentNode: parentNode,
              scrollController: _scrollController,
              firstItemWidth: _firstItemWidth ?? 250,
              onFocused: (node, {int? intervalMillis}) {
                lastFocused = node;
                final correctIndex = _getCorrectIndexForNode(node);
                if (correctIndex != -1) {
                  widget.onFocused?.call(correctIndex);
                  final duration = _durationForInterval(intervalMillis);
                  _scrollToPosition(correctIndex, duration: duration);
                }
              },
            ),
            onFocusChange: (value) {
              widget.onFocusChange?.call(value);
              if (value && hasFocus != value) {
                hasFocus = value;
                final nodesOnSameRow = _nodesInRow(parentNode);
                final currentNode = nodesOnSameRow.contains(lastFocused)
                    ? lastFocused
                    : _firstFullyVisibleNode(context, nodesOnSameRow);

                if (currentNode != null) {
                  lastFocused = currentNode;
                  final correctIndex = _getCorrectIndexForNode(currentNode);

                  if (widget.onFocused != null) {
                    if (correctIndex != -1) {
                      widget.onFocused!(correctIndex);
                    }
                  } else {
                    context.ensureVisible();
                  }
                  currentNode.requestFocus();
                }
              } else {
                hasFocus = false;
              }
            },
            onGroupFocused: (groupNode) {
              final nodesOnSameRow = _nodesInRow(parentNode);
              final currentNode =
                  nodesOnSameRow.contains(lastFocused) ? lastFocused : _firstFullyVisibleNode(context, nodesOnSameRow);

              if (currentNode != null) {
                lastFocused = currentNode;
                final correctIndex = _getCorrectIndexForNode(currentNode);
                if (widget.onFocused != null) {
                  if (correctIndex != -1) widget.onFocused!(correctIndex);
                } else {
                  context.ensureVisible();
                }
                currentNode.requestFocus();
              }
            },
            child: MouseRegion(
              onEnter: (event) {
                if (!_hovered) setState(() => _hovered = true);
              },
              onExit: (event) {
                if (_hovered) setState(() => _hovered = false);
              },
              child: SizedBox(
                height: widget.height ?? horizontalListHeight(context, ref, dominantRatio: widget.dominantRatio),
                child: Stack(
                  children: [
                    ListView.separated(
                      key: _listViewKey,
                      controller: _scrollController,
                      clipBehavior: Clip.none,
                      scrollDirection: Axis.horizontal,
                      padding: widget.contentPadding,
                      // Three items ahead rather than one: a row flicked
                      // hard used to arrive at posters that had not started
                      // loading until they were already in view.
                      cacheExtent: (_firstItemWidth ?? 250) * 3,
                      itemBuilder: (context, index) => index == widget.items.length
                          ? PosterPlaceHolder(
                              onTap: widget.onLabelClick ?? () {},
                              aspectRatio: widget.dominantRatio ?? AdaptiveLayout.poster(context).ratio,
                            )
                          : Container(
                              key: index == 0 ? _firstItemKey : null,
                              child: widget.itemBuilder(context, index),
                            ),
                      separatorBuilder: (context, index) => SizedBox(width: contentPadding),
                      itemCount:
                          widget.onLabelClick != null && AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad
                              ? widget.items.length + 1
                              : widget.items.length,
                    ),
                    // At the ends of the row rather than in a card next to the
                    // title: they point at the content they scroll, and they are
                    // out of the way of whatever sits in the screen's corner.
                    if (widget.showScrollControls && widget.items.length > 1 && hasPointer) ...[
                      _EdgeArrow(
                        alignment: Alignment.centerLeft,
                        inset: widget.contentPadding.left,
                        artworkFraction: _artworkFraction,
                        icon: IconsaxPlusLinear.arrow_left_1,
                        visible: _canScrollBack,
                        hovered: _hovered,
                        onTap: () => _nudge(-1),
                      ),
                      _EdgeArrow(
                        alignment: Alignment.centerRight,
                        inset: widget.contentPadding.right,
                        artworkFraction: _artworkFraction,
                        icon: IconsaxPlusLinear.arrow_right_3,
                        visible: _canScrollOn,
                        hovered: _hovered,
                        onTap: () => _nudge(1),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (hasLabel && widget.titleActionsPosition == VerticalDirection.down) titleBarWidget,
        ],
      ),
    );
  }

  int _getCorrectIndexForNode(FocusNode node) {
    if (!mounted || _firstItemWidth == null || !_scrollController.hasClients || node.context == null) return -1;

    final scrollableContext = _listViewKey.currentContext;
    if (scrollableContext == null || !scrollableContext.mounted) return -1;

    final scrollableBox = scrollableContext.findRenderObject() as RenderBox?;
    final itemBox = node.context!.findRenderObject() as RenderBox?;
    if (scrollableBox == null || itemBox == null) return -1;

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final itemTopLeft = itemBox.localToGlobal(Offset.zero, ancestor: scrollableBox);
    final itemTopRight = itemBox.localToGlobal(Offset(itemBox.size.width, 0), ancestor: scrollableBox);
    final viewportWidth = scrollableBox.size.width;
    final startPadding = isRtl ? widget.contentPadding.right : widget.contentPadding.left;
    final leadingInViewport = isRtl ? (viewportWidth - itemTopRight.dx) : itemTopLeft.dx;
    final offset = leadingInViewport + _scrollController.offset - startPadding;

    if (widget.itemWidthBuilder != null) {
      double cumulative = 0;
      for (var i = 0; i < widget.items.length; i++) {
        final w = widget.itemWidthBuilder!(i);
        if (offset < cumulative + w + contentPadding / 2) return i;
        cumulative += w + contentPadding;
      }
      return widget.items.length - 1;
    }

    final totalItemWidth = _firstItemWidth! + contentPadding;
    final index = ((offset + totalItemWidth / 2) ~/ totalItemWidth).clamp(0, widget.items.length - 1);

    return index;
  }
}

FocusNode? _firstFullyVisibleNode(
  BuildContext context,
  List<FocusNode> nodes,
) {
  if (nodes.isEmpty) return null;
  final isRtl = Directionality.of(context) == TextDirection.rtl;

  final scrollable = Scrollable.of(context);

  final viewportBox = scrollable.context.findRenderObject() as RenderBox;
  final viewportSize = viewportBox.size;

  for (final node in isRtl ? nodes.reversed : nodes) {
    final renderObj = node.context?.findRenderObject();
    if (renderObj is RenderBox) {
      final topLeft = renderObj.localToGlobal(Offset.zero, ancestor: viewportBox);
      final bottomRight = renderObj.localToGlobal(renderObj.size.bottomRight(Offset.zero), ancestor: viewportBox);

      final nodeRect = Rect.fromPoints(topLeft, bottomRight);

      final fullyVisible = nodeRect.left >= 0 &&
          nodeRect.right <= viewportSize.width &&
          nodeRect.top >= 0 &&
          nodeRect.bottom <= viewportSize.height;

      if (fullyVisible) {
        return node;
      }
    }
  }

  return isRtl ? nodes.lastOrNull : nodes.firstOrNull;
}

FocusNode? _nodeForItemIndex(BuildContext context, List<FocusNode> nodes, int index) {
  if (nodes.isEmpty) return null;

  final maxIndex = nodes.length - 1;
  final clampedIndex = index.clamp(0, maxIndex);
  final isRtl = Directionality.of(context) == TextDirection.rtl;
  final visualIndex = isRtl ? nodes.length - 1 - clampedIndex : clampedIndex;

  return nodes[visualIndex];
}

List<FocusNode> _nodesInRow(FocusNode parentNode) {
  return parentNode.descendants.where((n) => n.canRequestFocus && n.context != null).toList()
    ..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx));
}

class HorizontalRailFocus extends WidgetOrderTraversalPolicy {
  final FocusNode parentNode;
  final void Function(FocusNode node, {int? intervalMillis}) onFocused;
  final ScrollController scrollController;
  final double firstItemWidth;
  static DateTime? _lastMoveTime;
  static TraversalDirection? _lastDirection;

  HorizontalRailFocus({
    required this.parentNode,
    required this.onFocused,
    required this.scrollController,
    required this.firstItemWidth,
  });

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final towardsSidebar = isRtl ? TraversalDirection.right : TraversalDirection.left;
    final rowNodes = _nodesInRow(parentNode);
    final index = rowNodes.indexOf(currentNode);
    if (index == -1) return false;

    if (direction == TraversalDirection.left) {
      if (index == 0) {
        if (direction == towardsSidebar &&
            scrollController.hasClients &&
            scrollController.offset > firstItemWidth * 0.5) {
          if (scrollController.hasClients) scrollController.jumpTo(0);
          return true;
        }

        if (direction == towardsSidebar) {
          lastMainFocus = currentNode;
          if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true) {
            navBarNode.requestFocus();
            return true;
          }
        }
        return false;
      }

      final target = rowNodes[index - 1];
      final now = DateTime.now();
      final interval = _lastMoveTime == null || _lastDirection != TraversalDirection.left
          ? null
          : now.difference(_lastMoveTime!).inMilliseconds;
      _lastMoveTime = now;
      _lastDirection = TraversalDirection.left;

      target.requestFocus();
      onFocused(target, intervalMillis: interval);
      return true;
    }

    if (direction == TraversalDirection.right) {
      if (index < rowNodes.length - 1) {
        final target = rowNodes[index + 1];
        final now = DateTime.now();
        final interval = _lastMoveTime == null || _lastDirection != TraversalDirection.right
            ? null
            : now.difference(_lastMoveTime!).inMilliseconds;
        _lastMoveTime = now;
        _lastDirection = TraversalDirection.right;

        target.requestFocus();
        onFocused(target, intervalMillis: interval);
      } else if (direction == towardsSidebar) {
        lastMainFocus = currentNode;
        if (navBarNode.canRequestFocus && navBarNode.context?.mounted == true) {
          navBarNode.requestFocus();
          return true;
        }
      }
      return true;
    }

    parentNode.requestFocus();
    return super.inDirection(currentNode, direction);
  }
}

/// A scroll arrow at one end of a row, over the content it scrolls.
///
/// The same button, inset and fade the dashboard's banner uses, so the two
/// read as one control rather than two takes on the same idea. It appears
/// while the pointer is over the row, and only on the side there is something
/// left to scroll to.
class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow({
    required this.alignment,
    required this.inset,
    required this.artworkFraction,
    required this.icon,
    required this.visible,
    required this.hovered,
    required this.onTap,
  });

  final Alignment alignment;

  /// The row's own padding. The list is inset by it but this stack is not, so
  /// without it the left arrow sits under the navigation rail, which draws over
  /// the body — visible only as an arrow that does nothing.
  final double inset;

  /// How much of the item is picture. The arrow centres on that rather than on
  /// the cell, so it does not ride low against the title underneath.
  final double artworkFraction;
  final IconData icon;
  final ValueListenable<bool> visible;
  final bool hovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(alignment.x, artworkFraction - 1),
      child: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, canScroll, child) {
          final show = canScroll && hovered;
          return IgnorePointer(
            ignoring: !show,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: EdgeInsets.only(
            left: alignment == Alignment.centerLeft ? inset + 16 : 16,
            right: alignment == Alignment.centerRight ? inset + 16 : 16,
          ),
          child: IconButton.filledTonal(
            onPressed: onTap,
            icon: Icon(icon),
          ),
        ),
      ),
    );
  }
}

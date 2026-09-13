import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/screens/shared/media/poster_widget.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/sticky_header_text.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:chudder/widgets/shared/ensure_visible.dart';
import 'package:chudder/widgets/shared/focus_row.dart';

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

  /// Whether the selection left this row only because a page was pushed over
  /// the one it is on.
  ///
  /// A row used to hear that as losing the selection outright: it told the
  /// page (the television row folded its selected card back to a small one
  /// and dropped the summary under it), and on coming back it went through
  /// arriving all over again - re-scrolled itself, re-centred the page. All of
  /// which you could see: the card moved, the page shifted. But nothing was
  /// left. The page on top has the selection for a while, and it comes back
  /// to the very card it left. So while a page is over this one the row stays
  /// exactly as it was, and the only thing it does on the way back is check
  /// that the card is still in view.
  bool _focusUnderCover = false;

  /// Runs once the covering page is gone, in case the selection did not come
  /// back here - then the row really has lost it.
  Timer? _uncoverSettle;

  /// The arrows only exist while the pointer is over the row, the way the
  /// dashboard's banner does it — a row you are not pointing at should not be
  /// wearing two buttons.
  /// Only the edge arrows care, and they listen; the row itself - every
  /// poster in it - used to rebuild twice for each pass of the pointer.
  final ValueNotifier<bool> _hovered = ValueNotifier(false);

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
    _stopUncoverWatch();
    _scrollController.removeListener(_updateScrollEdges);
    _canScrollBack.dispose();
    _canScrollOn.dispose();
    _hovered.dispose();
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

  /// How wide item [index] is, by the same reckoning as [_cumulativeOffset].
  double _itemWidth(int index) => widget.itemWidthBuilder?.call(index) ?? _firstItemWidth ?? 0;

  /// The offset that brings item [index] whole into the row, or null when it
  /// already is.
  ///
  /// As little as it takes, and only when it takes anything: a card past the
  /// end of the row comes in to sit at that end, a card past the start at
  /// that start, and a card already in view leaves the row where it is. The
  /// selection used to be scrolled to the start of the row on every press, so
  /// it lived at the left edge and every step moved the whole row under it.
  /// Now it walks across the cards you can see, and the row only starts to
  /// move once it reaches the last of them - and stays where it is when the
  /// selection is simply given back to a card that never left the screen.
  ///
  /// "In view" is the row's own padded window. Nothing is clipped at its
  /// edges, so a card just outside it is still drawn - under the side bar at
  /// the start, cut by the window at the end - but it is not one you would
  /// call on screen.
  double? _revealOffset(int index) {
    if (_firstItemWidth == null || !_scrollController.hasClients) return null;
    final position = _scrollController.position;
    final window = position.viewportDimension - widget.contentPadding.horizontal;
    final start = _cumulativeOffset(index);
    final end = start + _itemWidth(index);
    final pixels = position.pixels;
    const slack = 0.5;

    final double target;
    if (end - start > window || start < pixels - slack) {
      target = start;
    } else if (end > pixels + window + slack) {
      target = end - window;
    } else {
      return null;
    }
    final clamped = _clampToExtent(target);
    return (clamped - pixels).abs() <= slack ? null : clamped;
  }

  /// Brings item [index] into view if it is not, see [_revealOffset].
  Future<void> _revealIndex(int index, {Duration? duration}) async {
    final target = _revealOffset(index);
    if (target == null) return;
    await _animateTo(target, duration: duration);
  }

  Future<void> _scrollToPosition(int index, {Duration? duration, bool instant = false}) async {
    if (_firstItemWidth == null || !_scrollController.hasClients) return;
    await _animateTo(_clampToExtent(_cumulativeOffset(index)), duration: duration, instant: instant);
  }

  Future<void> _animateTo(double target, {Duration? duration, bool instant = false}) async {
    if (!_scrollController.hasClients) return;

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
                  // Only as far as it takes - see [_revealOffset]. The
                  // selection walks across the cards in view and the row
                  // moves once it reaches the last of them.
                  _revealIndex(correctIndex, duration: _durationForInterval(intervalMillis));
                }
              },
            ),
            onFocusChange: (value) {
              if (!value) {
                if (hasFocus && _coveredByRoute()) {
                  // A page over this one has the selection for now. Nothing
                  // here changes; see [_focusUnderCover].
                  _focusUnderCover = true;
                  _watchForUncover();
                  return;
                }
                _stopUncoverWatch();
                hasFocus = false;
                widget.onFocusChange?.call(false);
                return;
              }
              if (_focusUnderCover) {
                // Back from under the page. The widget above never heard the
                // selection leave, so it does not hear it return either; the
                // card is only checked to be in view, which it will be unless
                // the page changed under the cover.
                _stopUncoverWatch();
                hasFocus = false;
              } else {
                widget.onFocusChange?.call(true);
              }
              if (hasFocus) return;
              hasFocus = true;
              _settleOnSelection();
            },
            onGroupFocused: (groupNode) => _settleOnSelection(),
            child: MouseRegion(
              onEnter: (event) => _hovered.value = true,
              onExit: (event) => _hovered.value = false,
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
                      scrollCacheExtent: ScrollCacheExtent.pixels((_firstItemWidth ?? 250) * 3),
                      itemBuilder: (context, index) {
                        if (index == widget.items.length) {
                          return PosterPlaceHolder(
                            onTap: widget.onLabelClick ?? () {},
                            aspectRatio: widget.dominantRatio ?? AdaptiveLayout.poster(context).ratio,
                          );
                        }
                        final child = widget.itemBuilder(context, index);
                        // Keyed by which item it is, not by where it sits.
                        //
                        // The cards carry a key of their own - see [PosterRow] -
                        // but it used to sit on the child of an unkeyed
                        // Container, and a list matches the children it is
                        // handed. Matching by position, the row could only
                        // rebuild: every update - the server saying an episode's
                        // progress changed, a row coming back with the same
                        // films in a different order - threw away the cards and
                        // built new ones. New cards are new state and new focus
                        // nodes, so anything the row was holding, the selection
                        // included, went with them. Keyed here, the list moves
                        // the cards it already has and they survive the update.
                        return KeyedSubtree(
                          key: child.key ?? ValueKey(index),
                          child: index == 0 ? Container(key: _firstItemKey, child: child) : child,
                        );
                      },
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

  /// The selection has arrived in this row: settle it on a card, bring that
  /// card into view and tell the page.
  ///
  /// Whatever actually holds the selection keeps it. This used to decide for
  /// itself which of its cards ought to be selected - its own [lastFocused],
  /// or failing that whichever card was first fully in view - and then request
  /// focus on it. Coming back from a pushed page the selection is already on
  /// the right card, so that took it away again: onto the card before, or onto
  /// whatever the scroll offset had left at the left edge, which is why it
  /// landed one along or a row off. Geometry only when nothing here is
  /// selected, which is what that fallback was written for: arriving from
  /// another row.
  ///
  /// Every step of this leaves a row alone that is already right, so it is
  /// safe to arrive at twice - the group node and the row's own focus change
  /// both call it.
  void _settleOnSelection() {
    final nodesOnSameRow = _nodesInRow(parentNode);
    if (_selectionHeldElsewhere(nodesOnSameRow)) return;
    final held = FocusManager.instance.primaryFocus;
    final currentNode = (held != null && nodesOnSameRow.contains(held))
        ? held
        : nodesOnSameRow.contains(lastFocused)
            ? lastFocused
            : _firstFullyVisibleNode(context, nodesOnSameRow);
    if (currentNode == null) return;

    lastFocused = currentNode;
    final correctIndex = _getCorrectIndexForNode(currentNode);
    if (widget.onFocused != null) {
      if (correctIndex != -1) widget.onFocused!(correctIndex);
    } else {
      context.ensureVisible();
    }
    // Into view as well as selected: the card a row remembers is often the one
    // the page opened on, which the row has since been scrolled away from.
    // Only if it is out of view, though - a card that never left the screen
    // is not moved, see [_revealOffset].
    if (correctIndex != -1) _revealIndex(correctIndex, duration: const Duration(milliseconds: 250));
    currentNode.requestFocus();
  }

  /// Whether a page has been pushed over the one this row is on.
  ///
  /// Every navigator on the way up, not only the nearest: a details page is
  /// pushed on the tab's own navigator, a dialog or the player on the root's,
  /// and either takes the selection away from here for a while.
  bool _coveredByRoute() {
    // A row a list has set aside is still mounted but no longer in the tree,
    // and asking such an element for its route throws. Not live, not covered:
    // the selection is treated as gone, which for a row that is going is right.
    if (!mounted || (context as Element).renderObject?.attached != true) return false;
    ModalRoute<dynamic>? route = ModalRoute.of(context);
    while (route != null) {
      if (!route.isCurrent) return true;
      final navigatorContext = route.navigator?.context;
      route = navigatorContext == null ? null : ModalRoute.of(navigatorContext);
    }
    return false;
  }

  /// Listens for the covering page to go, see [_focusUnderCover].
  void _watchForUncover() {
    // Once, however often this is asked: removeListener takes off one
    // registration per call, so a second one would outlive the stop.
    FocusManager.instance.removeListener(_onFocusWhileCovered);
    FocusManager.instance.addListener(_onFocusWhileCovered);
  }

  void _stopUncoverWatch() {
    _focusUnderCover = false;
    _uncoverSettle?.cancel();
    _uncoverSettle = null;
    FocusManager.instance.removeListener(_onFocusWhileCovered);
  }

  void _onFocusWhileCovered() {
    if (!mounted) {
      _stopUncoverWatch();
      return;
    }
    if (_coveredByRoute()) return;
    // The page on top has gone. The selection is on its way back here - the
    // route hands it to its scope, and the navigator's observer puts it on the
    // card it left - but not in this very frame. Long enough for a transition
    // to finish; if the selection has not come back by then it went somewhere
    // else, and this row lost it after all.
    FocusManager.instance.removeListener(_onFocusWhileCovered);
    _uncoverSettle?.cancel();
    _uncoverSettle = Timer(const Duration(milliseconds: 700), () {
      _uncoverSettle = null;
      if (!mounted || !_focusUnderCover) return;
      _focusUnderCover = false;
      if (parentNode.hasFocus) return;
      hasFocus = false;
      widget.onFocusChange?.call(false);
    });
  }

  /// Whether the selection is already on a card that is not one of ours.
  ///
  /// Every row hears about the selection arriving on the page, not only the row
  /// it arrived in. A row that does not have it used to carry on and hand the
  /// selection to its own remembered card anyway - so coming back from a pushed
  /// page, the right card was selected and then a row further up took it. A row
  /// with no claim leaves it alone.
  bool _selectionHeldElsewhere(List<FocusNode> nodesOnSameRow) {
    final held = FocusManager.instance.primaryFocus;
    if (held == null || nodesOnSameRow.contains(held)) return false;
    return held.context?.findAncestorWidgetOfExactType<PosterWidget>() != null;
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
  return parentNode.descendants.where((n) => n.canRequestFocus && isLiveFocusNode(n)).toList()
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
          if (focusNavBar()) return true;
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
        if (focusNavBar()) return true;
      }
      return true;
    }

    // Up or down: out of the row, by the page's own search - geometry over
    // live nodes only. Flutter's search weighed the stale nodes a list
    // leaves behind: it threw on them in a debug build, and in a release one
    // could land on something that is not on screen, which is how down off
    // the dashboard's first row went nowhere.
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      return pageVerticalMove(currentNode, direction);
    }
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
  final ValueListenable<bool> hovered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment(alignment.x, artworkFraction - 1),
      child: ListenableBuilder(
        listenable: Listenable.merge([visible, hovered]),
        builder: (context, child) {
          final show = visible.value && hovered.value;
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

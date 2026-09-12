import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/screens/details_screens/components/overview_header.dart';
import 'package:fladder/widgets/navigation_scaffold/components/playback_chrome_actions.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_bar.dart';
import 'package:fladder/widgets/navigation_scaffold/components/top_navigation_bar.dart';
import 'package:fladder/widgets/shared/back_intent_dpad.dart';

class NavigationBody extends ConsumerStatefulWidget {
  final BuildContext parentContext;
  final Widget child;
  final int currentIndex;
  final List<DestinationModel> destinations;
  final String currentLocation;
  final GlobalKey<ScaffoldState> drawerKey;
  const NavigationBody({
    required this.parentContext,
    required this.child,
    required this.currentIndex,
    required this.destinations,
    required this.currentLocation,
    required this.drawerKey,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _NavigationBodyState();
}

class _NavigationBodyState extends ConsumerState<NavigationBody> {
  double currentSideBarWidth = 80;

  @override
  Widget build(BuildContext context) {
    // Always true: this widget only exists inside the tabs router, and
    // details screens are siblings of Home rather than children, so there
    // is no longer a non-tab route to test for. Kept as a name because the
    // padding helpers below still read as a question.
    const hasOverlay = true;

    ref.listen(
      clientSettingsProvider,
      (previous, next) {
        if (previous != next) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarIconBrightness: next.statusBarBrightness(context),
          ));
        }
      },
    );

    Widget paddedChild() => MediaQuery(
          data: semiNestedPadding(widget.parentContext, hasOverlay),
          child: widget.child,
        );

    final newTVLayout = AdaptiveLayout.viewSizeOf(context) >= ViewSize.television &&
        ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout));

    return BackIntentDpad(
      // Whatever page is on top: one opened on a tab is on that tab's own
      // navigator, and popping the router this sits in - the root's, above
      // the tabs - would skip it and take Home back to its first tab.
      onBack: () => context.router.maybePopTop(),
      child: FocusTraversalGroup(
        policy: GlobalFallbackTraversalPolicy(),
        // The side bar is not drawn here any more: one bar is drawn over
        // every page by [PersistentNavigationChrome], which also tells these
        // pages how wide it is. Only the television's top bar is still Home's.
        child: switch (AdaptiveLayout.layoutOf(context)) {
          ViewSize.phone || ViewSize.tablet => paddedChild(),
          ViewSize.desktop || ViewSize.television => newTVLayout
              ? TopNavigationBar(
                  currentIndex: widget.currentIndex,
                  destinations: widget.destinations,
                  currentLocation: widget.currentLocation,
                  child: paddedChild(),
                  scaffoldKey: widget.drawerKey,
                )
              : paddedChild(),
        },
      ),
    );
  }

  MediaQueryData semiNestedPadding(BuildContext context, bool hasOverlay) {
    final paddingOf = MediaQuery.paddingOf(context);
    final isRTL = Directionality.of(context) == TextDirection.rtl;
    return MediaQuery.of(context).copyWith(
      padding: EdgeInsetsDirectional.only(
        start: isRTL
            ? hasOverlay
                ? 0
                : paddingOf.right
            : hasOverlay
                ? 0
                : paddingOf.left,
        end: isRTL ? paddingOf.left : paddingOf.right,
        top: paddingOf.top,
        bottom: paddingOf.bottom,
      ).resolve(Directionality.of(context)),
    );
  }
}

FocusNode? lastMainFocus;

/// The last vertical move the page policy made, so the opposite press can
/// undo it exactly. See [GlobalFallbackTraversalPolicy.inDirection].
({FocusNode from, FocusNode to, TraversalDirection direction})? _lastVerticalMove;

/// Prints every directional move the page policy decides, and every vertical
/// search behind it. Switched on by integration_test/dpad_sweep_test.dart,
/// which walks the detail pages with a pad and reads these back.
bool debugTraceFocusMoves = false;

/// A press of up or down anywhere on a page, from [currentNode] - or from a
/// row's group node, asking on behalf of whichever of its buttons is selected.
///
/// Straight back the way you came when that is what the press is: up from
/// the play row to the artwork and down again lands on the picker you left,
/// not on whichever button in the row happens to be nearest. One step of
/// memory only - a fresh direction is a fresh search - so it cannot loop the
/// way Flutter's own history did. Otherwise geometry, see [verticalNeighbour];
/// and up with nothing above goes to SyncPlay and Cast in the corner, which
/// float over the content and are in no band with anything.
bool pageVerticalMove(FocusNode currentNode, TraversalDirection direction, {FocusNode? origin}) {
  final back = _lastVerticalMove;
  // The node the last move landed on, or the row asking on its behalf.
  final landedHere = back != null && (identical(back.to, currentNode) || currentNode.descendants.contains(back.to));
  if (back != null &&
      landedHere &&
      back.direction != direction &&
      back.from.canRequestFocus &&
      // And still in the tree and laid out. A node whose row has scrolled or
      // rebuilt since the move out still answers canRequestFocus, but has no
      // box any more: the selection goes to something that is not on screen and
      // the ring is drawn from a stale rectangle - a little away from where it
      // belongs, or on the button beside the one you actually left. Every other
      // walk over these nodes filters the same way; [verticalNeighbour] gets it
      // for free by needing a rect at all. Not live, and the search below picks
      // instead, which is the behaviour this shortcut is an improvement on.
      isLiveFocusNode(back.from) &&
      _onCurrentRoute(back.from)) {
    _lastVerticalMove = null;
    back.from.requestFocus();
    return true;
  }

  final target = verticalNeighbour(currentNode, direction);
  if (target != null) {
    // Remember the button that actually had the selection, so the way back
    // lands on it rather than on the row it is in.
    _lastVerticalMove = (from: origin ?? currentNode, to: target, direction: direction);
    target.requestFocus();
    return true;
  }

  if (direction == TraversalDirection.up) {
    final chrome = chromeActionsAnchor?.traversalDescendants
        .where((node) => node.canRequestFocus && _onCurrentRoute(node))
        .firstOrNull;
    if (chrome != null) {
      lastMainFocus = currentNode;
      chrome.requestFocus();
      return true;
    }
  }
  return false;
}

/// The nearest focusable strictly above or below [from], or null.
///
/// One rule for every vertical move on a page, in place of Flutter's
/// directional search. That search prefers what it remembers from the last
/// move over what is on screen, and on a page that scrolls under the
/// selection it sent up from a genre chip to the play row *below* it, and
/// from there back to the chip - forever. This looks only at geometry: what
/// is above or below right now, preferring whatever overlaps horizontally
/// with [from], else whatever is closest.
///
/// [from]'s own descendants are never candidates, so a row's group node can
/// ask where to go from the row as a whole.
FocusNode? verticalNeighbour(FocusNode from, TraversalDirection direction, {Iterable<FocusNode>? candidates}) {
  final scope = from.enclosingScope;
  if (scope == null) return null;
  final origin = _rectOf(from);
  if (origin == null) return null;
  // With [candidates] given - a row asking about its own lines - those are
  // the only ones considered, descendants of [from] included.
  final own = candidates == null ? from.descendants.toSet() : const <FocusNode>{};

  // Everything beyond the edge, with how far beyond it starts.
  final beyond = <(FocusNode, Rect, double)>[];
  for (final node in candidates ?? scope.traversalDescendants) {
    if (identical(node, from) || own.contains(node) || !node.canRequestFocus) continue;
    // Buttons, not the groups around them: a row's own node is focusable and
    // would then hand the selection to its first child, whichever button was
    // actually nearest.
    if (isFocusGroup(node)) continue;
    final rect = _rectOf(node);
    if (rect == null) continue;
    final double gap;
    switch (direction) {
      case TraversalDirection.up:
        gap = origin.top - rect.bottom;
      case TraversalDirection.down:
        gap = rect.top - origin.bottom;
      default:
        return null;
    }
    // Strictly beyond the edge, with a little slack for rows that touch.
    if (gap < -4) continue;
    beyond.add((node, rect, gap));
  }
  if (beyond.isEmpty) return null;

  // The nearest line first - reading order, the way a page is laid out - and
  // only then the best fit across it. Judged all at once, a summary as wide
  // as the page beat the row of buttons right under the artwork simply by
  // overlapping it, and down from the artwork skipped the play button.
  final nearest = beyond.map((c) => c.$3).reduce((a, b) => a < b ? a : b);
  final line = beyond.where((c) => c.$3 <= nearest + 24);

  FocusNode? best;
  double bestScore = double.infinity;
  for (final (node, rect, _) in line) {
    final overlaps = rect.right > origin.left && rect.left < origin.right;
    // Overlap wins; among overlaps, the one that starts nearest to where the
    // origin starts - reading order, so up from a summary as wide as the page
    // lands on the play button at the left of the row rather than whichever
    // button happens to sit under the summary's middle. Without overlap, the
    // closest edge.
    final score = overlaps
        ? (rect.left - origin.left).abs()
        : 10000 + (rect.left > origin.right ? rect.left - origin.right : origin.left - rect.right);
    if (score < bestScore) {
      best = node;
      bestScore = score;
    }
  }
  if (debugTraceFocusMoves) {
    final laidOut = scope.traversalDescendants.where((n) => _rectOf(n) != null).length;
    debugPrint('[vertical] $direction from=${origin.toString()} candidates=$laidOut '
        'own=${own.length} -> ${best == null ? 'none' : '${best.context?.widget.runtimeType} ${_rectOf(best)}'}');
  }
  return best;
}

/// The render box behind [node], if its widget is in the tree right now.
///
/// A focus node can outlive its widget's place in the tree: the element is
/// deactivated, the node stays attached. Asking such an element for its route
/// or its size throws in a debug build - the press that asked is lost - and
/// answers with stale values in a release one. `renderObject` rather than
/// `findRenderObject()`, which is the call that asserts; a deactivated
/// element's render object is detached, so that says whether it is live.
RenderBox? _liveBox(FocusNode node) {
  final context = node.context;
  if (context is! Element || !context.mounted) return null;
  final ro = context.renderObject;
  if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
  return ro;
}

Rect? _rectOf(FocusNode node) {
  final ro = _liveBox(node);
  if (ro == null) return null;
  return ro.localToGlobal(Offset.zero) & ro.size;
}

/// Whether [node]'s widget is in the tree right now and laid out: the only
/// kind of node a traversal should weigh up. See [_liveBox].
bool isLiveFocusNode(FocusNode node) => _liveBox(node) != null;

/// Whether [node] is a group around other controls rather than a control
/// itself: a row's node, a chip strip's, the page's.
///
/// Judged by what a traversal could reach under it, not by what merely can
/// take focus. A text field on a pad is a wrapper node around the field
/// proper, which stays focusable - typing needs it - but is kept out of
/// traversal; counted as a group for that, the search field on the Search tab
/// was never a candidate and no press could reach it.
bool isFocusGroup(FocusNode node) => node.traversalDescendants.isNotEmpty;

/// The nearest focusable to the left or right of [from], or null.
///
/// The sideways half of [verticalNeighbour], and for the same reason:
/// Flutter's own directional search weighs every node in the scope, the stale
/// ones a list leaves behind included - on those it throws in a debug build
/// and, in a release one, picks something that is not on screen. Heading for
/// the bar only the line [from] is on counts, so a press off the edge of a
/// row reaches the bar rather than a control somewhere further down; the
/// other way, anything further along does, the same line first.
FocusNode? horizontalNeighbour(FocusNode from, TraversalDirection direction, {required bool towardsSidebar}) {
  if (direction != TraversalDirection.left && direction != TraversalDirection.right) return null;
  final scope = from.enclosingScope;
  if (scope == null) return null;
  final origin = _rectOf(from);
  if (origin == null) return null;
  final own = from.descendants.toSet();

  FocusNode? best;
  double bestScore = double.infinity;
  for (final node in scope.traversalDescendants) {
    if (identical(node, from) || own.contains(node) || !node.canRequestFocus) continue;
    // Buttons, not the groups around them - see [verticalNeighbour].
    if (isFocusGroup(node)) continue;
    if (!_onCurrentRoute(node)) continue;
    final rect = _rectOf(node);
    if (rect == null) continue;
    final gap = direction == TraversalDirection.left ? origin.left - rect.right : rect.left - origin.right;
    // Strictly beyond the edge, with a little slack for buttons that touch.
    if (gap < -4) continue;
    final sameLine = rect.bottom > origin.top && rect.top < origin.bottom;
    if (!sameLine && towardsSidebar) continue;
    final score = sameLine ? gap : 10000 + gap + (rect.center.dy - origin.center.dy).abs();
    if (score < bestScore) {
      best = node;
      bestScore = score;
    }
  }
  return best;
}

/// Whether [a] and [b] share a line: their rectangles overlap vertically.
bool _onSameLine(FocusNode a, FocusNode b) {
  final ra = _rectOf(a);
  final rb = _rectOf(b);
  if (ra == null || rb == null) return false;
  return rb.bottom > ra.top && rb.top < ra.bottom;
}

/// The scroller running sideways under [node], if it sits in one - the
/// dashboard's carousel of banner cards, say - and not the page itself.
ScrollableState? _sidewaysScrollerOf(FocusNode node) {
  final context = node.context;
  if (context == null || !context.mounted) return null;
  return Scrollable.maybeOf(context, axis: Axis.horizontal);
}

/// Whether [direction] runs towards the end of a sideways scroller.
bool _towardsEnd(BuildContext context, TraversalDirection direction) =>
    (direction == TraversalDirection.right) != (Directionality.of(context) == TextDirection.rtl);

/// Brings [node] whole into view along the sideways scroller it sits in.
///
/// Flutter's own traversal scrolled the node it landed on into view; the
/// geometric search that replaced it (see [horizontalNeighbour]) only moved
/// the selection, so a press onto the carousel's last visible card landed on
/// the sliver of it that was showing and the card never came in.
void _revealSideways(FocusNode node, TraversalDirection direction) {
  final scroller = _sidewaysScrollerOf(node);
  final box = _liveBox(node);
  if (scroller == null || box == null) return;
  scroller.position.ensureVisible(
    box,
    alignmentPolicy: _towardsEnd(node.context!, direction)
        ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
        : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeInOutCubic,
  );
}

/// With nothing further along the line to move to, scrolls the sideways
/// scroller [node] sits in so that [node] is at the near edge and whatever
/// follows it comes into view. Returns whether it had anywhere to go.
bool _scrollSideways(FocusNode node, TraversalDirection direction) {
  final scroller = _sidewaysScrollerOf(node);
  final box = _liveBox(node);
  if (scroller == null || box == null) return false;
  final position = scroller.position;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return false;
  final alignment = _towardsEnd(node.context!, direction) ? 0.0 : 1.0;
  final target =
      viewport.getOffsetToReveal(box, alignment).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  if ((target - position.pixels).abs() < 1) return false;
  position.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeInOutCubic);
  return true;
}

/// Whether [node] belongs to the page on top.
///
/// A page that another has been pushed over keeps every one of its nodes
/// focusable - Flutter only marks its scope skipTraversal - and the anchors
/// are globals, so down out of the corner buttons on an actor's page handed
/// the selection to the play button of the film underneath: nothing on screen
/// showed it, and Select would have started the film.
bool _onCurrentRoute(FocusNode node) {
  if (_liveBox(node) == null) return false;
  return ModalRoute.isCurrentOf(node.context!) ?? true;
}

/// The first control on the page: the topmost line, and the leftmost on it.
///
/// For a press made while nothing is really selected. Buttons only, never a
/// row's group node; and never SyncPlay and Cast in the corner, which up
/// reaches on its own.
FocusNode? firstPageControl(FocusNode from) {
  final scope = from is FocusScopeNode ? from : from.enclosingScope;
  if (scope == null) return null;
  FocusNode? best;
  Rect? bestRect;
  for (final node in scope.traversalDescendants) {
    if (!node.canRequestFocus || !_onCurrentRoute(node)) continue;
    if (isFocusGroup(node)) continue;
    if (_isWithin(node, chromeActionsAnchor)) continue;
    final rect = _rectOf(node);
    if (rect == null) continue;
    final higher = bestRect == null || rect.top < bestRect.top - 4;
    final leftOnSameLine = bestRect != null && (rect.top - bestRect.top).abs() <= 4 && rect.left < bestRect.left;
    if (higher || leftOnSameLine) {
      best = node;
      bestRect = rect;
    }
  }
  return best;
}

/// Whether [node] is [anchor] or sits under it.
bool _isWithin(FocusNode node, FocusNode? anchor) {
  if (anchor == null) return false;
  FocusNode? current = node;
  while (current != null) {
    if (identical(current, anchor)) return true;
    current = current.parent;
  }
  return false;
}

class GlobalFallbackTraversalPolicy extends ReadingOrderTraversalPolicy {
  GlobalFallbackTraversalPolicy() : super();

  // Flutter's own directional search is deliberately never asked: it weighs
  // every node in the scope, stale ones included (see [horizontalNeighbour]
  // and [verticalNeighbour]), and the history it keeps is only ever used by
  // that search.
  @override
  // ignore: must_call_super
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final towardsSidebar = isRtl ? TraversalDirection.right : TraversalDirection.left;
    lastMainFocus = null;

    // Up from SyncPlay and Cast is the top of the page: nothing is above them.
    // Left to the directional search, a page scrolled down had the artwork
    // play button sitting above them off the top edge, and up went "up" to
    // it, which scrolled it back into view - and up from there is the chrome
    // again. Pressing only up bounced between the two forever.
    if (direction == TraversalDirection.up && _isWithin(currentNode, chromeActionsAnchor)) {
      return true;
    }

    // Down out of SyncPlay and Cast lands on the artwork play button when the
    // page has one. It is the top of the page and the first thing the page
    // wants pressed, but it stands alone in the middle of the artwork, in no
    // band with the corner buttons, and the directional search went past it to
    // wherever focus had been before.
    if (direction == TraversalDirection.down && _isWithin(currentNode, chromeActionsAnchor)) {
      final target = artworkPlayAnchor?.traversalDescendants
          .where((node) => node.canRequestFocus && _onCurrentRoute(node))
          .firstOrNull;
      if (target != null) {
        target.requestFocus();
        return true;
      }
    }

    // Nothing on the page is really selected: what has focus is the page's
    // scope, or a node that is only there to catch keys - PullToRefresh's,
    // which takes the autofocus on every detail page. A film page is rescued
    // by its play button's own autofocus; an actor's page had nothing, and a
    // search from a node the whole page sits inside finds nothing, since its
    // own descendants are never candidates. Any press selects the first
    // control instead, which is what Flutter's own search did from a scope.
    if (currentNode is FocusScopeNode || currentNode.skipTraversal) {
      final first = firstPageControl(currentNode);
      if (first != null) {
        _lastVerticalMove = null;
        first.requestFocus();
        return true;
      }
    }

    var handled = false;
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      handled = pageVerticalMove(currentNode, direction);
    } else {
      _lastVerticalMove = null;
      // By geometry, over live nodes only - see [horizontalNeighbour]. With
      // nothing on this line towards the bar, the press falls through to the
      // bar below.
      final target = horizontalNeighbour(currentNode, direction, towardsSidebar: direction == towardsSidebar);
      if (target != null && _onSameLine(currentNode, target)) {
        target.requestFocus();
        _revealSideways(target, direction);
        handled = true;
      } else if (_scrollSideways(currentNode, direction)) {
        // Nothing further along this line is built yet - the dashboard's
        // carousel builds its cards as they come into view - so the line is
        // scrolled on rather than left. The next press finds the card that
        // has appeared.
        handled = true;
      } else if (target != null) {
        target.requestFocus();
        handled = true;
      }
    }
    if (debugTraceFocusMoves) {
      final scope = currentNode.enclosingScope;
      final policy = FocusTraversalGroup.maybeOfNode(currentNode);
      debugPrint('[move] $direction handled=$handled policy=${policy.runtimeType} '
          'scope=${scope?.debugLabel ?? scope.runtimeType} from=${currentNode.debugLabel ?? currentNode.context?.widget.runtimeType}');
    }
    // Up out of the top of a page goes to SyncPlay and Cast, which float over
    // the content in the corner and so appear in no reading order that pressing
    // up could follow. Same arrangement as the sidebar below.
    if (!handled && direction == TraversalDirection.up) {
      final anchor = chromeActionsAnchor;
      final target =
          anchor?.traversalDescendants.where((node) => node.canRequestFocus && _onCurrentRoute(node)).firstOrNull;
      if (target != null) {
        lastMainFocus = currentNode;
        target.requestFocus();
        return true;
      }
    }

    if (!handled && direction == towardsSidebar) {
      lastMainFocus = currentNode;
      if (focusNavBar()) return true;
    }

    return handled;
  }
}

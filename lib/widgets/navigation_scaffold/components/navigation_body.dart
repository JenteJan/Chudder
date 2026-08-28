import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/routes/auto_router.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((value) {
      ref.read(viewsProvider.notifier).fetchViews();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasOverlay = AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual ||
        homeRoutes.any((element) => element.name.contains(context.router.current.name));

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
      child: FocusTraversalGroup(
        policy: GlobalFallbackTraversalPolicy(fallbackNode: navBarNode),
        child: switch (AdaptiveLayout.layoutOf(context)) {
          ViewSize.phone => paddedChild(),
          ViewSize.tablet => hasOverlay
              ? SideNavigationRail(
                  currentIndex: widget.currentIndex,
                  destinations: widget.destinations,
                  currentLocation: widget.currentLocation,
                  child: paddedChild(),
                  scaffoldKey: widget.drawerKey,
                )
              : paddedChild(),
          ViewSize.desktop || ViewSize.television => newTVLayout
              ? TopNavigationBar(
                  currentIndex: widget.currentIndex,
                  destinations: widget.destinations,
                  currentLocation: widget.currentLocation,
                  child: paddedChild(),
                  scaffoldKey: widget.drawerKey,
                )
              : SideNavigationRail(
                  currentIndex: widget.currentIndex,
                  destinations: widget.destinations,
                  currentLocation: widget.currentLocation,
                  child: paddedChild(),
                  scaffoldKey: widget.drawerKey,
                ),
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
      back.from.context?.mounted == true) {
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
    final chrome = chromeActionsAnchor?.traversalDescendants.where((node) => node.canRequestFocus).firstOrNull;
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
    if (node.descendants.any((child) => child.canRequestFocus)) continue;
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

Rect? _rectOf(FocusNode node) {
  final context = node.context;
  if (context == null || !context.mounted) return null;
  final ro = context.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize || !ro.attached) return null;
  return ro.localToGlobal(Offset.zero) & ro.size;
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
  final FocusNode fallbackNode;

  GlobalFallbackTraversalPolicy({required this.fallbackNode}) : super();

  @override
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
          .where((node) => node.canRequestFocus && node.context?.mounted == true)
          .firstOrNull;
      if (target != null) {
        target.requestFocus();
        return true;
      }
    }

    var handled = false;
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      handled = pageVerticalMove(currentNode, direction);
    } else {
      _lastVerticalMove = null;
      handled = super.inDirection(currentNode, direction);
      // A sideways move that ends on a bare scope - left out of the corner
      // buttons did - is a selection that has vanished: nothing shows it and
      // nothing answers the pad. Keep it where it was instead.
      if (handled && FocusManager.instance.primaryFocus is FocusScopeNode && currentNode.canRequestFocus) {
        currentNode.requestFocus();
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
      final target = anchor?.traversalDescendants.where((node) => node.canRequestFocus).firstOrNull;
      if (target != null) {
        lastMainFocus = currentNode;
        target.requestFocus();
        return true;
      }
    }

    if (!handled && direction == towardsSidebar) {
      lastMainFocus = currentNode;

      if (fallbackNode.canRequestFocus && fallbackNode.context?.mounted == true) {
        fallbackNode.requestFocus();
        return true;
      }
    }

    return handled;
  }
}

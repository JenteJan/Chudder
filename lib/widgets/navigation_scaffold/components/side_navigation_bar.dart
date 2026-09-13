import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/settings/client_settings_model.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/routes/auto_router.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/shared/animated_fade_size.dart';
import 'package:chudder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:chudder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_button.dart';
import 'package:chudder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:chudder/widgets/navigation_scaffold/components/side_navigation_buttons.dart';
import 'package:chudder/widgets/shared/custom_tooltip.dart';
import 'package:chudder/widgets/shared/horizontal_list.dart';

/// The first entry of the narrow layout's drawer: what [navBarNode] falls
/// back to while the bar over the pages is not up.
final FocusNode homeNavBarNode = FocusNode();

/// The lit entry of the bar drawn over the pages - see
/// [PersistentNavigationChrome] - or its first on a page no entry claims;
/// null while that bar is not up.
FocusNode? chromeNavBarNode;

/// Whichever bar is actually on screen: what a press off the left edge of a
/// page should land on.
FocusNode get navBarNode => chromeNavBarNode ?? homeNavBarNode;

/// Hands the selection to the bar, for a press off the left edge of a page.
/// Returns whether the bar took it.
///
/// Onto the entry that is lit - the library you are in, not back at the top
/// of the bar - scrolled into view if the rail has scrolled past it. Looked
/// up at the moment of the press, never held: the node changes with the lit
/// entry, and Home, built a frame before the bar existed, held on to one that
/// was on no bar at all, so left off the dashboard went nowhere.
bool focusNavBar() {
  final node = navBarNode;
  final context = node.context;
  if (!node.canRequestFocus || context == null || !context.mounted) return false;
  node.requestFocus();
  // Only as far as it takes: an entry already in view does not move the rail.
  Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
  Scrollable.ensureVisible(context, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  return true;
}

/// The rail's own scroll view, so a scroll can be offered to the page only when
/// the rail has nowhere of its own to go.
final ScrollController _railScrollController = ScrollController();

/// Marks the page behind the rail, so a scroll that the rail has no use for
/// can be given to it.
///
/// A local key, found by walking down from the rail, rather than a GlobalKey
/// at file scope. A GlobalKey shared by every rail that is ever alive breaks
/// the moment two are - a home route replaced while the old one is still
/// animating out is enough - and what breaks is the whole tree, every frame,
/// until the app is restarted.
const Key sideNavigationPageLayerKey = ValueKey('side_navigation_page_layer');

/// Offers the page whatever scroll the rail did not want.
///
/// [Scrollable] only claims a scroll that would actually move it, so a rail
/// with everything already in view declines and this gets its turn — and when
/// the rail does have somewhere to go, it claims the event first and this never
/// runs. The bar covers a quarter of the window on a narrow desktop; a wheel
/// over it doing nothing at all reads as the page being stuck.
void _forwardScrollToPage(BuildContext rail, PointerSignalEvent event) {
  if (event is! PointerScrollEvent) return;

  // A bar with somewhere of its own to go keeps every scroll over it, including
  // the ones at either end. Scrollable declines an event that would not move
  // it, which at the top or bottom of the rail is every one of them - and
  // handing those on meant the page crept along underneath a bar that looked
  // like it was the thing being scrolled.
  //
  // Asked of the one rail on screen. This controller is shared by every rail
  // that is alive, and during a route transition there are briefly two - at
  // which point `position` is an assertion rather than an answer, and the
  // wheel brings the whole window down with it.
  if (_railScrollController.positions.length == 1 && _railScrollController.position.maxScrollExtent > 0) return;
  GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent resolved) {
    final scroll = resolved as PointerScrollEvent;
    if (!rail.mounted) return;
    _verticalScrollableAt(rail, scroll.position)?.pointerScroll(scroll.scrollDelta.dy);
  });
}

/// The page's own scroll position at [globalPosition].
///
/// Found by walking the page's elements rather than by hit testing it: the
/// thing a [SingleChildScrollView] builds its viewport from is private, so
/// there is nothing public to recognise in a hit test path. Outermost match
/// wins, which is the scroll view the page as a whole sits in rather than any
/// list nested inside it.
ScrollPosition? _verticalScrollableAt(BuildContext rail, Offset globalPosition) {
  // The page layer is the rail's own child, a step or two down; found by its
  // key so the walk never wanders into the rail's own scroll view, which is
  // vertical and under the pointer too.
  Element? pageLayer;
  void find(Element element) {
    if (pageLayer != null) return;
    if (element.widget.key == sideNavigationPageLayerKey) {
      pageLayer = element;
      return;
    }
    element.visitChildren(find);
  }

  // The page layer is a sibling of the bar, both children of one Stack: up to
  // that Stack first, then down from there. A bar drawn as an overlay entry
  // has no such Stack; the layer is then found from the top of the tree, where
  // it sits a few steps down.
  Element? stack;
  rail.visitAncestorElements((element) {
    if (element.widget is Stack) {
      stack = element;
      return false;
    }
    return true;
  });
  (stack ?? rail).visitChildElements(find);
  if (pageLayer == null) WidgetsBinding.instance.rootElement?.visitChildren(find);
  final context = pageLayer;
  if (context == null) return null;

  ScrollPosition? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is ScrollableState) {
      final state = element.state as ScrollableState;
      final box = element.renderObject;
      // Only the route on top. A navigator keeps the pages you came from in
      // the tree and lays them out, so the first scrollable this walk meets is
      // the oldest one - and scrolling that moves a page nobody can see, which
      // is indistinguishable from the wheel doing nothing at all.
      final isCurrent = ModalRoute.of(element)?.isCurrent ?? true;
      if (isCurrent && state.position.axis == Axis.vertical && box is RenderBox && box.attached && box.hasSize) {
        if ((box.localToGlobal(Offset.zero) & box.size).contains(globalPosition)) {
          found = state.position;
          return;
        }
      }
    }
    element.visitChildren(visit);
  }

  context.visitChildElements(visit);
  return found;
}

/// The side bar's measurements, for the pages that keep clear of it.
///
/// Full width with labels, or folded to its icons - the chevron at the top of
/// the bar switches, on any window wide enough for a side bar. Windows under
/// 960 wide used to be held to the icons, with a drawer behind a menu button
/// for the labels, and that squeezed version was where things broke.
abstract final class SideNavigationRail {
  static const double expandedWidth = 200.0;

  /// How wide the bar is, for the page beside it to keep clear of.
  static double widthFor(BuildContext context, {required bool expanded}) {
    final textDirection = Directionality.of(context);
    final padding = MediaQuery.paddingOf(context);
    final startInset = EdgeInsetsDirectional.fromSTEB(padding.left, 0, padding.right, 0).resolve(textDirection).left;
    // -0.1 offset to fix single visible pixel line
    return (expanded ? expandedWidth : 90.0 + startInset) - 0.1;
  }
}

/// The bar itself, drawn over whatever is behind it: the gradient that fades
/// the page out under it, and the column of buttons.
///
/// Drawn over every page you browse by [PersistentNavigationChrome].
class SideNavigationRailOverlay extends ConsumerWidget {
  final int currentIndex;
  final List<DestinationModel> destinations;
  final String currentLocation;

  /// Whether the first entry holds [homeNavBarNode]. See [SideNavigationButtons].
  final bool useNavFocusNode;

  /// The caller's own node for each entry. See [SideNavigationButtons.focusNodeFor].
  final FocusNode? Function(DestinationModel destination)? focusNodeFor;

  /// Whether the Settings tab is showing, which lights the profile picture.
  final bool settingsSelected;

  /// The caller's own node for the profile picture, the Settings tab's entry.
  final FocusNode? settingsFocusNode;

  const SideNavigationRailOverlay({
    required this.currentIndex,
    required this.destinations,
    required this.currentLocation,
    this.useNavFocusNode = true,
    this.focusNodeFor,
    this.settingsSelected = false,
    this.settingsFocusNode,
    super.key,
  });

  /// Nothing: a route's own action stays in the corner button, where every
  /// screen has it. It used to be doubled at the top of the bar as well, so
  /// the bar grew a large button the moment you landed on Discover and lost
  /// it again on the next tab.
  AdaptiveFab? _railAction(BuildContext context) => null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;
    final expandedSideBar = ref.watch(clientSettingsProvider.select((value) => value.expandSideBar));

    const expandedWidth = SideNavigationRail.expandedWidth;

    final padding = MediaQuery.paddingOf(context);
    final directionalPadding = EdgeInsetsDirectional.fromSTEB(
      padding.left,
      padding.top,
      padding.right,
      padding.bottom,
    );
    final startInset = directionalPadding.resolve(textDirection).left;
    final tooltipPosition = isRtl ? TooltipPosition.left : TooltipPosition.right;

    final shouldExpand = expandedSideBar;
    final isDesktop = AdaptiveLayout.of(context).isDesktop;

    final railPadding = directionalPadding
        .copyWith(
          start: startInset,
          end: 0,
          top: isDesktop ? directionalPadding.top : null,
        )
        .resolve(textDirection);
    final collapsedWidth = 90.0 + startInset;

    final fullScreenChildRoute = fullScreenRoutes.contains(context.router.current.name);

    // Always true: the bar is drawn over the pages, never beside them. Kept as
    // a name because the padding helpers below still read as a question.
    const hasOverlay = true;

    // Asked of every page on the way down as well as of the root: to the root
    // router, a details page opened on a tab is just Home, and the page on
    // top of Settings is whichever of its own it has open.
    final useBlurredBackground = ref.watch(clientSettingsProvider.select(
          (value) => value.backgroundImage == BackgroundType.blurred && value.enableBlurEffects,
        )) &&
        !topBarNoBlurRoutes.contains(context.router.current.name) &&
        !context.router.root.currentSegments.any((segment) => topBarNoBlurRoutes.contains(segment.name));

    final blurWidth = (shouldExpand ? expandedWidth : collapsedWidth) + 25;

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final railAction = _railAction(context);

    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: RepaintBoundary(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: !fullScreenChildRoute ? 1 : 0,
                child: IgnorePointer(
                  child: Container(
                    width: blurWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                        end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
                        colors: [
                          surfaceColor.withAlpha(255),
                          surfaceColor.withAlpha(175),
                          surfaceColor.withAlpha(0),
                        ],
                      ),
                    ),
                    child: useBlurredBackground
                        ? ShaderMask(
                            shaderCallback: (bounds) {
                              return LinearGradient(
                                begin: isRtl ? Alignment.centerRight : Alignment.centerLeft,
                                end: isRtl ? Alignment.centerLeft : Alignment.centerRight,
                                colors: [
                                  Colors.white.withAlpha(255),
                                  Colors.white.withAlpha(175),
                                  Colors.white.withAlpha(0),
                                ],
                              ).createShader(
                                Rect.fromLTRB(0, 0, blurWidth, bounds.height),
                              );
                            },
                            blendMode: BlendMode.dstIn,
                            child: const BackgroundImage(),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            // Wrapped around the rail rather than laid behind it. Behind it, a
            // tap target only ever received the gaps between the rail's own
            // widgets, and the rail covers nearly the whole strip - so the taps
            // this is for never reached it. Above the rail every tap arrives,
            // and the gesture arena still gives a button its own tap, because a
            // button is deeper in the tree and enters the arena first.
            child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => HorizontalListOverlayTaps.nudgeRowAt(details.globalPosition),
                child: Listener(
                  onPointerSignal: (event) => _forwardScrollToPage(context, event),
                  child: FocusTraversalGroup(
                    policy: _RailTraversalPolicy(),
                    child: IgnorePointer(
                      ignoring: !hasOverlay || fullScreenChildRoute,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: !fullScreenChildRoute ? 1 : 0,
                        child: SizedBox(
                          width: shouldExpand ? expandedWidth : collapsedWidth,
                          child: Padding(
                            key: const Key('navigation_rail'),
                            padding: railPadding,
                            child: Column(
                              spacing: 2,
                              children: [
                                // A button that looks like one: a chevron that
                                // points the way the bar will go - in while it
                                // is open, out while it is folded to its icons.
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Align(
                                    alignment: shouldExpand ? AlignmentDirectional.centerStart : Alignment.center,
                                    child: IconButton(
                                      tooltip: context.localized.navigation,
                                      icon: Icon(
                                        (shouldExpand != isRtl)
                                            ? IconsaxPlusLinear.arrow_left_1
                                            : IconsaxPlusLinear.arrow_right_3,
                                      ),
                                      onPressed: () => ref.read(clientSettingsProvider.notifier).toggleSideBar(),
                                    ),
                                  ),
                                ),
                                if (railAction != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4)
                                        .copyWith(bottom: shouldExpand ? 10 : 0),
                                    child: AnimatedFadeSize(
                                      duration: const Duration(milliseconds: 250),
                                      // Also in the corner, deliberately: the corner
                                      // button is the one every screen has, this one
                                      // is where the desktop's other actions live.
                                      child: shouldExpand ? railAction.extended : railAction.normal,
                                    ),
                                  ),
                                // Everything between the collapse button and the
                                // profile scrolls when the rail runs out of room: the
                                // destinations, the playback cluster and the library
                                // list are otherwise fixed height, and a short window
                                // simply overflowed them.
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) => SingleChildScrollView(
                                      controller: _railScrollController,
                                      // A scroll view claims everything over it by
                                      // default, and this one spans the whole bar -
                                      // which is why the expanded bar swallowed
                                      // clicks and wheels in all the empty space
                                      // beside its buttons. Deferring to its children
                                      // leaves that space to the page behind, while
                                      // the buttons still scroll the rail when the
                                      // rail has somewhere to go.
                                      hitTestBehavior: HitTestBehavior.deferToChild,
                                      child: ConstrainedBox(
                                        // At least as tall as the rail, so a rail
                                        // with room to spare still centres its
                                        // destinations the way it always has.
                                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                        // No IntrinsicHeight: it lays this subtree
                                        // out twice on every resize, and toggling
                                        // full screen is one big resize. The minimum
                                        // height is enough on its own.
                                        child: SideNavigationButtons(
                                          largeBar: true,
                                          destinations: destinations,
                                          tooltipPosition: tooltipPosition,
                                          currentIndex: currentIndex,
                                          shouldExpand: shouldExpand,
                                          useNavFocusNode: useNavFocusNode,
                                          focusNodeFor: focusNodeFor,
                                          // The list scrolls now, so it does not need
                                          // to hide items behind a "more" menu to fit.
                                          useOverflow: false,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                NavigationButton(
                                  label: context.localized.settings,
                                  selected: settingsSelected,
                                  focusNode: settingsFocusNode,
                                  selectedIcon: const Icon(IconsaxPlusBold.setting_3),
                                  horizontal: true,
                                  expanded: shouldExpand,
                                  icon: const SizedBox.shrink(),
                                  customIcon: const ExcludeFocusTraversal(
                                      child: SizedBox.square(dimension: 40, child: SettingsUserIcon())),
                                  onPressed: () => showHomeTab(context.router.root, HomeTabs.settings),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )),
          ),
        ),
      ],
    );
  }
}

class _RailTraversalPolicy extends ReadingOrderTraversalPolicy {
  _RailTraversalPolicy();

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final isRtl = Directionality.of(currentNode.context!) == TextDirection.rtl;
    final toMainDirection = isRtl ? TraversalDirection.left : TraversalDirection.right;
    final awayFromMainDirection = isRtl ? TraversalDirection.right : TraversalDirection.left;

    if (direction == awayFromMainDirection) {
      return false;
    }
    if (direction == toMainDirection) {
      // Back onto the page, and never by a directional search: the bar's
      // scope is the navigator's, which holds every page on the stack and
      // the tabs that are not showing, and the search picked from those.
      _pageTarget(currentNode)?.requestFocus();
      return true;
    }
    if (direction == TraversalDirection.up || direction == TraversalDirection.down) {
      final scope = currentNode.enclosingScope;
      if (scope == null) {
        return false;
      }

      final candidates = scope.traversalDescendants
          .where((n) => n.canRequestFocus && FocusTraversalGroup.maybeOfNode(n) == this && _isLaidOut(n))
          .toList();

      if (candidates.isEmpty) return false;

      final sorted = sortDescendants(candidates, currentNode).toList();

      var index = sorted.indexOf(currentNode);
      if (index == -1) {
        index = direction == TraversalDirection.down ? -1 : sorted.length;
      }

      final nextIndex = direction == TraversalDirection.down ? index + 1 : index - 1;

      if (nextIndex < 0 || nextIndex >= sorted.length) {
        return true;
      }

      // Scrolled only as far as it takes. The default puts every entry you
      // move to on the rail's bottom edge, so a long rail slid under the
      // selection on every press, up as well as down.
      requestFocusCallback(
        sorted[nextIndex],
        alignmentPolicy: direction == TraversalDirection.down
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

/// Only nodes whose widget is still in the tree: see [isLiveFocusNode].
bool _isLaidOut(FocusNode node) => isLiveFocusNode(node);

/// The scope of the page the bar sits beside: the root navigator's current
/// route. The bar is an entry in that navigator's overlay rather than part of
/// any page, so a rail node's own scope is the navigator's - which holds every
/// page on the stack, the ones underneath included.
FocusScopeNode? _currentPageScope(FocusNode railNode) {
  final navigatorScope = railNode.enclosingScope;
  if (navigatorScope == null) return null;
  // Every route's scope sits straight under the navigator's; a scope inside
  // a page sits under that page's.
  for (final node in navigatorScope.descendants) {
    if (node is! FocusScopeNode || !identical(node.enclosingScope, navigatorScope)) continue;
    final context = node.context;
    if (context == null || !context.mounted) continue;
    if (ModalRoute.isCurrentOf(context) == true) return node;
  }
  return null;
}

/// Where right out of the bar goes: the control the selection left the page
/// from, else whatever the page last had selected, else its first control.
///
/// Only something on the page on top that can take the selection. A tab you
/// switched away from from the bar keeps its nodes laid out but unfocusable,
/// so going back to the control you left there did nothing at all.
FocusNode? _pageTarget(FocusNode railNode) {
  final page = _currentPageScope(railNode);
  bool usable(FocusNode? node) =>
      node != null &&
      node is! FocusScopeNode &&
      node.canRequestFocus &&
      !node.skipTraversal &&
      node.context?.mounted == true &&
      _isLaidOut(node) &&
      (page == null || node.ancestors.contains(page));

  final last = lastMainFocus;
  if (usable(last)) return last;
  if (page == null) return null;
  var remembered = page.focusedChild;
  while (remembered is FocusScopeNode) {
    remembered = remembered.focusedChild;
  }
  if (usable(remembered)) return remembered;
  return firstPageControl(page);
}

bool isNodeInCurrentRoute(FocusNode node) {
  if (!node.canRequestFocus) return false;
  if (node.context == null) return false;

  final nearestScope = FocusScope.of(node.context!);
  return nearestScope.hasFocus || nearestScope.isFirstFocus;
}

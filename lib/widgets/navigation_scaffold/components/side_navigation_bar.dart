import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/settings/client_settings_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:fladder/widgets/navigation_scaffold/components/collapse_button.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_button.dart';
import 'package:fladder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:fladder/widgets/navigation_scaffold/components/side_navigation_buttons.dart';
import 'package:fladder/widgets/shared/custom_tooltip.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';

final navBarNode = FocusNode();

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
const Key _pageLayerKey = ValueKey('side_navigation_page_layer');

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
  if (_railScrollController.hasClients && _railScrollController.position.maxScrollExtent > 0) return;
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
    if (element.widget.key == _pageLayerKey) {
      pageLayer = element;
      return;
    }
    element.visitChildren(find);
  }

  rail.visitChildElements(find);
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

class SideNavigationRail extends ConsumerWidget {
  final int currentIndex;
  final List<DestinationModel> destinations;
  final String currentLocation;
  final Widget child;
  final GlobalKey<ScaffoldState> scaffoldKey;
  const SideNavigationRail({
    required this.currentIndex,
    required this.destinations,
    required this.currentLocation,
    required this.child,
    required this.scaffoldKey,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textDirection = Directionality.of(context);
    final isRtl = textDirection == TextDirection.rtl;
    final expandedSideBar = ref.watch(clientSettingsProvider.select((value) => value.expandSideBar));

    final expandedWidth = 200.0;

    final padding = MediaQuery.paddingOf(context);
    final directionalPadding = EdgeInsetsDirectional.fromSTEB(
      padding.left,
      padding.top,
      padding.right,
      padding.bottom,
    );
    final startInset = directionalPadding.resolve(textDirection).left;
    final tooltipPosition = isRtl ? TooltipPosition.left : TooltipPosition.right;

    final largeBar = AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;
    final fullyExpanded = largeBar ? expandedSideBar : false;
    final shouldExpand = fullyExpanded;
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

    // Always true: this widget only exists inside the tabs router, and
    // details screens are siblings of Home rather than children, so there
    // is no longer a non-tab route to test for. Kept as a name because the
    // padding helpers below still read as a question.
    const hasOverlay = true;

    final useBlurredBackground = ref.watch(clientSettingsProvider.select(
          (value) => value.backgroundImage == BackgroundType.blurred && value.enableBlurEffects,
        )) &&
        !topBarNoBlurRoutes.contains(context.router.current.name);

    final blurWidth = (shouldExpand ? expandedWidth : collapsedWidth) + 25;

    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Stack(
      children: [
        AdaptiveLayout(
          key: _pageLayerKey,
          data: AdaptiveLayout.of(context).copyWith(
            // -0.1 offset to fix single visible pixel line
            sideBarWidth: (fullyExpanded ? expandedWidth : collapsedWidth) - 0.1,
          ),
          child: child,
        ),
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
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: CollapseButton(
                                    label: shouldExpand ? Expanded(child: Text(context.localized.navigation)) : null,
                                    keepVisible: !(largeBar && expandedSideBar),
                                    icon: Icon(
                                      largeBar && expandedSideBar
                                          ? IconsaxPlusLinear.sidebar_left
                                          : IconsaxPlusLinear.menu,
                                      color: Theme.of(context).colorScheme.onSurface.withValues(
                                            alpha: largeBar && expandedSideBar ? 0.65 : 1,
                                          ),
                                    ),
                                    onPressed: !largeBar
                                        ? () => scaffoldKey.currentState?.openDrawer()
                                        : () => ref
                                            .read(clientSettingsProvider.notifier)
                                            .update((state) => state.copyWith(expandSideBar: !state.expandSideBar)),
                                  ),
                                ),
                                if (largeBar)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4)
                                        .copyWith(bottom: expandedSideBar ? 10 : 0),
                                    child: AnimatedFadeSize(
                                      duration: const Duration(milliseconds: 250),
                                      // Also in the corner, deliberately: the corner
                                      // button is the one every screen has, this one
                                      // is where the desktop's other actions live.
                                      child: shouldExpand ? _railAction(context).extended : _railAction(context).normal,
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
                                      // default, and this one spans the whole bar —
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
                                          largeBar: largeBar,
                                          destinations: destinations,
                                          tooltipPosition: tooltipPosition,
                                          currentIndex: currentIndex,
                                          shouldExpand: shouldExpand,
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
                                  selected: currentLocation.contains(const SettingsRoute().routeName),
                                  selectedIcon: const Icon(IconsaxPlusBold.setting_3),
                                  horizontal: true,
                                  expanded: shouldExpand,
                                  icon: const SizedBox.shrink(),
                                  customIcon: const ExcludeFocusTraversal(
                                      child: SizedBox.square(dimension: 40, child: SettingsUserIcon())),
                                  onPressed: () {
                                    if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.single) {
                                      context.router.push(const SettingsRoute());
                                    } else {
                                      context.router.push(const ClientSettingsRoute());
                                    }
                                  },
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

extension on SideNavigationRail {
  /// The route's own action, or Search - the same pair the corner button uses,
  /// so both offer the same thing on any given screen.
  AdaptiveFab _railAction(BuildContext context) =>
      ((currentIndex >= 0 && currentIndex < destinations.length)
          ? destinations[currentIndex].floatingActionButton
          : null) ??
      DestinationModel.searchFab(context);
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
      if (lastMainFocus != null && _isLaidOut(lastMainFocus!)) {
        lastMainFocus!.requestFocus();
        return true;
      } else {
        return super.inDirection(currentNode, direction);
      }
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

      requestFocusCallback(sorted[nextIndex]);
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

bool _isLaidOut(FocusNode node) {
  final ro = node.context?.findRenderObject();
  return ro is RenderBox && ro.hasSize;
}

bool isNodeInCurrentRoute(FocusNode node) {
  if (!node.canRequestFocus) return false;
  if (node.context == null) return false;

  final nearestScope = FocusScope.of(node.context!);
  return nearestScope.hasFocus || nearestScope.isFirstFocus;
}

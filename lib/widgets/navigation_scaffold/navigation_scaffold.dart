import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/providers/views_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/screens/home_screen.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/screens/shared/nested_bottom_appbar.dart';
import 'package:fladder/screens/video_player/audio_player_full_screen.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/destination_model.dart';
import 'package:fladder/widgets/navigation_scaffold/components/fladder_app_bar.dart';
import 'package:fladder/widgets/navigation_scaffold/components/floating_player_bar.dart';
import 'package:fladder/widgets/navigation_scaffold/components/floating_video_window.dart';
import 'package:fladder/widgets/navigation_scaffold/components/playback_chrome_actions.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_drawer.dart';
import 'package:fladder/widgets/shared/animated_visibility.dart';
import 'package:fladder/widgets/shared/hide_on_scroll.dart';
import 'package:fladder/widgets/shared/status_banners.dart';
import 'package:fladder/widgets/split_area/split_area.dart';

class NavigationScaffold extends ConsumerStatefulWidget {
  /// Index into [destinations] of the active tab, or -1 when none matches.
  final int currentIndex;
  final Widget? nestedChild;
  final List<DestinationModel> destinations;
  final GlobalKey<NavigatorState>? nestedNavigatorKey;
  const NavigationScaffold({
    required this.currentIndex,
    this.nestedChild,
    required this.destinations,
    this.nestedNavigatorKey,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _NavigationScaffoldState();
}

class _NavigationScaffoldState extends ConsumerState<NavigationScaffold> {
  final GlobalKey<ScaffoldState> _key = GlobalKey();

  /// Watches for playback that is running with nothing on screen to show it.
  Timer? _orphanedPlaybackTimer;

  int get currentIndex => widget.currentIndex;

  /// The active destination's route name, for the pieces that still
  /// label themselves with it. Derived from the index rather than the
  /// other way round.
  String get currentLocation =>
      widget.destinations.elementAtOrNull(currentIndex)?.route?.routeName ?? 'Nothing';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((value) {
      ref.read(viewsProvider.notifier).fetchViews();
      context.router.addListener(() {
        _key.currentState?.closeDrawer();
      });
    });
  }

  @override
  void dispose() {
    _orphanedPlaybackTimer?.cancel();
    super.dispose();
  }

  /// Anything playing must be visible somewhere.
  ///
  /// The player is shown by one of two things: the full-screen route, or the
  /// minimized surfaces (the floating window, or the bar). Which one is decided
  /// by [VideoPlayerState] - and `fullScreen` with no route on screen shows
  /// neither. Media then plays on with nothing to see and nothing to press,
  /// which is where "it starts the audio but no player appears" keeps coming
  /// from: resuming group playback, an item switch that skipped its push, a
  /// route popped from under a start that was still in flight. Each of those
  /// has been patched where it happened, and another one turns up.
  ///
  /// So rather than guard every path that pushes the route, this notices the
  /// combination that cannot be right and falls back to the minimized player -
  /// there is always a way back to full screen from there.
  ///
  /// Audio is the exception: it genuinely renders full screen without the video
  /// route, so it is left alone.
  void _keepPlaybackVisible({required bool orphaned}) {
    if (!orphaned) {
      _orphanedPlaybackTimer?.cancel();
      _orphanedPlaybackTimer = null;
      return;
    }
    if (_orphanedPlaybackTimer?.isActive == true) return;

    // Long enough to sit out a route push and its transition, so this only
    // ever fires on a state that has actually settled wrong.
    _orphanedPlaybackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final stillOrphaned = ref.read(playBackModel) != null &&
          ref.read(mediaPlaybackProvider).state == VideoPlayerState.fullScreen &&
          !ref.read(isVideoPlayerRouteOpenProvider) &&
          ref.read(playBackModel)?.item is! AudioModel;
      if (!stillOrphaned) return;
      ref.read(mediaPlaybackProvider.notifier).update(
            (state) => state.copyWith(state: VideoPlayerState.minimized, fullScreen: false),
          );
    });
  }

  @override
  void didUpdateWidget(covariant NavigationScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex && currentIndex != -1) {
      Future.microtask(() {
        if (mounted) {
          ref.read(windowTitleProvider.notifier).clearStack();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = ref.watch(viewsProvider.select((value) => value.views));
    final playerState = ref.watch(mediaPlaybackProvider.select((value) => value.state));
    final currentItem = ref.watch(playBackModel.select((value) => value?.item));
    final playerMinimized = playerState == VideoPlayerState.minimized;
    // A minimized video floats in its own little window; everything else the
    // minimized player handles keeps the bottom bar.
    final showPlayerWindow = playerMinimized && useFloatingVideoWindow(context, ref);
    final showPlayerBar = playerMinimized && !showPlayerWindow;
    final showAudioFullScreen = playerState == VideoPlayerState.fullScreen && currentItem is AudioModel;
    final showAudioSidePanel = showAudioFullScreen && AdaptiveLayout.layoutModeOf(context) == LayoutMode.dual;

    _keepPlaybackVisible(
      orphaned: currentItem != null &&
          playerState == VideoPlayerState.fullScreen &&
          !ref.watch(isVideoPlayerRouteOpenProvider) &&
          currentItem is! AudioModel,
    );
    final showAudioOverlay = showAudioFullScreen && !showAudioSidePanel;

    final isDesktop = AdaptiveLayout.of(context).isDesktop || kIsWeb;

    final mediaQuery = MediaQuery.of(context);

    final paddingOf = mediaQuery.padding;
    final viewPaddingOf = mediaQuery.viewPadding;

    final bottomPadding = isDesktop ? 12.0 : paddingOf.bottom;
    final bottomViewPadding = isDesktop ? 12.0 : viewPaddingOf.bottom;
    final isHomeScreen = currentIndex != -1;

    final calculatedBottomViewPadding =
        showPlayerBar ? floatingPlayerHeight(context) + bottomViewPadding : bottomViewPadding;

    final currentTab =
        HomeTabs.values.elementAtOrNull(currentIndex.clamp(0, HomeTabs.values.length - 1)) ?? HomeTabs.dashboard;

    final fullScreenChildRoute = fullScreenRoutes.contains(context.router.current.name);

    Widget buildMainScaffold(BuildContext scaffoldContext) {
      return Scaffold(
        key: _key,
        appBar: fullScreenChildRoute || showAudioFullScreen
            ? null
            : FladderAppBar(
                isDesktop: isDesktop,
                label: currentIndex == -1 ? "" : null,
              ),
        extendBodyBehindAppBar: true,
        resizeToAvoidBottomInset: false,
        extendBody: true,
        // Bottom right on every layout, and on every overview screen: the
        // screen's own action where it has one, Search everywhere else. It used
        // to be the phone's alone, with desktop hiding the same action away in
        // the navigation bar instead.
        floatingActionButton: !showAudioFullScreen && isHomeScreen
            ? widget.destinations.elementAtOrNull(currentIndex)?.fabWidget ??
                DestinationModel.searchFab(scaffoldContext).normal
            : null,
        // Attached whenever the audio overlay is not up, rather than only on
        // routes we currently believe we are on. The hamburger that opens it
        // is only ever rendered by the home screens anyway, and tying the
        // drawer's EXISTENCE to a route name meant any stale name left the
        // button pressing a Scaffold with no drawer - visible, and inert.
        drawer: !showAudioFullScreen
            ? NestedNavigationDrawer(
                toggleExpanded: (value) => _key.currentState?.closeDrawer(),
                views: views,
                destinations: widget.destinations,
                currentLocation: currentLocation,
                currentIndex: currentIndex,
              )
            : null,
        bottomNavigationBar: AnimatedVisibility(
          visible:
              !showAudioFullScreen && (isHomeScreen && AdaptiveLayout.viewSizeOf(scaffoldContext) == ViewSize.phone),
          hiddenHeight: calculatedBottomViewPadding,
          duration: const Duration(milliseconds: 250),
          child: HideOnScroll(
            controller: AdaptiveLayout.scrollOf(scaffoldContext, currentTab),
            // Details screens are siblings of Home now, not children, so
            // anything built here is on a tab by construction.
            forceHide: false,
            child: NestedBottomAppBar(
              child: SizedBox(
                height: 65,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.destinations
                      .map(
                        (destination) => destination.toNavigationButton(
                          widget.destinations.indexOf(destination) == currentIndex,
                          false,
                          false,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
        body: widget.nestedChild != null
            ? NavigationBody(
                child: widget.nestedChild!,
                parentContext: scaffoldContext,
                currentIndex: currentIndex,
                destinations: widget.destinations,
                currentLocation: currentLocation,
                drawerKey: _key,
              )
            : null,
      );
    }

    final Widget audioOverlay = showAudioFullScreen
        ? const AudioPlayerFullScreen(
            key: ValueKey("audio_full_screen"),
          )
        : const SizedBox.shrink();

    // Back means "go to the first tab" only while we are ON a tab. A details
    // screen, settings or the player is not a destination, so currentIndex is
    // -1 there - and treating that as "not the first tab" turned every back
    // gesture on those screens into a navigate() to the Dashboard. auto_route
    // then reshuffled the stack to surface it, deleting the tab routes
    // underneath; a few pops later the stack no longer matched anything the
    // navigation knew, which is what took the drawer away with it.
    // Three cases, in order:
    //  - the router has something to pop (a details screen, settings, the
    //    player): pop it. This used to be treated as "a tab that is not the
    //    first" because currentIndex is -1 off-tab, so back called navigate()
    //    to the Dashboard instead; auto_route then surfaced it by deleting the
    //    tab routes underneath, and a few pops later nothing matched the
    //    navigation any more - which is what took the drawer with it.
    //  - nothing to pop but we are on a later tab: go to the first tab.
    //  - nothing to pop and already on the first tab: let the app close.
    final routerCanPop = context.router.canPop();
    return PopScope(
      canPop: !showAudioOverlay && !routerCanPop && currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (showAudioOverlay) {
          return;
        }
        if (routerCanPop) {
          context.router.maybePop();
          return;
        }
        if (currentIndex != 0) {
          widget.destinations.first.action!();
        }
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                padding: paddingOf.copyWith(
                  bottom: showPlayerBar ? floatingPlayerHeight(context) + 12 + bottomPadding : bottomPadding,
                ),
                viewPadding: viewPaddingOf.copyWith(
                  top: mediaQuery.viewPadding.top,
                  bottom: calculatedBottomViewPadding,
                ),
              ),
              child: SplitArea(
                axis: Axis.horizontal,
                areas: [
                  Area(
                    initialArea: 0.7,
                  ),
                  Area(
                    initialArea: 0.3,
                    minArea: 0.2,
                    maxArea: 0.5,
                    constraints: const BoxConstraints(minWidth: 200, maxWidth: 500),
                  ),
                ],
                children: [
                  buildMainScaffold(context),
                  if (showAudioSidePanel)
                    SizedBox(
                      width: double.infinity,
                      child: audioOverlay,
                    ),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: AnimatedFadeSize(
              child: SizedBox(
                width: double.infinity,
                child: showPlayerBar ? const FloatingPlayerBar() : const SizedBox.shrink(),
              ),
            ),
          ),
          // Sticky in the corner, over the content: the desktop rail used to
          // carry these, where they scrolled away with it and sat nowhere near
          // the phone's. The phone has them in its app bar, and the TV's
          // expanded layout in its top bar, where a d-pad can still reach them.
          //
          // A television that is *not* on that expanded layout falls back to
          // the side rail, which carries them nowhere - so from a sofa there
          // was no way to join a group or pick a device without starting
          // something playing first. It gets the desktop's corner pair, in the
          // desktop's position, rather than a placement of its own.
          //
          // Overview screens only: a detail screen has its own button row and
          // carries them there, and this would land on top of it.
          if (!showAudioFullScreen &&
              !fullScreenChildRoute &&
              isHomeScreen &&
              AdaptiveLayout.viewSizeOf(context) != ViewSize.phone &&
              (AdaptiveLayout.viewSizeOf(context) < ViewSize.television ||
                  !ref.watch(clientSettingsProvider.select((value) => value.useTVExpandedLayout))))
            Positioned(
              // Directly under the window's close button, plus a little air so
              // they don't sit flush against the title bar. The title bar's
              // height is already in the padding here, so adding it again is
              // what left a gap the size of a second title bar.
              top: (isDesktop ? defaultTitleBarHeight : paddingOf.top) + 6,
              right: 8,
              child: const PlaybackChromeActions(),
            ),
          if (showPlayerWindow) const Positioned.fill(child: FloatingVideoWindow()),
          if (showAudioOverlay) audioOverlay,
          if (!AdaptiveLayout.of(context).isDesktop) const Align(alignment: Alignment.topCenter, child: StatusBanners())
        ],
      ),
    );
  }
}

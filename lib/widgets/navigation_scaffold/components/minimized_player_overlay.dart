import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/routes/auto_router.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/widgets/navigation_scaffold/components/floating_player_bar.dart';
import 'package:chudder/widgets/navigation_scaffold/components/floating_video_window.dart';

/// Pages on which the minimized player is not shown at all: places a playing
/// video has no business floating over. The lock screen hides everything,
/// and the album viewer fills the screen with a picture.
const _routesWithoutOverlay = {
  LockRoute.name,
  LoginRoute.name,
  SplashRoute.name,
  PhotoViewerRoute.name,
};

/// The minimized player, above the router.
///
/// The floating window lives here on every page, Home included: up here it
/// is over the side bar as well as the content, so it can be dragged across
/// the whole app window rather than stopping at the bar's edge - and it does
/// not get covered when a details page, a sibling of Home on the root stack,
/// opens over the scaffold.
///
/// The bar is another matter. On Home it belongs inside the scaffold, where
/// it pushes the content up and the tabs know about it; this overlay only
/// carries it over the pages that are not Home, where the film used to play
/// on with nothing to see and nothing to press until the page was left.
class MinimizedPlayerOverlay extends ConsumerWidget {
  const MinimizedPlayerOverlay({required this.router, super.key});

  final AutoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minimized = ref.watch(mediaPlaybackProvider.select((value) => value.state == VideoPlayerState.minimized));
    final playerRouteOpen = ref.watch(isVideoPlayerRouteOpenProvider);
    if (!minimized || playerRouteOpen) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: router,
      builder: (context, _) {
        final routeName = router.current.name;
        if (_routesWithoutOverlay.contains(routeName)) return const SizedBox.shrink();
        final asWindow = useFloatingVideoWindow(context, ref);
        if (!asWindow && routeName == HomeRoute.name) return const SizedBox.shrink();
        return Material(
          type: MaterialType.transparency,
          child: asWindow
              ? const FloatingVideoWindow()
              : const Align(
                  alignment: Alignment.bottomCenter,
                  child: FloatingPlayerBar(),
                ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/widgets/navigation_scaffold/components/floating_player_bar.dart';
import 'package:fladder/widgets/navigation_scaffold/components/floating_video_window.dart';

/// Pages on which the minimized player is not shown by this overlay.
///
/// Home carries the player itself, inside its scaffold, where the bar can
/// push the content up and the tabs know about it. The rest are places a
/// playing video has no business floating over: settings and the admin
/// panel are for reading, the lock screen hides everything, and the album
/// viewer fills the screen with a picture.
const _routesWithoutOverlay = {
  HomeRoute.name,
  SettingsRoute.name,
  ControlPanelRoute.name,
  LockRoute.name,
  LoginRoute.name,
  SplashRoute.name,
  PhotoViewerRoute.name,
};

/// The minimized player over the pages that are not Home.
///
/// The floating window and the bar live in Home's scaffold, so opening a
/// details page - a sibling of Home on the root stack - covered them, and
/// the film played on with nothing to see and nothing to press until the
/// page was left. This sits above the router, and shows the same surfaces
/// over whichever page is on top.
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
        if (_routesWithoutOverlay.contains(router.current.name)) return const SizedBox.shrink();
        final asWindow = useFloatingVideoWindow(context, ref);
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

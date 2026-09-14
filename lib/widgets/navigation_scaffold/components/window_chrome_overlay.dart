import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/routes/auto_router.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/shared/default_title_bar.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';

/// Root pages that draw the title bar themselves: Home through its
/// scaffold's app bar, the login screen through its own, and the photo viewer
/// inside its controls. The player does too, and is covered by the
/// route-open flag below rather than a name, since it is not a router page.
const _routesWithOwnTitleBar = {
  HomeRoute.name,
  LoginRoute.name,
  PhotoViewerRoute.name,
};

/// The window's own buttons - minimise, maximise, close - and the drag area
/// beside them, over every root page that does not draw them itself.
///
/// They used to come from the Home scaffold's app bar, which every page sat
/// inside. Since details, settings and the rest became siblings of Home on
/// the root stack, those pages had no bar at all: the space for it was still
/// reserved at the top, and the strip above the router still moved the
/// window, but there was nothing to press. Every page reserves the bar's
/// height, so the bar can be drawn here for all of them.
class WindowChromeOverlay extends ConsumerWidget {
  const WindowChromeOverlay({required this.router, super.key});

  final AutoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.windows && platform != TargetPlatform.linux && platform != TargetPlatform.macOS) {
      return const SizedBox.shrink();
    }
    // The player brings a title bar of its own, so this one goes while the
    // player is up. Faded rather than dropped: it sits above the player, and
    // the player opens by growing its picture over the page while the black
    // fades in behind it - a bar that vanished the frame that started was
    // the one thing in the picture that jumped.
    final playerOpen = ref.watch(isVideoPlayerRouteOpenProvider);

    return ListenableBuilder(
      listenable: router,
      builder: (context, _) {
        if (_routesWithOwnTitleBar.contains(router.current.name)) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: defaultTitleBarHeight,
            width: double.infinity,
            child: IgnorePointer(
              ignoring: playerOpen,
              child: ExcludeFocus(
                excluding: playerOpen,
                child: AnimatedOpacity(
                  opacity: playerOpen ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: const Material(
                    type: MaterialType.transparency,
                    child: DefaultTitleBar(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

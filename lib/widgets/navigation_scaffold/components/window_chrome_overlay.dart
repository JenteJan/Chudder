import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/routes/auto_router.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/shared/default_title_bar.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

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
    if (ref.watch(isVideoPlayerRouteOpenProvider)) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: router,
      builder: (context, _) {
        if (_routesWithOwnTitleBar.contains(router.current.name)) return const SizedBox.shrink();
        return const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: defaultTitleBarHeight,
            width: double.infinity,
            child: Material(
              type: MaterialType.transparency,
              child: DefaultTitleBar(),
            ),
          ),
        );
      },
    );
  }
}

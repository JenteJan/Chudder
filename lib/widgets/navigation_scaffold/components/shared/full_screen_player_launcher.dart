import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/router_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/minimized_video_surfaces.dart';
import 'package:chudder/screens/video_player/video_player_route.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Shared "go back to the full screen player" behaviour for the widgets that
/// stand in for the player while it is minimized (the bar and the floating
/// window).
mixin FullScreenPlayerLauncher<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Future<void> openFullScreenPlayer() async {
    final item = ref.read(playBackModel.select((value) => value?.item));
    if (item is AudioModel) {
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));
      if (mounted) {
        await context.refreshData();
      }
      return;
    }
    // Where the picture is now: the player grows out of it.
    //
    // The state is not flipped to fullScreen here, though it used to be. The
    // player's route spends its first frame offstage (the navigator measures
    // heroes that way, whether or not there are any), so flipping it now
    // took this surface down a frame before the player could be seen - a
    // blink of the page where the picture had been. The player flips it
    // itself once it is up, and this surface leaves in the frame the picture
    // arrives.
    final from = MinimizedVideoSurfaces.top;
    // The surfaces this serves can sit above the router - over a details
    // page, where the scaffold's own copy is covered - and a context there
    // has no Navigator to ask. The root router's is the one wanted either way.
    final navigator =
        Navigator.maybeOf(context, rootNavigator: true) ?? ref.read(routerProvider)?.navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(VideoPlayerRoute(from: from));
    // We can unmount while the full-screen player is open (e.g. casting
    // started and swapped the player), leaving this State defunct. Read the
    // State's own `mounted` flag — touching `context` once unmounted throws.
    if (!mounted) return;
    if (AdaptiveLayout.of(context).isDesktop || kIsWeb) {
      await fullScreenHelper.closeFullScreen(ref);
    }
    if (mounted) {
      await context.refreshData();
    }
  }
}

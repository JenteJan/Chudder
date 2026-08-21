import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/video_player.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/refresh_state.dart';

/// Shared "go back to the full screen player" behaviour for the widgets that
/// stand in for the player while it is minimized (the bar and the floating
/// window).
mixin FullScreenPlayerLauncher<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Future<void> openFullScreenPlayer() async {
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));
    final item = ref.read(playBackModel.select((value) => value?.item));
    if (item is AudioModel) {
      if (mounted) {
        await context.refreshData();
      }
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) {
          return const VideoPlayer();
        },
      ),
    );
    // We can unmount while the full-screen player is open (e.g. casting
    // started and swapped the player), leaving this State defunct. Read the
    // State's own `mounted` flag — touching `context` once unmounted throws.
    if (!mounted) return;
    if (AdaptiveLayout.of(context).isDesktop || kIsWeb) {
      final fullScreen = await windowManager.isFullScreen();
      if (fullScreen) {
        await windowManager.setFullScreen(false);
      }
    }
    if (mounted) {
      await context.refreshData();
    }
  }
}

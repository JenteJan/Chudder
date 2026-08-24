import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/components/video_player_guide_wrapper.dart';
import 'package:fladder/screens/video_player/components/video_player_next_wrapper.dart';
import 'package:fladder/screens/video_player/video_player_controls.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/themes_data.dart';
import 'package:fladder/widgets/shared/ambient_blur.dart';
import 'package:fladder/widgets/shared/back_intent_dpad.dart';

class VideoPlayer extends ConsumerStatefulWidget {
  const VideoPlayer({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends ConsumerState<VideoPlayer> with WidgetsBindingObserver {
  double lastScale = 0.0;

  bool errorPlaying = false;

  late PlaybackModel? currentPlaybackModel = ref.read(playBackModel);

  /// Empty-player guard: when playback fully ends underneath the open route
  /// (e.g. leaving a SyncPlay group stops and clears everything), the screen
  /// would linger as an empty player. If the emptiness persists — item
  /// switches and SyncPlay reloads null the model only briefly — close
  /// ourselves.
  Timer? _emptyCloseTimer;

  void _guardEmptyPlayer() {
    final model = ref.read(playBackModel);
    final playerState = ref.read(mediaPlaybackProvider).state;
    final switching = ref.read(syncPlayStartPlaybackInProgressProvider);
    final empty = model == null && playerState == VideoPlayerState.disposed && !switching;
    if (!empty) {
      _emptyCloseTimer?.cancel();
      _emptyCloseTimer = null;
      return;
    }
    _emptyCloseTimer ??= Timer(const Duration(milliseconds: 1200), () {
      _emptyCloseTimer = null;
      if (!mounted) return;
      final stillEmpty = ref.read(playBackModel) == null &&
          ref.read(mediaPlaybackProvider).state == VideoPlayerState.disposed &&
          !ref.read(syncPlayStartPlaybackInProgressProvider);
      if (stillEmpty && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    //Don't manage the wakelock on desktop focus loss
    if (!(AdaptiveLayout.of(context).isDesktop || kIsWeb)) {
      if (state == AppLifecycleState.resumed) {
        // Android drops the keep-screen-on flag on resume; re-apply it.
        ref.read(videoPlayerProvider).reassertWakelock();
      }
    }
  }

  @override
  void deactivate() {
    // Capture the notifier synchronously while the consumer element is
    // still alive, then defer the mutation to the next microtask to
    // avoid "Tried to modify a provider while the widget tree was
    // building" when deactivate runs inside a parent rebuild.
    try {
      final notifier = ref.read(mediaPlaybackProvider.notifier);
      // The route is gone however it was popped. The controls' minimize
      // button already clears this, but a system back gesture only lands
      // here - and a stale "route open" made the next-episode load think it
      // could go fullScreen, which vanished every minimized surface.
      final routeOpenNotifier = ref.read(isVideoPlayerRouteOpenProvider.notifier);
      final currentPlaybackState = ref.read(mediaPlaybackProvider).state;
      if (currentPlaybackState == VideoPlayerState.fullScreen) {
        Future.microtask(() {
          try {
            routeOpenNotifier.state = false;
            notifier.update(
              (state) => state.copyWith(state: VideoPlayerState.minimized),
            );
          } catch (_) {
            // ProviderContainer may already be torn down.
          }
        });
      } else {
        Future.microtask(() {
          try {
            routeOpenNotifier.state = false;
          } catch (_) {}
        });
      }
    } catch (_) {
      // ProviderContainer may already be torn down (app shutdown).
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _emptyCloseTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(isVideoPlayerRouteOpenProvider.notifier).state = true;
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));
      final orientations = ref.read(videoPlayerSettingsProvider.select((value) => value.allowedOrientations));
      SystemChrome.setPreferredOrientations(
          orientations?.isNotEmpty == true ? orientations!.toList() : DeviceOrientation.values);
      return ref.read(videoPlayerSettingsProvider.notifier).setSavedBrightness();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Close the route if playback ends for good underneath it (SyncPlay
    // leave, external stop) — listeners fire outside build, and the guard
    // itself debounces transient empty states during reloads.
    ref.listen(playBackModel, (_, __) => _guardEmptyPlayer());
    ref.listen(mediaPlaybackProvider.select((s) => s.state), (_, __) => _guardEmptyPlayer());

    final fillScreen = ref.watch(videoPlayerSettingsProvider.select((value) => value.fillScreen));
    final videoFit = ref.watch(videoPlayerSettingsProvider.select((value) => value.videoFit));
    final padding = MediaQuery.of(context).padding;

    final playerController = ref.watch(videoPlayerProvider.select((value) => value));

    // The wrapper keeps its identity when the underlying player is swapped for
    // casting, so videoPlayerProvider alone never triggers a rebuild — watch
    // the cast status too so the video/placeholder swaps on connect/disconnect
    // instead of on the next touch.
    ref.watch(castProvider.select((value) => value.status));

    // Watch playbackModel type changes to switch between normal
    // players. Guard with `mounted`: this listener can fire from an
    // async callback (e.g. media-kit's loadVideo Future) that resolves
    // after the player route has been popped/disposed - calling
    // setState then triggers a "_lifecycleState != defunct" assertion.
    ref.listen(
      playBackModel,
      (previous, next) {
        if (!mounted || next == null) {
          return;
        }
        if (previous.runtimeType != next.runtimeType) {
          setState(() {
            currentPlaybackModel = next;
            errorPlaying = false;
          });
        }
      },
    );

    ref.listen(
      videoPlayerSettingsProvider.select((value) => value.allowedOrientations),
      (previous, next) {
        if (!mounted || previous == next) {
          return;
        }
        SystemChrome.setPreferredOrientations(
          next?.isNotEmpty == true ? next!.toList() : DeviceOrientation.values,
        );
      },
    );

    final player = Padding(
      padding: fillScreen ? EdgeInsets.zero : EdgeInsets.only(left: padding.left, right: padding.right),
      child: playerController.videoWidget(
        const Key("VideoPlayer"),
        fillScreen ? (MediaQuery.of(context).orientation == Orientation.portrait ? videoFit : BoxFit.cover) : videoFit,
      ),
    );

    return PopScope(
      // Runs at the very START of the pop, unlike deactivate (which fires
      // after the transition ends): flipping to minimized here mounts the
      // floating window / mini bar while the route is still animating out,
      // so its Hero has a flight partner. A back-gesture minimize used to
      // just jump-cut for exactly this reason.
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        ref.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
        if (ref.read(mediaPlaybackProvider).state == VideoPlayerState.fullScreen) {
          ref.read(mediaPlaybackProvider.notifier).update(
                (state) => state.copyWith(state: VideoPlayerState.minimized),
              );
        }
      },
      child: BackIntentDpad(
        child: Material(
          color: Colors.black,
          child: Theme(
            data: ThemesData.of(context).dark,
            child: Container(
              color: Colors.black,
              child: GestureDetector(
                onScaleUpdate: (details) {
                  lastScale = details.scale;
                },
                onScaleEnd: (details) {
                  if (lastScale < 1.0) {
                    ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(false, context: context);
                  } else if (lastScale > 1.0) {
                    ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(true, context: context);
                  }
                  lastScale = 0.0;
                },
                child: Stack(children: [
                  if (!kIsWeb && ref.watch(videoPlayerSettingsProvider.select((value) => value.ambientBlur)))
                    AmbientBlur(
                      child: playerController.videoWidget(
                            const Key("VideoPlayerBlur"),
                            BoxFit.cover,
                          ) ??
                          const SizedBox.shrink(),
                    ),
                  switch (currentPlaybackModel) {
                    TvPlaybackModel _ => VideoPlayerGuideWrapper(
                        key: const Key("VideoPlayerGuideWrapper"),
                        child: player,
                      ),
                    _ => VideoPlayerNextWrapper(
                        video: player,
                        controls: const DesktopControls(),
                        overlays: [
                          if (errorPlaying) const _VideoErrorWidget(),
                        ],
                      ),
                  }
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoErrorWidget extends StatelessWidget {
  const _VideoErrorWidget();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_rounded,
            size: 46,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(
            "Error playing file",
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}

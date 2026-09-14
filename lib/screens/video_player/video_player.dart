import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/tv_playback_model.dart';
import 'package:chudder/providers/cast_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/flying_video.dart';
import 'package:chudder/screens/video_player/components/video_player_guide_wrapper.dart';
import 'package:chudder/screens/video_player/components/video_player_next_wrapper.dart';
import 'package:chudder/screens/video_player/video_player_controls.dart';
import 'package:chudder/screens/video_player/video_player_route.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/themes_data.dart';
import 'package:chudder/widgets/shared/ambient_blur.dart';
import 'package:chudder/widgets/shared/back_intent_dpad.dart';

class VideoPlayer extends ConsumerStatefulWidget {
  const VideoPlayer({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends ConsumerState<VideoPlayer> with WidgetsBindingObserver {
  double lastScale = 0.0;

  bool errorPlaying = false;

  late PlaybackModel? currentPlaybackModel = ref.read(playBackModel);

  /// The route this is on, when it is one that flies (see [VideoPlayerRoute]).
  VideoPlayerRoute? _route;

  /// Whether the opening is over: the picture has landed, and the controls
  /// and the ambient glow may come up over it. False again from the moment
  /// the route starts closing, so they get out of the way of the picture
  /// shrinking back into its window.
  bool _settled = true;

  /// The black behind the picture: up over the page as the picture grows,
  /// and down again as it shrinks - earlier on the way back, so the page is
  /// there to land on.
  Animation<double> _backdrop = kAlwaysCompleteAnimation;

  /// Everything at once, for an opening with nothing to grow out of.
  Animation<double> _entrance = kAlwaysCompleteAnimation;

  /// The controls: up over the last stretch of the flight, so they are there
  /// the moment the picture lands rather than a beat after it - a bare
  /// picture with nothing on it read as a gap - and gone in the first
  /// stretch of the way back.
  Animation<double> _controls = kAlwaysCompleteAnimation;

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = VideoPlayerRoute.of(context);
    if (route == _route) return;
    _detachRoute();
    _route = route;
    if (route == null) {
      _settled = true;
      return;
    }
    final animation = route.animation!;
    animation.addStatusListener(_onFlightStatus);
    // Offstage - the route's first frame - the animation stands in as
    // completed; taking that at its word had the controls up for that frame
    // and fading out over the start of the flight.
    _settled = !route.offstage && animation.isCompleted;
    _backdrop = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.6, curve: Curves.easeOut),
      reverseCurve: const Interval(0.35, 1, curve: Curves.easeIn),
    );
    _entrance = route.from == null ? _ForwardFade(animation) : kAlwaysCompleteAnimation;
    _controls = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.55, 1, curve: Curves.easeOut),
      reverseCurve: const Interval(0.8, 1, curve: Curves.easeIn),
    );
  }

  void _detachRoute() {
    _route?.animation?.removeStatusListener(_onFlightStatus);
    for (final animation in [_backdrop, _controls]) {
      if (animation is CurvedAnimation) animation.dispose();
    }
    _backdrop = kAlwaysCompleteAnimation;
    _entrance = kAlwaysCompleteAnimation;
    _controls = kAlwaysCompleteAnimation;
  }

  void _onFlightStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled != _settled && mounted) setState(() => _settled = settled);
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
    _detachRoute();
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

    // The picture's own shape, so the flight can end on exactly the rect the
    // fit puts it in - the same shape the floating window takes.
    final videoSize = ref.watch(playBackModel.select((value) {
      final video = value?.mediaStreams?.videoStreams.firstOrNull;
      if (video == null || video.width <= 0 || video.height <= 0) return null;
      return Size(video.width.toDouble(), video.height.toDouble());
    }));
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final fit = fillScreen ? (portrait ? videoFit : BoxFit.cover) : videoFit;

    final player = FlyingVideo(
      videoSize: videoSize,
      fit: fit,
      padding: fillScreen ? EdgeInsets.zero : EdgeInsets.only(left: padding.left, right: padding.right),
      child: playerController.videoWidget(const Key("VideoPlayer"), FlyingVideo.textureFit(fit)) ??
          const SizedBox.shrink(),
    );

    return PopScope(
      // Runs at the very START of the pop, unlike deactivate (which fires
      // after the transition ends): flipping to minimized here mounts the
      // floating window / mini bar while the route is still animating out,
      // so the picture has somewhere to shrink into. A back-gesture minimize
      // used to just jump-cut for exactly this reason.
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
          type: MaterialType.transparency,
          child: Theme(
            data: ThemesData.of(context).dark,
            child: FadeTransition(
              opacity: _entrance,
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
                  Positioned.fill(
                    child: FadeTransition(
                      opacity: _backdrop,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                  // Only once the picture has landed: it is a second copy of
                  // the texture with a blur over it, and it would be paid for
                  // under a flight that covers it anyway.
                  if (!kIsWeb &&
                      _settled &&
                      ref.watch(videoPlayerSettingsProvider.select((value) => value.ambientBlur)))
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
                        controls: _WithThePicture(
                          reveal: _controls,
                          settled: _settled,
                          child: const DesktopControls(),
                        ),
                        overlays: [
                          if (errorPlaying)
                            _WithThePicture(
                              reveal: _controls,
                              settled: _settled,
                              child: const _VideoErrorWidget(),
                            ),
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

/// What lies over the picture: faded in as it comes in to land ([reveal]),
/// out again as it takes off, and only there to be pressed while it is down.
class _WithThePicture extends StatelessWidget {
  const _WithThePicture({required this.reveal, required this.settled, required this.child});

  final Animation<double> reveal;
  final bool settled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !settled,
      child: FadeTransition(opacity: reveal, child: child),
    );
  }
}

/// A fade in on the way forward, and nothing on the way back: an opening
/// with nowhere to grow out of fades up as a whole, but closing is the
/// picture shrinking into its window, which must not fade out from under it.
class _ForwardFade extends Animation<double> with AnimationWithParentMixin<double> {
  const _ForwardFade(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => switch (parent.status) {
        AnimationStatus.forward || AnimationStatus.dismissed => Curves.easeOut.transform(parent.value),
        AnimationStatus.reverse || AnimationStatus.completed => 1,
      };
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

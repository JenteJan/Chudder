import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/minimized_video_surfaces.dart';
import 'package:chudder/screens/video_player/video_player_route.dart';

/// The player's picture, and the way it gets there.
///
/// Landed, this is the video laid out where the fit setting puts it. While
/// the route is opening out of a minimized surface - the floating window, the
/// bar's thumbnail - it is that surface's picture growing into place, corners
/// squaring off and shadow fading as it goes; while the route is closing back
/// to one it shrinks into it the same way. One Video widget throughout: the
/// texture is never attached twice, and there is nothing to swap in at the
/// end that could arrive a frame late.
///
/// The rect is [settledRect] rather than "fill the area and let the fit sort
/// it out" so that the landing is exact: the flight ends on the very pixels
/// the settled picture occupies. [child] is therefore built with [textureFit],
/// which fills whatever rect it is given.
class FlyingVideo extends ConsumerStatefulWidget {
  const FlyingVideo({
    required this.videoSize,
    required this.fit,
    required this.padding,
    required this.child,
    super.key,
  });

  /// The stream's own frame size. Null lays the picture over the whole area.
  final Size? videoSize;

  /// How the settled picture sits in the area.
  final BoxFit fit;

  /// What the settled picture keeps clear of at the edges.
  final EdgeInsets padding;

  /// The player's video widget, built with [textureFit] of [fit].
  final Widget child;

  /// The fit to build [child] with: the picture is laid out in the rect [fit]
  /// would put it in, so filling that rect *is* [fit] - and stays so while the
  /// rect is on its way from a window of the picture's own shape.
  static BoxFit textureFit(BoxFit fit) => fit == BoxFit.fill ? BoxFit.fill : BoxFit.cover;

  /// The rect [fit] puts a [video] in, inside [area] less [padding].
  static Rect settledRect(Size area, EdgeInsets padding, Size? video, BoxFit fit) {
    final inner = padding.deflateRect(Offset.zero & area);
    if (video == null || video.isEmpty || inner.isEmpty) return inner;
    final destination = switch (fit) {
      BoxFit.fill => inner.size,
      BoxFit.none => video,
      BoxFit.scaleDown => video * min(1.0, min(inner.width / video.width, inner.height / video.height)),
      _ => applyBoxFit(fit, video, inner.size).destination,
    };
    return Alignment.center.inscribe(destination, inner);
  }

  @override
  ConsumerState<FlyingVideo> createState() => _FlyingVideoState();
}

class _FlyingVideoState extends ConsumerState<FlyingVideo> {
  /// Material's emphasized curve: leaves quickly, lands softly.
  static const _curve = Curves.easeInOutCubicEmphasized;

  /// The floating window's own shadow, carried along for the first stretch.
  static final _shadow = kElevationToShadow[12]!;

  /// The route whose animation is being followed, for the flag below.
  VideoPlayerRoute? _route;

  /// Held from the start: [dispose] has to clear it, and `ref` is gone by then.
  late final StateController<bool> _inFlight = ref.read(videoPictureInFlightProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = VideoPlayerRoute.of(context);
    if (route == _route) return;
    _route?.animation?.removeStatusListener(_onStatus);
    _route = route;
    route?.animation?.addStatusListener(_onStatus);
    // A route spends its first frame offstage, and while it is its animation
    // reads as completed - the navigator stands in a finished one so the
    // heroes it measures land where they will end up. Not landed, then.
    final flying = route != null && (route.offstage || !route.animation!.isCompleted);
    // Deferred: this runs during a build, where providers can't be written.
    Future.microtask(() => _publish(flying));
  }

  @override
  void dispose() {
    _route?.animation?.removeStatusListener(_onStatus);
    final inFlight = _inFlight;
    Future.microtask(() {
      try {
        inFlight.state = false;
      } catch (_) {
        // ProviderContainer may already be torn down.
      }
    });
    super.dispose();
  }

  void _onStatus(AnimationStatus status) => _publish(status != AnimationStatus.completed);

  void _publish(bool flying) {
    if (!mounted) return;
    if (_inFlight.state != flying) _inFlight.state = flying;
  }

  @override
  Widget build(BuildContext context) {
    final route = VideoPlayerRoute.of(context);
    final animation = route?.animation ?? kAlwaysCompleteAnimation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final settled = FlyingVideo.settledRect(constraints.biggest, widget.padding, widget.videoSize, widget.fit);
        return AnimatedBuilder(
          animation: animation,
          // Built once, out here: only the box around it changes per frame.
          child: widget.child,
          builder: (context, child) {
            final frame = _frameFor(context, route, animation, settled);
            final radius = BorderRadius.circular(frame.radius);
            // The same tree whether flying or landed, so the video element -
            // and the texture behind it - lives through the change.
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: frame.rect,
                  child: Opacity(
                    opacity: frame.opacity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: radius, boxShadow: frame.shadow),
                      child: ClipRRect(
                        borderRadius: radius,
                        clipBehavior: frame.radius > 0 ? Clip.antiAlias : Clip.none,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  _Frame _frameFor(BuildContext context, VideoPlayerRoute? route, Animation<double> animation, Rect settled) {
    if (route == null) return _Frame.landed(settled);
    switch (animation.status) {
      case AnimationStatus.completed:
        return _Frame.landed(settled);
      case AnimationStatus.forward:
      case AnimationStatus.dismissed:
        final from = route.from;
        if (from == null) return _Frame.landed(settled);
        return _flight(context, from, settled, animation.value);
      case AnimationStatus.reverse:
        final to = MinimizedVideoSurfaces.top;
        if (to != null) return _flight(context, to, settled, animation.value);
        // The surface mounts the frame after the pop begins and has no rect
        // until it is laid out: hold still for it rather than start a fade
        // that would have to be undone.
        if (ref.read(mediaPlaybackProvider).state == VideoPlayerState.minimized) return _Frame.landed(settled);
        // Closing for good: nothing to shrink into, so go with the rest.
        return _Frame(rect: settled, radius: 0, opacity: animation.value, shadow: null);
    }
  }

  _Frame _flight(BuildContext context, VideoSurfaceFrame surface, Rect settled, double value) {
    final t = _curve.transform(value);
    // The surface's rect is global; ours is measured from this box. On the
    // first frame there is no box yet and the route fills the window anyway.
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.attached && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
    final from = surface.rect.shift(-origin);
    // Gone a quarter of the way in: a shadow the size of the screen is a
    // blur per frame for nothing anyone sees.
    final shade = (1 - t / 0.25).clamp(0.0, 1.0);
    return _Frame(
      rect: Rect.lerp(from, settled, t)!,
      radius: lerpDouble(surface.radius, 0, t)!,
      opacity: 1,
      shadow: shade == 0
          ? null
          : [
              for (final shadow in _shadow)
                BoxShadow(
                  color: shadow.color.withValues(alpha: shadow.color.a * shade),
                  offset: shadow.offset,
                  blurRadius: shadow.blurRadius,
                  spreadRadius: shadow.spreadRadius,
                ),
            ],
    );
  }
}

class _Frame {
  const _Frame({required this.rect, required this.radius, required this.opacity, required this.shadow});

  const _Frame.landed(this.rect)
      : radius = 0,
        opacity = 1,
        shadow = null;

  final Rect rect;
  final double radius;
  final double opacity;
  final List<BoxShadow>? shadow;
}

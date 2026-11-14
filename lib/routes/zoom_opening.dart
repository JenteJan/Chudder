import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// The platform's zoom as a page opens (Windows and Linux), drawn from a
/// picture of the page that is taken again whenever the page changes.
///
/// Flutter's zoom draws the opening page in one of two ways. From a picture
/// taken on its first frame, which costs next to nothing to scale - but the
/// page is frozen in that picture for the whole 300 ms, so the backdrop, the
/// logo and whatever else arrives on the way all appear at once as it ends.
/// Or live, every frame - which is how this app had it, and which on a large
/// window was more than the GPU could draw in a frame: the blurred artwork,
/// its fades and the gradients over them, again for every frame of the zoom,
/// just as the poster was landing.
///
/// This is the picture, taken again when something on the page changes: a
/// picture arriving, the film's details landing. A page that fills in while
/// it zooms is drawn a few times rather than every frame, and still seen to
/// fill in. Pictures are taken at most every [_retakeEvery], so a fade on the
/// page costs a few pictures rather than one a frame.
///
/// Closing is Flutter's own, from a single picture: a page that is leaving
/// has nothing more arriving.
class ZoomOpening extends StatelessWidget {
  const ZoomOpening({required this.animation, required this.child, super.key});

  final Animation<double> animation;
  final Widget child;

  /// Says something on the page changed where a repaint does not reach this
  /// far up - inside a repaint boundary of its own - so that the picture is
  /// taken again. Nothing while no zoom is running.
  static void contentChanged(BuildContext context) {
    context.findAncestorStateOfType<_ZoomEnterState>()?._changed();
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surface;
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, animation, child) =>
          _ZoomEnter(animation: animation, backgroundColor: background, child: child),
      reverseBuilder: (context, animation, child) => _ZoomClose(animation: animation, child: child),
      child: child,
    );
  }
}

/// Flutter's zoom curve (fastOutExtraSlowIn), as its zoom uses it.
final TweenSequence<double> _scaleCurve = TweenSequence<double>(<TweenSequenceItem<double>>[
  TweenSequenceItem<double>(
    tween: Tween<double>(begin: 0.0, end: 0.4).chain(CurveTween(curve: const Cubic(0.05, 0.0, 0.133333, 0.06))),
    weight: 0.166666,
  ),
  TweenSequenceItem<double>(
    tween: Tween<double>(begin: 0.4, end: 1.0).chain(CurveTween(curve: const Cubic(0.208333, 0.82, 0.25, 1.0))),
    weight: 1.0 - 0.166666,
  ),
]);

class _ZoomEnter extends StatefulWidget {
  const _ZoomEnter({required this.animation, required this.backgroundColor, this.child});

  final Animation<double> animation;
  final Color backgroundColor;
  final Widget? child;

  @override
  State<_ZoomEnter> createState() => _ZoomEnterState();
}

class _ZoomEnterState extends State<_ZoomEnter> {
  static final Animatable<double> _fade =
      Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: const Interval(0.125, 0.250)));
  static final Animatable<double> _scale = Tween<double>(begin: 0.85, end: 1.0).chain(_scaleCurve);
  static final Animatable<double> _scrim =
      Tween<double>(begin: 0.0, end: 0.60).chain(CurveTween(curve: const Interval(0.2075, 0.4175)));

  /// The shortest time between two pictures of the page.
  static const Duration _retakeEvery = Duration(milliseconds: 48);

  final SnapshotController _controller = SnapshotController();
  late _ZoomPainter _painter;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _stale = false;
  Duration? _takenAt;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _fadeAnimation = _fade.animate(widget.animation);
    _scaleAnimation = _scale.animate(widget.animation);
    _painter = _ZoomPainter(
      animation: widget.animation,
      scale: _scaleAnimation,
      fade: _fadeAnimation,
      scrim: _scrim,
      backgroundColor: widget.backgroundColor,
    );
    widget.animation
      ..addListener(_onTick)
      ..addStatusListener(_onStatus);
    _controller.allowSnapshotting = widget.animation.isAnimating;
  }

  void _unlisten(Animation<double> animation) {
    animation
      ..removeListener(_onTick)
      ..removeStatusListener(_onStatus);
    _painter.dispose();
  }

  @override
  void didUpdateWidget(_ZoomEnter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation || oldWidget.backgroundColor != widget.backgroundColor) {
      _unlisten(oldWidget.animation);
      _listen();
    }
  }

  @override
  void dispose() {
    _unlisten(widget.animation);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    _controller.allowSnapshotting = status.isAnimating;
    if (!status.isAnimating) {
      _stale = false;
      _takenAt = null;
    }
  }

  void _changed() {
    if (!_controller.allowSnapshotting) return;
    _stale = true;
  }

  /// Every frame of the zoom: a page that has changed since its picture was
  /// taken gets a new one, once the last is old enough.
  void _onTick() {
    // Done: drawn live from here. Told by the value, as Flutter's zoom is -
    // the builder above swaps this animation for a finished one as it ends,
    // so its status never says completed.
    if (_scaleAnimation.value == 1.0 && (_fadeAnimation.value == 0.0 || _fadeAnimation.value == 1.0)) {
      _controller.allowSnapshotting = false;
      _stale = false;
      _takenAt = null;
      return;
    }
    if (!_controller.allowSnapshotting) {
      if (!widget.animation.isAnimating) return;
      _controller.allowSnapshotting = true;
    }
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final takenAt = _takenAt;
    if (takenAt == null) {
      _takenAt = now;
      return;
    }
    if (!_stale || now - takenAt < _retakeEvery) return;
    _stale = false;
    _takenAt = now;
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotWidget(
      painter: _painter,
      controller: _controller,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: widget.child,
    );
  }
}

class _ZoomClose extends StatefulWidget {
  const _ZoomClose({required this.animation, this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  State<_ZoomClose> createState() => _ZoomCloseState();
}

class _ZoomCloseState extends State<_ZoomClose> {
  static final Animatable<double> _fade =
      Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: const Interval(0.0825, 0.2075)));
  static final Animatable<double> _scale = Tween<double>(begin: 1.0, end: 0.90).chain(_scaleCurve);

  final SnapshotController _controller = SnapshotController();
  late _ZoomPainter _painter;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  void _listen() {
    _scaleAnimation = _scale.animate(widget.animation);
    _fadeAnimation = _fade.animate(widget.animation);
    _painter = _ZoomPainter(animation: widget.animation, scale: _scaleAnimation, fade: _fadeAnimation);
    widget.animation
      ..addStatusListener(_onStatus)
      ..addListener(_onTick);
    _controller.allowSnapshotting = widget.animation.isAnimating;
  }

  void _onStatus(AnimationStatus status) => _controller.allowSnapshotting = status.isAnimating;

  /// As Flutter's zoom does: no picture where it would show the page as it is.
  void _onTick() {
    _controller.allowSnapshotting = widget.animation.isAnimating &&
        !(_scaleAnimation.value == 1.0 && (_fadeAnimation.value == 0.0 || _fadeAnimation.value == 1.0));
  }

  @override
  void didUpdateWidget(_ZoomClose oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation
        ..removeStatusListener(_onStatus)
        ..removeListener(_onTick);
      _painter.dispose();
      _listen();
    }
  }

  @override
  void dispose() {
    widget.animation
      ..removeStatusListener(_onStatus)
      ..removeListener(_onTick);
    _painter.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
        painter: _painter,
        controller: _controller,
        mode: SnapshotMode.permissive,
        autoresize: true,
        child: widget.child,
      );
}

/// Scales and fades the page, or the picture of it, about its centre - as
/// Flutter's zoom painters do - over a scrim of [backgroundColor] while it
/// opens.
class _ZoomPainter extends SnapshotPainter {
  _ZoomPainter({
    required this.animation,
    required this.scale,
    required this.fade,
    this.scrim,
    this.backgroundColor,
  }) {
    animation
      ..addListener(notifyListeners)
      ..addStatusListener(_onStatus);
  }

  final Animation<double> animation;
  final Animation<double> scale;
  final Animation<double> fade;
  final Animatable<double>? scrim;
  final Color? backgroundColor;

  final Matrix4 _transform = Matrix4.zero();
  final LayerHandle<OpacityLayer> _opacity = LayerHandle<OpacityLayer>();
  final LayerHandle<TransformLayer> _transformLayer = LayerHandle<TransformLayer>();

  void _onStatus(AnimationStatus _) => notifyListeners();

  void _drawScrim(PaintingContext context, Offset offset, Size size) {
    final scrim = this.scrim;
    final color = backgroundColor;
    if (scrim == null || color == null || animation.isCompleted) return;
    final opacity = scrim.evaluate(animation);
    if (opacity <= 0) return;
    context.canvas.drawRect(offset & size, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  void paint(PaintingContext context, Offset offset, Size size, PaintingContextCallback painter) {
    if (!animation.isAnimating) {
      painter(context, offset);
      return;
    }
    _drawScrim(context, offset, size);
    _transform.setIdentity();
    final s = scale.value;
    if (s != 1.0) {
      _transform
        ..scaleByDouble(s, s, s, 1)
        // As Flutter's zoom has it (_updateScaledTransform), so the live
        // frames line up with its own.
        ..translateByDouble(-(size.width * s - size.width) / 2, -(size.height * s - size.height) / 2, 0, 1);
    }
    _transformLayer.layer = context.pushTransform(true, offset, _transform, (context, offset) {
      _opacity.layer = context.pushOpacity(offset, (fade.value * 255).round(), painter, oldLayer: _opacity.layer);
    }, oldLayer: _transformLayer.layer);
  }

  @override
  void paintSnapshot(
    PaintingContext context,
    Offset offset,
    Size size,
    ui.Image image,
    Size sourceSize,
    double pixelRatio,
  ) {
    _drawScrim(context, offset, size);
    final s = scale.value;
    final opacity = fade.value;
    if (s <= 0 || opacity <= 0) return;
    final width = image.width / pixelRatio;
    final height = image.height / pixelRatio;
    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(offset.dx + (width - width * s) / 2, offset.dy + (height - height * s) / 2, width * s, height * s),
      Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }

  @override
  void dispose() {
    animation
      ..removeListener(notifyListeners)
      ..removeStatusListener(_onStatus);
    _opacity.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  bool shouldRepaint(covariant _ZoomPainter oldDelegate) => true;
}

/// Put at the top of a page that fills in as it opens, so that the opening
/// zoom takes its picture again when the page changes.
///
/// A page sits inside a repaint boundary of its route's, below the zoom, so
/// the zoom cannot see it repaint for itself. This is a repaint boundary that
/// says when anything under it - down to the next boundary - asks to be
/// painted again. Nothing while no zoom is running.
class ZoomOpeningProbe extends SingleChildRenderObjectWidget {
  const ZoomOpeningProbe({super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) {
    // Looked up once: a page is repainted on its way out too, when its
    // ancestors may no longer be asked for. The zoom is the route's, and
    // lives as long as the page does.
    final zoom = context.findAncestorStateOfType<_ZoomEnterState>();
    return _RenderRepaintProbe(() {
      if (zoom != null && zoom.mounted) zoom._changed();
    });
  }
}

class _RenderRepaintProbe extends RenderProxyBox {
  _RenderRepaintProbe(this.onRepaint);

  final VoidCallback onRepaint;

  @override
  bool get isRepaintBoundary => true;

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    onRepaint();
  }
}

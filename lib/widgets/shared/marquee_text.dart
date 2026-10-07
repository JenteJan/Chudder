import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A single line of text that fades out where it runs out of room, and slides
/// along to show the rest while [active] is true.
///
/// An ellipsis says "there is more" and then keeps it from you; a hovered or
/// selected card is the one moment somebody actually wants to read the whole
/// title, so that is when it moves. Nothing here is a scrollable: the text is
/// moved by an animation, so a wheel over it still scrolls the page it is on.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  /// Whether the text is being looked at. Null means never scroll, only fade.
  final ValueListenable<bool>? active;

  /// The width of the fade at an edge that has more text behind it.
  final double fadeWidth;

  /// How fast the text slides, in logical pixels per second.
  final double velocity;

  /// How long the text sits still before it starts, and again at the end.
  final Duration pause;

  const MarqueeText(
    this.text, {
    this.style,
    this.textAlign = TextAlign.start,
    this.active,
    this.fadeWidth = 24,
    this.velocity = 32,
    this.pause = const Duration(milliseconds: 900),
    super.key,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  /// Made the first time the text actually has to move. Stopping never makes
  /// one: a card taken out of the tree still hears its notifier, and creating
  /// a ticker there asks a deactivated element for its TickerMode.
  AnimationController? _animation;
  AnimationController get _controller => _animation ??= AnimationController(vsync: this);
  Timer? _pauseTimer;
  double _overflow = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    widget.active?.addListener(_onActiveChanged);
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.active, widget.active)) {
      oldWidget.active?.removeListener(_onActiveChanged);
      widget.active?.addListener(_onActiveChanged);
      _onActiveChanged();
    }
    if (oldWidget.text != widget.text) {
      _stop(reset: true);
    }
  }

  /// Out of the tree, deaf to the notifier until it is back: the notifier
  /// belongs to a card that may well still be alive elsewhere.
  @override
  void deactivate() {
    widget.active?.removeListener(_onActiveChanged);
    _stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    widget.active?.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    widget.active?.removeListener(_onActiveChanged);
    _pauseTimer?.cancel();
    _animation?.dispose();
    super.dispose();
  }

  void _onActiveChanged() {
    if (!mounted) return;
    if (widget.active?.value == true) {
      _start();
    } else {
      _stop();
    }
  }

  /// Sit still, slide to the end, sit still, slide back, and again for as long
  /// as the text is being looked at.
  Future<void> _start() async {
    if (_running || _overflow <= 0 || !mounted) return;
    _running = true;
    // The line below paints from the controller, and has to be handed it the
    // first time there is one.
    if (_animation == null) {
      setState(() {
        _animation = AnimationController(vsync: this);
      });
    }
    while (mounted && _running && (widget.active?.value ?? false)) {
      await _wait(widget.pause);
      if (!_running) return;
      await _controller.animateTo(
        1,
        duration: Duration(milliseconds: (_overflow / widget.velocity * 1000).round().clamp(400, 20000)),
        curve: Curves.linear,
      );
      if (!_running) return;
      await _wait(widget.pause + const Duration(milliseconds: 400));
      if (!_running) return;
      await _controller.animateBack(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    }
    _running = false;
  }

  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    _pauseTimer?.cancel();
    _pauseTimer = Timer(duration, completer.complete);
    return completer.future;
  }

  void _stop({bool reset = false}) {
    _running = false;
    _pauseTimer?.cancel();
    // Nothing to stop if the text never moved - and making a controller just
    // to stop it is what asked a card on its way out for a ticker.
    final animation = _animation;
    if (animation == null) return;
    animation.stop();
    if (!mounted) return;
    if (reset) {
      animation.value = 0;
    } else if (animation.value != 0) {
      animation.animateBack(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }
  }

  /// Told by the line itself, from its layout, how much of the text does not
  /// fit.
  void _onOverflow(double overflow) {
    if ((overflow - _overflow).abs() <= 0.5) return;
    _overflow = overflow;
    if (overflow <= 0) {
      _animation?.value = 0;
    } else if (widget.active?.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    // The text is laid out once, as wide as it wants to be, by the line that
    // then clips, fades and slides it. This used to measure the text with a
    // painter of its own to find out whether it fit, and then build a Text
    // that laid the same string out again: two paragraph layouts for every
    // title and every subtitle of every card, which on a grid being flung was
    // more of the frame than laying the text out for real.
    return _MarqueeLine(
      textAlign: widget.textAlign,
      textDirection: Directionality.of(context),
      fadeWidth: widget.fadeWidth,
      progress: _animation,
      onOverflow: _onOverflow,
      child: Text(
        widget.text,
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
      ),
    );
  }
}

/// One line of [child], laid out at its full width whatever room there is,
/// and shown through a window as wide as the room: clipped, faded out at
/// whichever edge has more text behind it, and slid along by [progress].
class _MarqueeLine extends SingleChildRenderObjectWidget {
  const _MarqueeLine({
    required this.textAlign,
    required this.textDirection,
    required this.fadeWidth,
    required this.progress,
    required this.onOverflow,
    required super.child,
  });

  final TextAlign textAlign;
  final TextDirection textDirection;
  final double fadeWidth;

  /// 0 at the start of the text, 1 at its end. Null while it has never moved.
  final Animation<double>? progress;
  final ValueChanged<double> onOverflow;

  @override
  _RenderMarqueeLine createRenderObject(BuildContext context) => _RenderMarqueeLine(
        textAlign: textAlign,
        textDirection: textDirection,
        fadeWidth: fadeWidth,
        progress: progress,
        onOverflow: onOverflow,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderMarqueeLine renderObject) {
    renderObject
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..fadeWidth = fadeWidth
      ..progress = progress
      ..onOverflow = onOverflow;
  }
}

class _RenderMarqueeLine extends RenderShiftedBox {
  _RenderMarqueeLine({
    required TextAlign textAlign,
    required TextDirection textDirection,
    required double fadeWidth,
    required Animation<double>? progress,
    required this.onOverflow,
  })  : _textAlign = textAlign,
        _textDirection = textDirection,
        _fadeWidth = fadeWidth,
        _progress = progress,
        super(null);

  ValueChanged<double> onOverflow;

  TextAlign _textAlign;
  set textAlign(TextAlign value) {
    if (_textAlign == value) return;
    _textAlign = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  double _fadeWidth;
  set fadeWidth(double value) {
    if (_fadeWidth == value) return;
    _fadeWidth = value;
    markNeedsPaint();
  }

  Animation<double>? _progress;
  set progress(Animation<double>? value) {
    if (identical(_progress, value)) return;
    if (attached) _progress?.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) value?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// How much wider the text is than the room it has.
  double _overflow = 0;

  bool get _rtl => _textDirection == TextDirection.rtl;

  /// How far along the text has been slid, towards its start.
  double get _shift => (_progress?.value ?? 0) * _overflow;

  /// Where the text sits within the window when it has room to spare.
  double get _alignment => switch (_textAlign) {
        TextAlign.left => 0,
        TextAlign.right => 1,
        TextAlign.center => 0.5,
        TextAlign.start || TextAlign.justify => _rtl ? 1 : 0,
        TextAlign.end => _rtl ? 0 : 1,
      };

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _progress?.removeListener(markNeedsPaint);
    super.detach();
  }

  BoxConstraints _childConstraints(BoxConstraints constraints) =>
      BoxConstraints(minHeight: constraints.minHeight, maxHeight: constraints.maxHeight);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    return constraints.constrain(child.getDryLayout(_childConstraints(constraints)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
    final spare = size.width - child.size.width;
    _overflow = spare < 0 ? -spare : 0;
    // With room to spare the text sits where its alignment puts it; without,
    // it starts at its beginning and the rest runs off the far edge.
    final dx = spare >= 0 ? spare * _alignment : (_rtl ? spare : 0.0);
    (child.parentData! as BoxParentData).offset = Offset(dx, 0);
    onOverflow(_overflow);
  }

  Offset get _childOffset {
    final offset = (child!.parentData! as BoxParentData).offset;
    if (_overflow <= 0) return offset;
    return offset.translate(_rtl ? _shift : -_shift, 0);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _childOffset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _childOffset,
      position: position,
      hitTest: (result, transformed) => child.hitTest(result, position: transformed),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_overflow <= 0) {
      context.paintChild(child, offset + _childOffset);
      return;
    }
    final shift = _shift;
    final leading = (shift / _fadeWidth).clamp(0.0, 1.0);
    final trailing = ((_overflow - shift) / _fadeWidth).clamp(0.0, 1.0);
    final fade = (_fadeWidth / size.width).clamp(0.0, 0.5);
    final bounds = offset & size;
    final mask = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: _rtl
            ? [
                Colors.white.withValues(alpha: 1 - trailing),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - leading),
              ]
            : [
                Colors.white.withValues(alpha: 1 - leading),
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: 1 - trailing),
              ],
        stops: [0, fade, 1 - fade, 1],
      ).createShader(bounds);
    final canvas = context.canvas;
    canvas.saveLayer(bounds, Paint());
    canvas.clipRect(bounds);
    context.paintChild(child, offset + _childOffset);
    // The same canvas, as long as the child is plain text - which is all this
    // is ever given.
    context.canvas.drawRect(bounds, mask);
    context.canvas.restore();
  }
}

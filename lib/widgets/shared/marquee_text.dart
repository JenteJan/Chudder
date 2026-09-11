import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  /// The last measurement, so a rebuild that changes nothing about the text
  /// does not lay it out again - a grid rebuilds every card on a scroll.
  (String, TextStyle, double, TextScaler, TextDirection)? _measuredFor;
  double _measuredWidth = 0;
  double _measuredHeight = 0;

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
    if (_running || _overflow <= 0) return;
    _running = true;
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

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final key = (widget.text, style, maxWidth, scaler, direction);
        if (_measuredFor != key) {
          final painter = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          _measuredWidth = painter.width;
          _measuredHeight = painter.height;
          painter.dispose();
          _measuredFor = key;
        }
        final textWidth = _measuredWidth;
        final lineHeight = _measuredHeight;

        final overflow = maxWidth.isFinite ? (textWidth - maxWidth).clamp(0.0, double.infinity) : 0.0;
        if ((overflow - _overflow).abs() > 0.5) {
          _overflow = overflow;
          if (overflow <= 0) {
            _controller.value = 0;
          } else if (widget.active?.value == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _start());
          }
        }

        if (overflow <= 0) {
          return Text(
            widget.text,
            style: style,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            textAlign: widget.textAlign,
          );
        }

        return SizedBox(
          height: lineHeight,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final shift = _controller.value * overflow;
              final leading = (shift / widget.fadeWidth).clamp(0.0, 1.0);
              final trailing = ((overflow - shift) / widget.fadeWidth).clamp(0.0, 1.0);
              final fade = widget.fadeWidth / maxWidth;
              return ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: direction == TextDirection.rtl
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
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: AlignmentDirectional.centerStart,
                    maxWidth: double.infinity,
                    child: Transform.translate(
                      offset: Offset(direction == TextDirection.rtl ? shift : -shift, 0),
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Text(
              widget.text,
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
            ),
          ),
        );
      },
    );
  }
}

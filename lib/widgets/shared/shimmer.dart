import 'package:flutter/material.dart';

/// Sweeps a highlight across everything below it, to say that the shapes there
/// are standing in for something still on its way.
///
/// One animation for a whole group rather than one per box: a row of six
/// placeholders is six tickers otherwise, and the sweep only reads as a sweep
/// if they share a clock.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({required this.child, super.key});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = colors.surfaceContainer;
    // Built from the surface it sits on rather than picked, so it stays a
    // shade rather than a colour in either theme.
    final highlight = Color.alphaBlend(colors.onSurface.withValues(alpha: 0.07), base);

    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
          stops: const [0.25, 0.5, 0.75],
          transform: _SlideGradient(_controller.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double value;
  const _SlideGradient(this.value);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (value * 2 - 1), 0, 0);
}

/// One placeholder shape. Only ever drawn inside a [Shimmer], which is what
/// colours it — on its own it is a flat block.
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry? borderRadius;
  const ShimmerBox({this.width, this.height, this.borderRadius, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: borderRadius ?? BorderRadius.circular(8),
      ),
    );
  }
}

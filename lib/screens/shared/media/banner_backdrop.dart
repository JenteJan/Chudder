import 'package:flutter/material.dart';

/// The pieces a wide banner's picture is set into the page with: the picture
/// faded out on the sides the page comes in from, and a shade behind the words
/// beside it.
///
/// Both ease in and out, rather than running straight from one stop to the
/// next. A straight ramp has a corner where it starts and another where it
/// ends, and the eye finds both: the old ones read as a grey box behind the
/// words and a band down the picture's edge.

/// Smootherstep from [from] to [to]: flat at both ends, so nothing it fades
/// shows where the fade begins or ends.
double _ease(double from, double to, double t) {
  final x = ((t - from) / (to - from)).clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

/// [steps] stops of [value] from 0 to 1, for a gradient that follows a curve
/// rather than a straight line between two colours.
({List<double> stops, List<Color> colors}) _curve(Color color, double Function(double t) value, {int steps = 24}) {
  final stops = [for (var i = 0; i <= steps; i++) i / steps];
  return (stops: stops, colors: [for (final t in stops) color.withValues(alpha: color.a * value(t).clamp(0.0, 1.0))]);
}

/// Fades [child] in from its left side and out just before its foot, both
/// eased, so the picture meets the page without an edge.
///
/// The bottom fade is short on purpose: the middle of the picture's foot,
/// just over the row, is often where its subject is - hands, a face, a title
/// - and a long fade, or a curve from the top corner, put it in the dark. The
/// corner the two fades share lies under the shade behind the words
/// ([BannerTextShade]), whose round shape is the one there is to see.
class BannerPictureFade extends StatelessWidget {
  const BannerPictureFade({required this.child, this.bottomTo = 1, this.foot = 0.16, this.edge = 380, super.key});

  final Widget child;

  /// Where, as a share of the height, the picture is gone - where whatever
  /// stands under the banner begins, or that cuts across it in a line.
  final double bottomTo;

  /// How much of the height, above [bottomTo], the fade at the foot takes.
  final double foot;

  /// How wide, in pixels, the picture's left side eases in over.
  final double edge;

  @override
  Widget build(BuildContext context) {
    final down = _curve(Colors.white, (t) => 1 - _ease(bottomTo - foot, bottomTo, t));
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final share = (edge / bounds.width).clamp(0.05, 0.5);
        final side = _curve(Colors.white, (t) => _ease(0, share, t));
        return LinearGradient(stops: side.stops, colors: side.colors).createShader(bounds);
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: down.stops,
          colors: down.colors,
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// The page's colour coming in under the words from the corner they stand in
/// - the banner's bottom left - and thinning out across the picture.
///
/// One shape for every item, sized by where the words may go rather than by
/// the words there are now: the old shade was a blurred box around the text,
/// and changed shape, and showed its sides, with every item. Centred on the
/// corner, past the window's edge and the banner's foot, it has no edge on
/// those sides at all; on the others it eases away to nothing.
class BannerTextShade extends StatelessWidget {
  const BannerTextShade({
    required this.width,
    required this.height,
    this.strength = 0.92,
    super.key,
  });

  /// How far the words may reach across and up, from the corner.
  final double width;
  final double height;

  /// How much of the page's colour there is right behind the words.
  final double strength;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _TextShadePainter(
            color: surface.withValues(alpha: strength),
            reach: Size(width, height),
          ),
        ),
      ),
    );
  }
}

class _TextShadePainter extends CustomPainter {
  const _TextShadePainter({required this.color, required this.reach});

  final Color color;
  final Size reach;

  /// How far past the words the shade runs out, as a share of their reach;
  /// and how much of it, from the corner, is at full strength.
  static const _overreach = 1.3;
  static const _full = 0.34;

  @override
  void paint(Canvas canvas, Size size) {
    final rx = reach.width * _overreach;
    final ry = reach.height * _overreach;
    if (rx <= 0 || ry <= 0) return;
    final curve = _curve(color, (t) => 1 - _ease(_full, 1, t), steps: 32);
    final circle = Rect.fromCircle(center: Offset.zero, radius: ry);
    canvas
      ..save()
      ..translate(0, size.height)
      // A circle stretched across: an ellipse as wide as the words reach.
      ..scale(rx / ry, 1)
      ..drawRect(
        circle,
        Paint()
          ..shader = RadialGradient(
            radius: 0.5,
            stops: curve.stops,
            colors: curve.colors,
          ).createShader(circle),
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_TextShadePainter old) => old.color != color || old.reach != reach;
}

/// The fade's value at [t], for tests.
@visibleForTesting
double bannerEase(double from, double to, double t) => _ease(from, to, t);

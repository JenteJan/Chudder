import 'package:flutter/material.dart';

/// How a wide banner's picture is set into the page: faded out on the sides
/// the page comes in from. What sets the words beside it off is in
/// banner_text_backing.dart.
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
/// corner the two fades share lies under the words, where the picture gives
/// way to the shape they make ([BannerPictureMask]).
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

/// The fade's value at [t], for tests.
@visibleForTesting
double bannerEase(double from, double to, double t) => _ease(from, to, t);

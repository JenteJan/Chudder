import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/util/fladder_image.dart';

/// A picture blurred past recognition, for the colours it lends whatever
/// stands around the sharp copy of it.
///
/// Artwork used to fade into the page's own flat colour, so everything the
/// fade crossed - the logo, the facts, the summary - sat on a grey smear that
/// belonged to no picture at all. Faded into this instead, the picture seems
/// to carry on under the words, and the fade reads as depth rather than as the
/// picture running out.
///
/// The server's blurhash where there is one: it is there before the picture
/// is, costs sixteen pixels to decode, and is already the look of the blurred
/// band on the wider detail pages. Without one, the picture itself decoded
/// tiny and blurred the rest of the way.
class AmbientArtwork extends StatelessWidget {
  const AmbientArtwork({required this.image, super.key});

  final ImageData? image;

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return const SizedBox.shrink();
    if (image.hash.isNotEmpty) return FladderImage(image: image, blurOnly: true);
    // Clamped so the edges keep their colour rather than blurring in from
    // nothing, and clipped because a blur spreads past its box: unclipped it
    // hung below the fade as a band of its own.
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24, tileMode: TileMode.clamp),
        child: FladderImage(image: image, decodeHeight: 48, disableBlur: true),
      ),
    );
  }
}

/// An [AmbientArtwork] made something to write on, and let out into the page.
///
/// The page's colour comes in over the blur from the sharp picture's lower
/// edge, enough to read the words by, and the whole thing then eases away to
/// nothing. Eased, because a straight ramp ended in a line you could see
/// however soft the blur above it. And faded out rather than painted over in
/// the page's colour: the blur and a cover over it never end on quite the same
/// pixel, and the blur's last row showed as a hairline under the cover.
class AmbientVeil extends StatelessWidget {
  const AmbientVeil({required this.pictureEnd, required this.child, super.key});

  /// Where the sharp picture stops, as a share of this box's height.
  final double pictureEnd;

  /// The blur, usually an [AmbientArtwork].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    // Dark text wants more of the page's colour behind it than light does.
    final veil = theme.brightness == Brightness.light ? 0.62 : 0.42;
    final start = pictureEnd.clamp(0.0, 1.0);
    const steps = 6;
    final stops = <double>[0.0, start];
    final opacities = <double>[1.0, 1.0];
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      stops.add(start + (1 - start) * t);
      opacities.add(1 - Curves.easeInOut.transform(t));
    }
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: stops,
        colors: [for (final opacity in opacities) Colors.white.withValues(alpha: opacity)],
      ).createShader(bounds),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Lighter behind the sharp picture, which covers it anyway but for
          // the fade at its foot.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [start * 0.7, start],
                colors: [surface.withValues(alpha: veil * 0.5), surface.withValues(alpha: veil)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fladder/util/theme_extensions.dart';

class ChudderIcon extends StatelessWidget {
  final double size;
  const ChudderIcon({this.size = 100, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
          "icons/chudder_icon.svg",
          width: size,
        ),
      ],
    );
  }
}

/// The play glyph: the logo's wedge as one flat shape, in place of a triangle.
///
/// Drops in where an [Icon] would go and reads size and colour from the
/// surrounding [IconTheme] the same way, so an [IconButton]'s `iconSize` and
/// foreground still apply. The glyph is drawn on the Iconsax 24px grid, so it
/// sits at the same weight as the pause beside it.
class ChudderPlayIcon extends StatelessWidget {
  final double? size;
  final Color? color;
  const ChudderPlayIcon({this.size, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final boxSize = size ?? iconTheme.size ?? 24;
    var tint = color ?? iconTheme.color ?? context.colors.onSurface;
    if (iconTheme.opacity != null && iconTheme.opacity != 1.0) {
      tint = tint.withValues(alpha: tint.a * iconTheme.opacity!);
    }
    return SvgPicture.asset(
      "icons/chudder_play.svg",
      width: boxSize,
      height: boxSize,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}

class ChudderIconOutlined extends StatelessWidget {
  final double size;
  final Color? color;
  const ChudderIconOutlined({this.size = 100, this.color, super.key});

  @override
  Widget build(BuildContext context) {
    // The single-colour silhouette, not the artwork: this one is tinted to sit
    // among the other list icons, and a flat tint of the artwork is a blob.
    return Image.asset(
      "icons/chudder_notification_icon.png",
      width: size,
      color: color ?? context.colors.onSurfaceVariant,
    );
  }
}

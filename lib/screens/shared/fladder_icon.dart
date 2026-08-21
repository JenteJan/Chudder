import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fladder/util/theme_extensions.dart';

class FladderIcon extends StatelessWidget {
  final double size;
  const FladderIcon({this.size = 100, super.key});

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

class FladderIconOutlined extends StatelessWidget {
  final double size;
  final Color? color;
  const FladderIconOutlined({this.size = 100, this.color, super.key});

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

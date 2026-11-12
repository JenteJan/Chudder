import 'package:flutter/material.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/util/video_properties.dart';
import 'package:chudder/wrappers/players/windows_hdr.dart';

/// The film's format and resolution ("HDR10 4K") as the player's info card
/// shows them. While the picture is really shown in HDR - the window is on
/// an HDR swap chain (see [WindowsHdr]) - the format is drawn in a rainbow:
/// not just an HDR file, but HDR on screen. An HDR file shown in SDR (stock
/// engine, a display without HDR) keeps the plain text.
///
/// Information only: it takes no focus, so remote navigation passes it by.
class MediaInfoTag extends StatelessWidget {
  const MediaInfoTag({required this.streams, super.key});

  final MediaStreamsModel streams;

  static const rainbow = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF32ADE6),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
  ];

  @override
  Widget build(BuildContext context) {
    final profile = streams.displayProfile;
    final resolution = streams.resolution;
    return ValueListenableBuilder<bool>(
      valueListenable: WindowsHdr.active,
      builder: (context, active, _) {
        if (!active || profile == null || profile == DisplayProfile.sdr) {
          return Text(streams.mediaInfoTag ?? '');
        }
        final style = DefaultTextStyle.of(context).style.copyWith(fontWeight: FontWeight.w700);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              key: const Key('hdr-rainbow'),
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const LinearGradient(colors: rainbow).createShader(bounds),
              child: Text(profile.value, style: style),
            ),
            Text(' ${resolution?.value}'),
          ],
        );
      },
    );
  }
}

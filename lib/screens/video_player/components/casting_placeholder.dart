import 'package:flutter/material.dart';

/// Shown in place of the video while casting/playing remotely: the item's
/// backdrop with a cast badge. Scales down to the mini player-bar preview
/// (icon only). Shared by every remote player (Chromecast, DLNA, web) so the
/// casting UI is identical regardless of protocol.
class CastingPlaceholder extends StatelessWidget {
  const CastingPlaceholder({
    super.key,
    required this.deviceName,
    this.image,
  });

  final String deviceName;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 140;
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Colors.black),
            if (image != null)
              Image(
                image: image!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            // Scrim so the badge stays readable on bright backdrops.
            ColoredBox(color: Colors.black.withValues(alpha: compact ? 0.35 : 0.55)),
            Center(
              child: compact
                  ? const Icon(Icons.cast_connected, size: 22, color: Colors.white)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cast_connected, size: 36, color: Colors.white70),
                        const SizedBox(height: 12),
                        Text(
                          'Casting to $deviceName',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

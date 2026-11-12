import 'package:flutter/material.dart';

import 'package:chudder/wrappers/players/windows_hdr.dart';

/// "HDR" in the player's top bar while the picture is shown in HDR: the
/// window has switched to an HDR swap chain and the video's highlights use
/// the display's range above SDR white (see [WindowsHdr]). Nothing at all
/// otherwise - an SDR file, a stock engine, or a display without HDR.
///
/// Information only: it takes no focus, so remote navigation passes it by.
class HdrBadge extends StatelessWidget {
  const HdrBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WindowsHdr.active,
      builder: (context, active, _) {
        if (!active) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
          child: Text(
            'HDR',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';

/// An icon in the same quiet outline the stream pickers wear - see the
/// `subtle` [EnumBox] - so a row of play, pickers and this reads as one row
/// with one loud thing in it.
class SubtleIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autoFocus;

  const SubtleIconButton({
    required this.icon,
    this.tooltip,
    this.onTap,
    this.onLongPress,
    this.autoFocus = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    final button = FocusButton(
      onTap: onTap,
      onLongPress: onLongPress,
      autoFocus: autoFocus,
      borderRadius: radius,
      darkOverlay: false,
      onFocusChanged: (value) {
        if (value) context.ensureVisible(alignment: 1.0);
      },
      child: Container(
        height: 40,
        width: 44,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: colors.onSurface.withValues(alpha: 0.18)),
        ),
        child: Icon(icon, size: 20, color: colors.onSurface.withValues(alpha: 0.8)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

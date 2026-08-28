import 'package:flutter/material.dart';

import 'package:fladder/screens/shared/flat_button.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';

class ChipButton extends StatefulWidget {
  final String label;
  final Function()? onPressed;
  const ChipButton({required this.label, this.onPressed, super.key});

  @override
  State<ChipButton> createState() => _ChipButtonState();
}

class _ChipButtonState extends State<ChipButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Inverted while selected: a chip is small and low-contrast, and an
    // outline alone was hard to pick out from across a room. Selected, it
    // swaps its two colours - dark on light becomes light on dark.
    final background = _focused ? colors.onSurface : colors.onSurface.withValues(alpha: 0.15);
    final foreground = _focused ? colors.surface : colors.onSurface;
    return Card(
      color: background,
      shadowColor: Colors.transparent,
      child: FlatButton(
        onTap: widget.onPressed,
        onFocusChange: (focused) {
          if (focused != _focused) setState(() => _focused = focused);
          // To the page's focus line like every other button; without this a
          // chip stayed wherever the last move had left the page.
          if (focused) context.ensureVisible();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: foreground),
          ),
        ),
      ),
    );
  }
}

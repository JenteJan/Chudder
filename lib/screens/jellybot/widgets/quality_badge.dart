import 'package:flutter/material.dart';

class QualityBadge extends StatelessWidget {
  final String quality;
  const QualityBadge({super.key, required this.quality});

  Color _bg(BuildContext context) {
    final q = quality.toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    if (q.contains('uhd') || q.contains('2160') || q.contains('4k')) {
      return Colors.amber.shade700;
    }
    if (q.contains('1080') || q.contains('fullhd') || q.contains('full hd')) {
      return scheme.primary;
    }
    if (q.contains('720') || q.contains('hd')) {
      return Colors.green.shade600;
    }
    if (q.contains('sd') || q.contains('480')) {
      return scheme.outline;
    }
    return scheme.surfaceContainerHighest;
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bg(context);
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        quality.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}

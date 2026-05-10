import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

class LanguageBadge extends StatelessWidget {
  final String language;
  const LanguageBadge({super.key, required this.language});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(IconsaxPlusLinear.global, size: 12, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            language.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
          ),
        ],
      ),
    );
  }
}

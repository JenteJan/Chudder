import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class NestedBottomAppBar extends ConsumerWidget {
  final Widget child;
  const NestedBottomAppBar({required this.child, super.key});

  /// What the bar adds above and below its [child]: the margin around it and
  /// the padding inside it. The safe-area inset comes on top of this.
  static const double verticalChrome = 8 + 6 + 6 + 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(8.0).copyWith(bottom: MediaQuery.paddingOf(context).bottom + 8),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.965),
          borderRadius: BorderRadiusDirectional.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: child,
        ),
      ),
    );
  }
}

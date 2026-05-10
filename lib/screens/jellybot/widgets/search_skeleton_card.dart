import 'package:flutter/material.dart';

class SearchSkeletonCard extends StatefulWidget {
  const SearchSkeletonCard({super.key});

  @override
  State<SearchSkeletonCard> createState() => _SearchSkeletonCardState();
}

class _SearchSkeletonCardState extends State<SearchSkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final highlight = Theme.of(context).colorScheme.surfaceContainerHigh;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color = Color.lerp(base, highlight, _controller.value)!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 80,
                  height: 120,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 18, color: color),
                      const SizedBox(height: 8),
                      Container(height: 14, width: 200, color: color),
                      const SizedBox(height: 12),
                      Container(height: 12, color: color),
                      const SizedBox(height: 4),
                      Container(height: 12, width: 240, color: color),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

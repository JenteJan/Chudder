import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/util/localization_helper.dart';

class SearchEmptyState extends StatelessWidget {
  final void Function(MediaCategory) onCategoryTap;
  const SearchEmptyState({super.key, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.search_normal,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.localized.jellybotSearchPrompt,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.localized.jellybotSearchHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(IconsaxPlusLinear.video_play, size: 16),
                  label: Text(context.localized.jellybotMovie),
                  onPressed: () => onCategoryTap(MediaCategory.movie),
                ),
                ActionChip(
                  avatar: const Icon(IconsaxPlusLinear.monitor, size: 16),
                  label: Text(context.localized.jellybotShow),
                  onPressed: () => onCategoryTap(MediaCategory.show),
                ),
                ActionChip(
                  avatar: const Icon(IconsaxPlusLinear.star, size: 16),
                  label: Text(context.localized.jellybotAnime),
                  onPressed: () => onCategoryTap(MediaCategory.anime),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

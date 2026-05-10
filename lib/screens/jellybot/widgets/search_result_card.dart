import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_search_provider.dart';
import 'package:fladder/screens/jellybot/widgets/already_added_badge.dart';
import 'package:fladder/screens/jellybot/widgets/language_badge.dart';
import 'package:fladder/screens/jellybot/widgets/quality_badge.dart';
import 'package:fladder/util/localization_helper.dart';

class SearchResultCard extends ConsumerWidget {
  final ProviderSearchItemDto item;
  final IProvider? provider;
  final bool isAdding;
  final VoidCallback? onAdd;

  const SearchResultCard({
    super.key,
    required this.item,
    required this.provider,
    required this.isAdding,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addedUrls = ref.watch(addedCrawlLinkUrlsProvider).valueOrNull ??
        const <String>{};
    final isAlreadyAdded = item.url != null && addedUrls.contains(item.url);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: (isAdding || isAlreadyAdded) ? null : onAdd,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(item: item, isAlreadyAdded: isAlreadyAdded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title ?? context.localized.unknown,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.season != null)
                          _MetaChip(
                            icon: IconsaxPlusLinear.video_play,
                            label:
                                '${context.localized.season(1)} ${item.season}',
                          ),
                        if ((item.quality ?? '').isNotEmpty)
                          QualityBadge(quality: item.quality!),
                        if ((item.language ?? '').isNotEmpty)
                          LanguageBadge(language: item.language!),
                        if (provider != null &&
                            (provider!.displayName ?? provider!.name) != null)
                          _MetaChip(
                            icon: IconsaxPlusLinear.global,
                            label: provider!.displayName ?? provider!.name!,
                          ),
                      ],
                    ),
                    if ((item.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isAdding)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (isAlreadyAdded)
                Tooltip(
                  message: context.localized.jellybotAlreadyAdded,
                  child: Icon(
                    IconsaxPlusBold.tick_circle,
                    color: scheme.tertiary,
                    size: 28,
                  ),
                )
              else
                IconButton.filled(
                  onPressed: onAdd,
                  icon: const Icon(IconsaxPlusLinear.add),
                  tooltip: context.localized.add,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final ProviderSearchItemDto item;
  final bool isAlreadyAdded;
  const _Thumbnail({required this.item, required this.isAlreadyAdded});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 80,
      height: 120,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(IconsaxPlusLinear.video_play, size: 32),
    );
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: (item.thumbnailUrl ?? '').isNotEmpty
              ? Image.network(
                  item.thumbnailUrl!,
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder,
                )
              : placeholder,
        ),
        if (isAlreadyAdded)
          const Positioned(
            top: 4,
            left: 4,
            child: AlreadyAddedBadge(),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/util/localization_helper.dart';

/// Returns:
/// - `true` if user confirms it's different media (proceed with adding)
/// - `false` if user confirms it's the same media (navigate to existing)
/// - `null` if dialog is dismissed/cancelled (stay on page)
class ExistingMediaDialog extends StatelessWidget {
  final MediaSearchResultDto existingMedia;
  final String addedLinkTitle;

  const ExistingMediaDialog({
    super.key,
    required this.existingMedia,
    required this.addedLinkTitle,
  });

  Future<void> _openJellyfinUrl() async {
    final url = existingMedia.mediaUrl;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOriginalTitle = existingMedia.originalTitle != null &&
        existingMedia.originalTitle != existingMedia.title;

    return AlertDialog(
      title: Text(context.localized.jellybotMediaExistsTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.localized.jellybotMediaExistsMessage,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.localized.jellybotExistingTitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        existingMedia.title ?? 'Unknown',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (hasOriginalTitle) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.localized.jellybotOriginalTitle,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          existingMedia.originalTitle!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      if (existingMedia.productionYear != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          context.localized.jellybotProductionYear,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          existingMedia.productionYear.toString(),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      if (existingMedia.mediaUrl != null &&
                          existingMedia.mediaUrl!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _openJellyfinUrl,
                          icon: const Icon(IconsaxPlusLinear.export_3, size: 18),
                          label: Text(context.localized.jellybotViewOnJellyfin),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.localized.jellybotAddedLinkTitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              addedLinkTitle,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(context.localized.cancel),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, false),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
          child: Text(context.localized.jellybotYesSameMedia),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.localized.jellybotNoDifferentMedia),
        ),
      ],
    );
  }
}

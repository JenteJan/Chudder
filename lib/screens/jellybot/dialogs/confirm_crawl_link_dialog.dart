import 'package:flutter/material.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/screens/jellybot/widgets/quality_badge.dart';
import 'package:fladder/util/localization_helper.dart';

class ConfirmDialogResult {
  final bool confirmed;
  final String? editedName;
  const ConfirmDialogResult({required this.confirmed, this.editedName});
}

class ConfirmCrawlLinkDialog extends StatefulWidget {
  final CrawlLinkDto crawlLink;
  const ConfirmCrawlLinkDialog({super.key, required this.crawlLink});

  @override
  State<ConfirmCrawlLinkDialog> createState() => _ConfirmCrawlLinkDialogState();
}

class _ConfirmCrawlLinkDialogState extends State<ConfirmCrawlLinkDialog> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.crawlLink.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _confirm() {
    final originalName = widget.crawlLink.name ?? '';
    final editedName = _nameController.text.trim();
    Navigator.pop(
      context,
      ConfirmDialogResult(
        confirmed: true,
        editedName: editedName != originalName ? editedName : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.crawlLink;
    final scheme = Theme.of(context).colorScheme;
    final aired = link.airedEpisodesCount ?? 0;
    final total = link.totalEpisodesCount ?? 0;
    return AlertDialog(
      title: Text(context.localized.jellybotConfirmAdd),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((link.thumbnailUrl ?? '').isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      link.thumbnailUrl!,
                      width: 64,
                      height: 96,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 64, height: 96),
                    ),
                  ),
                if ((link.thumbnailUrl ?? '').isNotEmpty)
                  const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (link.season != null)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${context.localized.season(1)} ${link.season}',
                              ),
                            ),
                          if ((link.quality ?? '').isNotEmpty)
                            QualityBadge(quality: link.quality!),
                          if (link.productionYear != null)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${link.productionYear}'),
                            ),
                        ],
                      ),
                      if (aired > 0 || total > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '$aired / $total ${context.localized.jellybotEpisodes(total)}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                labelText: context.localized.name,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(context.localized.cancel),
        ),
        FilledButton(
          onPressed: _confirm,
          child: Text(context.localized.confirm),
        ),
      ],
    );
  }
}

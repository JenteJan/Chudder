import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/util/localization_helper.dart';

class SeasonPickerDialog extends StatelessWidget {
  final String mediaTitle;
  final int availableSeasons;
  final String? thumbnailUrl;

  const SeasonPickerDialog({
    super.key,
    required this.mediaTitle,
    required this.availableSeasons,
    this.thumbnailUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.localized.jellybotSelectSeason),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(mediaTitle: mediaTitle, thumbnailUrl: thumbnailUrl),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableSeasons,
                itemBuilder: (context, index) {
                  final season = index + 1;
                  return ListTile(
                    leading: const Icon(IconsaxPlusLinear.video_play),
                    title: Text('${context.localized.season(1)} $season'),
                    onTap: () => Navigator.pop(context, season),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.localized.cancel),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String mediaTitle;
  final String? thumbnailUrl;
  const _Header({required this.mediaTitle, this.thumbnailUrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if ((thumbnailUrl ?? '').isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                thumbnailUrl!,
                width: 50,
                height: 70,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const SizedBox(width: 50, height: 70),
              ),
            ),
          if ((thumbnailUrl ?? '').isNotEmpty) const SizedBox(width: 8),
          Expanded(
            child: Text(
              mediaTitle,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

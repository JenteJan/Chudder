import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/studio_details_provider.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/poster_row.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';

/// What a studio has in the library.
///
/// Jellyfin has no catalogue of everything a studio ever made — only what it
/// has indexed — so this is a shelf rather than a filmography, and it says so
/// when the shelf is empty rather than leaving a blank page.
class StudioDetailScreen extends ConsumerStatefulWidget {
  final ItemBaseModel item;
  const StudioDetailScreen({required this.item, super.key});

  @override
  ConsumerState<StudioDetailScreen> createState() => _StudioDetailScreenState();
}

class _StudioDetailScreenState extends ConsumerState<StudioDetailScreen> {
  late final providerId = studioDetailsProvider(widget.item.id);

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerId);
    final studio = details.studio ?? widget.item;
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;

    return DetailScaffold(
      label: studio.name,
      item: details.studio,
      onRefresh: () async => await ref.read(providerId.notifier).fetch(widget.item),
      // A studio rarely has artwork of its own, so the page borrows the look of
      // what it made.
      backDrops: studio.images?.backDrop?.isNotEmpty == true
          ? studio.images
          : [...details.movies, ...details.series].random().firstOrNull?.images,
      content: (context, padding) => Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: detailArtworkHeight(context) * (isPhone ? 0.92 : 0.55)),
          Padding(
            padding: padding,
            child: _Header(studio: studio),
          ),
          const SizedBox(height: 32),
          if (details.movies.isNotEmpty)
            PosterRow(
              contentPadding: padding,
              posters: details.movies,
              label: context.localized.mediaTypeMovie(details.movies.length),
            ),
          if (details.series.isNotEmpty)
            PosterRow(
              contentPadding: padding,
              posters: details.series,
              label: context.localized.mediaTypeSeries(details.series.length),
            ),
          if (!details.loading && details.isEmpty)
            Padding(
              padding: padding.copyWith(top: 32, bottom: 32),
              child: Text(
                context.localized.noItemsToShow,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

/// The studio's logo where it has one, and its name either way — a logo alone
/// is not always readable, and half of them are missing.
class _Header extends StatelessWidget {
  const _Header({required this.studio});

  final ItemBaseModel studio;

  @override
  Widget build(BuildContext context) {
    final logo = studio.images?.logo ?? studio.images?.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        if (logo != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120, maxWidth: 320),
            child: FladderImage(image: logo, fit: BoxFit.contain),
          ),
        Text(
          studio.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        Text(
          context.localized.studio(1),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
        ),
      ],
    );
  }
}

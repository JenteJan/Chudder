import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/studio_details_provider.dart';
import 'package:fladder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/poster_grid.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';

/// A studio, and what of theirs you can watch.
///
/// The library part is a grid rather than a row: a studio usually has a handful
/// of films on a server, and a row of four in a screen's width reads as empty.
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
            child: _Header(studio: studio, logoUrl: details.logoUrl),
          ),
          const SizedBox(height: 32),
          if (details.movies.isNotEmpty)
            Padding(
              padding: padding,
              child: PosterGrid(
                name: context.localized.mediaTypeMovie(details.movies.length),
                posters: details.movies,
              ),
            ),
          if (details.series.isNotEmpty)
            Padding(
              padding: padding,
              child: PosterGrid(
                name: context.localized.mediaTypeSeries(details.series.length),
                posters: details.series,
              ),
            ),
          // Last, as everywhere else: these are things to request, not things
          // you can press play on.
          if (details.discoverMovies.isNotEmpty)
            SeerrPosterRow(
              posters: details.discoverMovies,
              label: "${context.localized.discover} ${context.localized.mediaTypeMovie(2).toLowerCase()}",
              contentPadding: padding,
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

/// The studio's logo where anyone has one, and its name either way.
///
/// TMDB's logo comes first: a studio's Jellyfin image tag often promises a
/// picture the server cannot actually serve, which is where the broken image
/// came from. Whichever is used, a logo that fails to load leaves nothing
/// behind rather than a placeholder — the name is right underneath it.
class _Header extends StatelessWidget {
  const _Header({required this.studio, this.logoUrl});

  final ItemBaseModel studio;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final jellyfinLogo = studio.images?.logo ?? studio.images?.primary;
    const hidden = SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        if (logoUrl != null || jellyfinLogo != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: logoUrl != null ? 140 : 100, maxWidth: 340),
            child: logoUrl != null
                // A company mark from a metadata provider is a transparent PNG,
                // and half of them are black on nothing — invisible on this
                // page. Painting the shape rather than the picture makes every
                // one of them legible at the same weight.
                ? ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                    child: CachedNetworkImage(
                      imageUrl: logoUrl!,
                      fit: BoxFit.contain,
                      errorWidget: (context, url, error) => hidden,
                    ),
                  )
                : FladderImage(
                    image: jellyfinLogo,
                    fit: BoxFit.contain,
                    disableBlur: true,
                    placeHolder: hidden,
                    imageErrorBuilder: (context, error, stack) => hidden,
                  ),
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

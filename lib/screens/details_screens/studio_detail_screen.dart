import 'dart:math';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/items/studio_details_provider.dart';
import 'package:chudder/screens/details_screens/components/overview_header.dart';
import 'package:chudder/screens/seerr/widgets/seerr_poster_row.dart';
import 'package:chudder/screens/shared/detail_scaffold.dart';
import 'package:chudder/screens/shared/media/poster_grid.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/localization_helper.dart';

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

  /// Which film lends its backdrop, chosen once per page. Picked again on
  /// every build, the backdrop changed - and faded in again - each time
  /// another part of the page arrived.
  final int _backdropPick = Random().nextInt(1 << 20);

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(providerId);
    final studio = details.studio ?? widget.item;
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    final works = [...details.movies, ...details.series];

    return DetailScaffold(
      label: studio.name,
      item: details.studio,
      onRefresh: () async => await ref.read(providerId.notifier).fetch(widget.item),
      // A studio rarely has artwork of its own, so the page borrows the look of
      // what it made.
      backDrops: studio.images?.backDrop?.isNotEmpty == true
          ? studio.images
          : works.isEmpty
              ? null
              : works[_backdropPick % works.length].images,
      content: (context, padding) => Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Into the backdrop's fade, not below it - and not so far down that
          // the films are a screen away.
          SizedBox(height: detailArtworkHeight(context) * (isPhone ? 0.6 : 0.42)),
          Padding(
            padding: padding,
            child: _Header(
              studio: studio,
              logoUrl: details.logoUrl,
              isPhone: isPhone,
              movieCount: details.movies.length,
              seriesCount: details.series.length,
            ),
          ),
          const SizedBox(height: 24),
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
  const _Header({
    required this.studio,
    this.logoUrl,
    required this.isPhone,
    required this.movieCount,
    required this.seriesCount,
  });

  final ItemBaseModel studio;
  final String? logoUrl;
  final bool isPhone;
  final int movieCount;
  final int seriesCount;

  @override
  Widget build(BuildContext context) {
    final jellyfinLogo = studio.images?.logo ?? studio.images?.primary;
    const hidden = SizedBox.shrink();
    final hasLogo = logoUrl != null || jellyfinLogo != null;

    final logo = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: isPhone ? 90 : 120, maxWidth: isPhone ? 260 : 300),
      child: logoUrl != null
          // Not tinted to a silhouette: plenty of these marks carry a
          // background of their own, and painting every opaque pixel one
          // colour turns those into a solid block.
          ? CachedNetworkImage(
              imageUrl: logoUrl!,
              fit: BoxFit.contain,
              errorWidget: (context, url, error) => hidden,
            )
          : FladderImage(
              image: jellyfinLogo,
              fit: BoxFit.contain,
              disableBlur: true,
              placeHolder: hidden,
              imageErrorBuilder: (context, error, stack) => hidden,
            ),
    );

    final facts = [
      context.localized.studio(1),
      if (movieCount > 0) "$movieCount ${context.localized.mediaTypeMovie(movieCount).toLowerCase()}",
      if (seriesCount > 0) "$seriesCount ${context.localized.mediaTypeSeries(seriesCount).toLowerCase()}",
    ];

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: isPhone ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      spacing: 8,
      children: [
        SelectableText(
          studio.name,
          textAlign: isPhone ? TextAlign.center : TextAlign.start,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        MetadataLabels(
          extraLabels: facts,
          alignment: isPhone ? WrapAlignment.center : WrapAlignment.start,
        ),
      ],
    );

    if (isPhone || !hasLogo) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          if (hasLogo) logo,
          text,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 28,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: logo,
        ),
        Expanded(child: text),
      ],
    );
  }
}

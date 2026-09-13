import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/external_ratings_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/providers/external_ratings_provider.dart';
import 'package:chudder/screens/shared/media/external_links_row.dart';
import 'package:chudder/util/external_links.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/localization_helper.dart';

/// The rating sites' scores for a film or show, as one quiet line of text:
/// "IMDb 7.8 · TMDB 74% · 85% · 91%", with the site's name small in front of
/// each number and the Rotten Tomatoes pair told apart by their marks. No
/// boxes, no colours to compete with the play button; a link button at the
/// end opens the site pages when there are any.
///
/// Draws what it has the moment it has it: the server's own rating on the
/// first frame, and the rest as they arrive.
class RatingsRow extends ConsumerWidget {
  final ItemBaseModel item;
  final double? communityRating;
  final double? criticRating;
  final WrapAlignment alignment;

  /// Where the item can be opened on the web, offered behind one button at
  /// the end of the line rather than as a row of chips.
  final List<ExternalLink> links;

  const RatingsRow({
    required this.item,
    this.communityRating,
    this.criticRating,
    this.alignment = WrapAlignment.start,
    this.links = const [],
    super.key,
  });

  /// The lookup for this item, or null for a kind of item no site rates.
  static ExternalRatingsRequest? requestFor(ItemBaseModel item) {
    final isSeries = item is SeriesModel;
    if (!isSeries && item is! MovieModel) return null;
    final tmdbId = item.tmdbId;
    final imdbId = item.imdbId;
    if (tmdbId == null && imdbId == null && item.name.isEmpty) return null;
    return (tmdbId: tmdbId, imdbId: imdbId, isSeries: isSeries, title: item.name, year: item.overview.yearAired);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = requestFor(item);
    final external = request == null ? null : ref.watch(externalRatingsProvider(request)).valueOrNull;
    final ratings = external ?? ExternalRatings.empty;
    final colors = Theme.of(context).colorScheme;
    final muted = colors.onSurface.withValues(alpha: 0.55);

    final scores = <Widget>[
      if (ratings.imdb != null)
        _Score(
          label: 'IMDb',
          value: ratings.imdb!.toStringAsFixed(1),
          tooltip:
              ratings.imdbVotes != null ? '${ExternalSite.imdb.label} · ${_votes(context, ratings.imdbVotes!)}' : null,
        ),
      if (ratings.tmdb != null)
        _Score(
          label: 'TMDB',
          value: '${(ratings.tmdb! * 10).round()}%',
          tooltip:
              ratings.tmdbVotes != null ? '${ExternalSite.tmdb.label} · ${_votes(context, ratings.tmdbVotes!)}' : null,
        ),
      if (ratings.rtCritics != null)
        _Score(
          icon: _SvgIcon('icons/tomato.svg', color: _tomatoColor(ratings.rtCritics!)),
          value: '${ratings.rtCritics}%',
          tooltip: '${ExternalSite.rottenTomatoes.label} · ${context.localized.critics}',
        ),
      if (ratings.rtAudience != null)
        _Score(
          icon: _SvgIcon('icons/popcorn_bucket.svg', color: muted),
          value: '${ratings.rtAudience}%',
          tooltip: '${ExternalSite.rottenTomatoes.label} · ${context.localized.audience}',
        ),
      if (ratings.metacritic != null)
        _Score(
          label: 'MC',
          value: ratings.metacritic.toString(),
          tooltip: ExternalSite.metacritic.label,
        ),
      // The server's own numbers stand in until something better has arrived,
      // and stay for anything no site was asked about.
      if (ratings.imdb == null && ratings.tmdb == null && communityRating != null && communityRating != 0)
        _Score(
          icon: Icon(IconsaxPlusBold.star_1, size: 14, color: const Color(0xFFF5C518).withValues(alpha: 0.85)),
          value: communityRating!.toStringAsFixed(1),
          tooltip: context.localized.communityRating,
        ),
      if (ratings.rtCritics == null && criticRating != null && criticRating != 0)
        _Score(
          icon: _SvgIcon('icons/tomato.svg', color: _tomatoColor(criticRating!.round())),
          value: '${criticRating!.round()}%',
          tooltip: '${ExternalSite.rottenTomatoes.label} · ${context.localized.critics}',
        ),
    ];

    if (scores.isEmpty && links.isEmpty) return const SizedBox.shrink();

    final separator = Text('·', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.35)));
    final children = <Widget>[];
    for (var i = 0; i < scores.length; i++) {
      if (i > 0) children.add(separator);
      children.add(scores[i]);
    }
    if (links.isNotEmpty) children.add(LinksMenuButton(links: links));

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      alignment: alignment,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  String _votes(BuildContext context, int votes) {
    final formatted = votes >= 1000 ? '${(votes / 1000).toStringAsFixed(votes >= 10000 ? 0 : 1)}k' : votes.toString();
    return context.localized.votes(formatted);
  }

  /// Fresh is red, rotten is green-grey: the mark itself says which, so the
  /// number beside it can stay the colour of the rest of the line.
  Color _tomatoColor(int score) => score >= 60 ? const Color(0xFFFA320A) : const Color(0xFF6A8A3A);
}

/// One number on the line, with the site's name small in front of it or a
/// mark that stands for the site.
class _Score extends StatelessWidget {
  final String? label;
  final Widget? icon;
  final String value;
  final String? tooltip;

  const _Score({this.label, this.icon, required this.value, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        if (icon != null) icon!,
        if (label != null)
          Text(
            label!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

class _SvgIcon extends StatelessWidget {
  final String asset;
  final Color color;
  const _SvgIcon(this.asset, {required this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: 14,
      height: 14,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

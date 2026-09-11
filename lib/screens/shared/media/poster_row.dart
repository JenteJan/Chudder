import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart' as jelly;
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/screens/shared/media/tv_poster_row.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';

/// The shape of one card in a row, worked out once for every row on a page.
///
/// Every row of portraits - films, shows, seasons, the cast, the things Seerr
/// suggests - is measured the same way: a card as wide as the poster setting
/// makes a portrait, the picture whole above the text at [artRatio], and
/// [maxLines] of text under it. Rows used to each pick a ratio of their own and
/// squeeze the whole card, picture and text, into it; the text took a fixed
/// height out of that, and what was left for the picture was a box wider than
/// the picture, so cover-fit cut the top and bottom off every one.
class PosterCardMetrics {
  /// The width of every card in the row.
  final double width;

  /// The height of the row: the picture and the text under it.
  final double height;

  /// [width] over [height], what a card's own [AspectRatio] should be.
  final double ratio;

  const PosterCardMetrics({required this.width, required this.height, required this.ratio});
}

/// The card metrics for a row of pictures shaped [artRatio], with [maxLines]
/// lines of text under each. See [PosterCardMetrics].
///
/// [portraitRatio] is the cell shape that decides the width - the same 0.55
/// every row of portraits uses, so that a row of faces stands as wide as a row
/// of posters even though its pictures are round.
PosterCardMetrics posterCardMetrics(
  BuildContext context,
  WidgetRef ref, {
  required double artRatio,
  int maxLines = 3,
  double portraitRatio = 0.55,
}) {
  final width = horizontalListHeight(context, ref, dominantRatio: portraitRatio) * portraitRatio;
  final ratio = posterCardRatioForWidth(context, artRatio: artRatio, width: width, maxLines: maxLines);
  return PosterCardMetrics(width: width, height: width / ratio, ratio: ratio);
}

class PosterRow extends ConsumerWidget {
  final List<ItemBaseModel> posters;
  final String label;
  final double? collectionAspectRatio;
  final Function()? onLabelClick;
  final EdgeInsets contentPadding;
  final Function(ItemBaseModel focused)? onFocused;
  final List<jelly.ImageType>? imagePriority;
  final bool tvMode;
  final bool showSyncStatus;
  const PosterRow({
    required this.posters,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16),
    required this.label,
    this.collectionAspectRatio,
    this.onLabelClick,
    this.onFocused,
    this.imagePriority,
    this.tvMode = false,
    this.showSyncStatus = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mostCommon = posters.getMostCommonType;
    // A row asking for thumb/backdrop art first wants the wide ratio those
    // images actually have - the same case primaryPosters used to cover
    // before imagePriority replaced it.
    final preferredType = imagePriority?.firstOrNull;
    final isWideArt = preferredType == jelly.ImageType.thumb || preferredType == jelly.ImageType.backdrop;
    final dominantRatio = isWideArt ? 1.2 : collectionAspectRatio ?? mostCommon.aspectRatio;
    if (tvMode) {
      return TVPosterRow(
        posters: posters,
        label: label,
        primaryRatio: dominantRatio,
        contentPadding: contentPadding,
        onLabelClick: onLabelClick,
        onFocused: onFocused,
        autoFocus: ref.read(argumentsStateProvider).htpcMode ? FocusProvider.autoFocusOf(context) : false,
      );
    }
    // Cards as wide as this row's type has always made them, and as tall as
    // the picture whole with the text under it.
    final artRatio = isWideArt ? mostCommon.imageAspectRatio : mostCommon.posterArtRatio;
    final metrics = posterCardMetrics(context, ref, artRatio: artRatio, portraitRatio: dominantRatio);
    return HorizontalList(
      height: metrics.height,
      contentPadding: contentPadding,
      label: label,
      autoFocus: ref.read(argumentsStateProvider).htpcMode ? FocusProvider.autoFocusOf(context) : false,
      onLabelClick: onLabelClick,
      dominantRatio: metrics.ratio,
      items: posters,
      onFocused: (index) {
        if (onFocused != null) {
          onFocused?.call(posters[index]);
        } else {
          context.ensureVisible();
        }
      },
      itemBuilder: (context, index) {
        final poster = posters[index];
        return PosterWidget(
          key: Key(poster.id),
          poster: poster,
          aspectRatio: metrics.ratio,
          showSyncStatus: showSyncStatus,
          imagePriority: imagePriority,
        );
      },
    );
  }
}

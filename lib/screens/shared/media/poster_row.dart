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
    // the picture whole with the text under it. The height came first before
    // and the picture got what the text left, which at the default poster
    // size was a box wider than a poster - and cover-fit cropped every one.
    final cardWidth = horizontalListHeight(context, ref, dominantRatio: dominantRatio) * dominantRatio;
    final artRatio = isWideArt ? mostCommon.imageAspectRatio : mostCommon.posterArtRatio;
    final cardRatio = posterCardRatioForWidth(context, artRatio: artRatio, width: cardWidth);
    return HorizontalList(
      height: cardWidth / cardRatio,
      contentPadding: contentPadding,
      label: label,
      autoFocus: ref.read(argumentsStateProvider).htpcMode ? FocusProvider.autoFocusOf(context) : false,
      onLabelClick: onLabelClick,
      dominantRatio: cardRatio,
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
          aspectRatio: cardRatio,
          showSyncStatus: showSyncStatus,
          imagePriority: imagePriority,
        );
      },
    );
  }
}

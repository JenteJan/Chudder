import 'package:flutter/material.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/routes/nested_details_screen.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';

/// The item's own poster, sat on the artwork above the title and the buttons.
///
/// It is also the far end of the flight from whatever poster was tapped to open
/// the page — the same picture in the same shape, so the flight only changes
/// its size. That is the one thing a hero does well, and the reason this is
/// worth having on the page at all: the artwork band was the wrong destination
/// because nothing about a portrait poster survives being pulled into 16:9.
class DetailPoster extends StatelessWidget {
  final ItemBaseModel? item;

  /// Overrides the height it works out for itself from the artwork band.
  final double? height;

  const DetailPoster({required this.item, this.height, super.key});

  /// Whether this screen has room to stand a poster beside the title.
  ///
  /// A phone does not: the header stacks there, so the poster lands on its own
  /// row above the logo and pushes everything the page is actually about below
  /// the fold. Nothing renders it there, which also means there is no far end
  /// for a flight from the grid — so on a phone the poster simply is not part
  /// of the transition.
  static bool fitsBeside(BuildContext context) => AdaptiveLayout.viewSizeOf(context) != ViewSize.phone;

  @override
  Widget build(BuildContext context) {
    final image = item?.getPosters?.primary;
    if (image == null) return const SizedBox.shrink();

    if (!fitsBeside(context)) return const SizedBox.shrink();

    final radius = FladderTheme.smallShape.borderRadius;

    // Most of the band. The logo beside it is capped at about a third, because
    // it reads as a caption; the poster is the subject, and at half this size
    // it looked like a thumbnail that had wandered onto the artwork.
    final resolvedHeight = height ?? (detailArtworkHeight(context) * 0.78).clamp(260.0, 480.0);

    // The hero's child is the artwork alone, with the box that gives it a size
    // left outside: mid-flight a hero hands its child whatever rect it has
    // reached, and a child that insists on its own height would refuse to fill
    // it.
    final Widget artwork = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      // The same hairline the posters in a grid wear, so the one that arrives
      // is the one that left.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: FladderImage(image: image),
      ),
    );

    final tag = DetailHeroTag.of(context);

    return SizedBox(
      height: resolvedHeight,
      child: AspectRatio(
        aspectRatio: item?.primaryRatio ?? 2 / 3,
        child: tag == null ? artwork : Hero(tag: tag, child: artwork),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/theme.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/shimmer.dart';

/// A row of placeholders shaped and sized like the real one, for the moment
/// between a page opening and its contents arriving.
///
/// It takes its height from [horizontalListHeight] rather than a number of its
/// own, so swapping it for the row it stands in for moves nothing. The title is
/// real text and sits outside the sweep — the name of a row is known before its
/// contents are, and greying it out would only lose information.
class ShimmerPosterRow extends ConsumerWidget {
  final String? label;
  final EdgeInsets contentPadding;

  /// The shape of one item, as its own [AspectRatio] would give it.
  final double aspectRatio;

  /// What the real row passes to [HorizontalList], which is what decides the
  /// height. Not the same number as [aspectRatio].
  final double? dominantRatio;

  /// Whether items carry a line of text underneath.
  final bool showLabelLine;

  final int count;

  const ShimmerPosterRow({
    this.label,
    required this.contentPadding,
    required this.aspectRatio,
    this.dominantRatio,
    this.showLabelLine = true,
    this.count = 8,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final height = horizontalListHeight(context, ref, dominantRatio: dominantRatio);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (label != null)
          HorizontalListTitleBar(
            contentPadding: contentPadding,
            label: label,
          ),
        SizedBox(
          height: height,
          child: ClipRect(
            child: Shimmer(
              child: ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: contentPadding,
                itemCount: count,
                separatorBuilder: (context, index) => const SizedBox(width: horizontalListItemGap),
                itemBuilder: (context, index) => AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: ShimmerBox(borderRadius: FladderTheme.smallShape.borderRadius),
                      ),
                      if (showLabelLine) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ShimmerBox(height: 15, width: 110),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

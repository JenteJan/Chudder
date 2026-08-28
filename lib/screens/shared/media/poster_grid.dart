import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sticky_headers/sticky_headers.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/screens/shared/media/poster_widget.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/sticky_header_text.dart';

class PosterGrid extends ConsumerWidget {
  final String? name;
  final List<ItemBaseModel> posters;
  final Widget? Function(BuildContext context, int index)? itemBuilder;
  final bool stickyHeader;
  final Function(VoidCallback action, ItemBaseModel item)? onPressed;
  const PosterGrid(
      {this.stickyHeader = true, this.itemBuilder, this.name, required this.posters, this.onPressed, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiplier = ref.watch(clientSettingsProvider.select((value) => value.posterSize));
    // Sized like the library search grid: cells derived from the width this
    // grid actually gets, not the whole screen's. Inside a padded detail page
    // the old screen-width math crammed a full screen's worth of columns into
    // the narrower content area, shrinking every poster.
    var posterBuilder = LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
      final size = width / (AdaptiveLayout.poster(context).gridRatio * multiplier);
      // The same cell math as the library search grid, cap included — the
      // 10-column ceiling is what makes library posters grow on a wide
      // window, and without it this grid's posters always came out smaller.
      final cellWidth = (width / size).floorToDouble();
      final crossAxisCount = ((width / cellWidth).floor()).clamp(2, 10);
      final itemWidth = (width - 8 * (crossAxisCount - 1)) / crossAxisCount;
      return GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          // The whole-cell shape of what's actually in the grid, matching the
          // library grid: the picture whole at this column width, and the
          // text under it.
          childAspectRatio: posterCardRatioForWidth(
            context,
            artRatio: posters.getMostCommonType.posterArtRatio,
            width: itemWidth,
          ),
        ),
        itemCount: posters.length,
        itemBuilder: itemBuilder ??
            (context, index) {
              return PosterWidget(
                poster: posters[index],
                onPressed: onPressed,
              );
            },
      );
    });

    if (stickyHeader) {
      //Translate fixes small peaking pixel line
      return StickyHeader(
        header: name != null
            ? StickyHeaderText(label: name ?? "")
            : const SizedBox(
                height: 16,
              ),
        content: posterBuilder,
      );
    } else {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              name ?? "",
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          posterBuilder,
        ],
      );
    }
  }
}

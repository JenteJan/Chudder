import 'package:flutter/material.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/screens/jellybot/widgets/search_result_card.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';

class AdaptiveResultsView extends StatelessWidget {
  final List<ProviderSearchItemDto> items;
  final IProvider? provider;
  final String? addingItemUrl;
  final void Function(ProviderSearchItemDto) onAdd;

  const AdaptiveResultsView({
    super.key,
    required this.items,
    required this.provider,
    required this.addingItemUrl,
    required this.onAdd,
  });

  int _crossAxisCountFor(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.single) return 1;
    if (width >= 1400) return 3;
    if (width >= 900) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = _crossAxisCountFor(context);

    if (crossAxisCount == 1) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => SearchResultCard(
              item: items[index],
              provider: provider,
              isAdding: addingItemUrl == items[index].url,
              onAdd:
                  addingItemUrl != null ? null : () => onAdd(items[index]),
            ),
            childCount: items.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisExtent: 160,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => SearchResultCard(
            item: items[index],
            provider: provider,
            isAdding: addingItemUrl == items[index].url,
            onAdd: addingItemUrl != null ? null : () => onAdd(items[index]),
          ),
          childCount: items.length,
        ),
      ),
    );
  }
}

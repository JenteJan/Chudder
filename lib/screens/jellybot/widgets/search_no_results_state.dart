import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/util/localization_helper.dart';

class SearchNoResultsState extends StatelessWidget {
  final VoidCallback onClearFilters;
  final bool hasActiveFilters;

  const SearchNoResultsState({
    super.key,
    required this.onClearFilters,
    required this.hasActiveFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              IconsaxPlusLinear.search_status,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              context.localized.noResultsFound,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(IconsaxPlusLinear.filter_remove),
                label: Text(context.localized.jellybotClearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

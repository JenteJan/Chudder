import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/jellybot_search_provider.dart';
import 'package:fladder/util/localization_helper.dart';

/// Collapsible advanced-search panel: exact-match toggle + minimum-score slider.
///
/// The slider's auto-search trigger fires on `onChangeEnd` only — `onChanged`
/// just updates local visual state — so dragging the thumb doesn't spam the
/// API with one request per pixel.
class SearchAdvancedControls extends ConsumerStatefulWidget {
  const SearchAdvancedControls({super.key});

  @override
  ConsumerState<SearchAdvancedControls> createState() =>
      _SearchAdvancedControlsState();
}

class _SearchAdvancedControlsState
    extends ConsumerState<SearchAdvancedControls> {
  double? _draftMinScore;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(jellybotSearchControllerProvider.notifier);
    final state = controller.searchState;
    final liveScore = _draftMinScore ?? state.minScore ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(IconsaxPlusLinear.setting_4, size: 18),
                const SizedBox(width: 8),
                Text(
                  context.localized.jellybotAdvancedSearch,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(context.localized.jellybotExactMatch),
              subtitle: Text(context.localized.jellybotExactMatchHint),
              value: state.exactMatch,
              onChanged: (v) {
                controller.toggleExactMatch(v);
                setState(() {});
              },
            ),
            Row(
              children: [
                const Icon(IconsaxPlusLinear.activity, size: 16),
                const SizedBox(width: 8),
                Text(context.localized.jellybotMinScore),
                const SizedBox(width: 8),
                Text(
                  liveScore == 0
                      ? context.localized.off
                      : liveScore.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            Slider(
              value: liveScore,
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) => setState(() => _draftMinScore = v),
              onChangeEnd: (v) {
                _draftMinScore = null;
                controller.setMinScore(v == 0 ? null : v);
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

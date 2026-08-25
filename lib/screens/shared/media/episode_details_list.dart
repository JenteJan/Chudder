import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/screens/shared/media/episode_posters.dart';
import 'package:fladder/util/humanize_duration.dart';
import 'package:fladder/util/item_base_model/item_base_model_extensions.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/theme_extensions.dart';

enum EpisodeDetailsViewType {
  /// The scrolling row the show page opens with.
  row(icon: IconsaxPlusBold.row_horizontal),
  list(icon: IconsaxPlusBold.grid_6);

  const EpisodeDetailsViewType({required this.icon});

  String label(BuildContext context) => switch (this) {
        EpisodeDetailsViewType.row => context.localized.defaultLabel,
        EpisodeDetailsViewType.list => context.localized.list,
      };

  final IconData icon;
}

/// Picks which shape the episodes are in. Icon-only: it lives in a row's title,
/// next to a season picker that already carries the words.
class EpisodeViewTypeButton extends StatelessWidget {
  final EpisodeDetailsViewType current;
  final ValueChanged<EpisodeDetailsViewType> onChanged;
  const EpisodeViewTypeButton({required this.current, required this.onChanged, super.key});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<EpisodeDetailsViewType>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((state) {
          if (state.contains(WidgetState.selected)) {
            return context.colors.primaryContainer;
          }
          return context.colors.surfaceContainer;
        }),
        visualDensity: VisualDensity.compact,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        side: const WidgetStatePropertyAll(BorderSide.none),
      ),
      showSelectedIcon: false,
      segments: EpisodeDetailsViewType.values
          .map(
            (e) => ButtonSegment(
              value: e,
              icon: Icon(e.icon),
              tooltip: e.label(context),
            ),
          )
          .toList(),
      selected: {current},
      onSelectionChanged: (value) => onChanged(value.first),
    );
  }
}

class EpisodeDetailsList extends ConsumerWidget {
  final List<EpisodeModel> episodes;
  final EdgeInsets? padding;

  /// Marked the way the episode row marks the one you are on.
  final EpisodeModel? selectedEpisode;

  /// Given, a tap selects the episode where it stands instead of opening it.
  final ValueChanged<EpisodeModel>? onEpisodeTap;

  const EpisodeDetailsList({
    required this.episodes,
    this.padding,
    this.selectedEpisode,
    this.onEpisodeTap,
    super.key,
  });

  void Function() _tap(BuildContext context, EpisodeModel episode) =>
      onEpisodeTap != null ? () => onEpisodeTap!(episode) : () => episode.navigateTo(context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
        );
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final episode = episodes[index];
        List<Widget> children = [
          Flexible(
            flex: 1,
            child: EpisodePoster(
              episode: episode,
              showLabel: false,
              actions: episode.generateActions(context, ref),
              onTap: _tap(context, episode),
              isCurrentEpisode: episode.id == selectedEpisode?.id,
            ),
          ),
          const SizedBox(width: 16, height: 16),
          Flexible(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SelectableText(
                            episode.seasonEpisodeLabel(context.localized),
                            style: textStyle,
                          ),
                          if (episode.overview.runTime != null)
                            SelectableText(
                              " - ${episode.overview.runTime!.humanize!}",
                              style: textStyle,
                            ),
                        ],
                      ),
                      SelectableText(
                        episode.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      SelectableText(
                        episode.overview.summary,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ].addPadding(const EdgeInsets.symmetric(vertical: 4)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.all(8.0),
              child: Card(
                color: episode.id == selectedEpisode?.id ? context.colors.primaryContainer : null,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: constraints.maxWidth > 800
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: children,
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

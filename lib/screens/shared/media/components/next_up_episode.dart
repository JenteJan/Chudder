import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/screens/details_screens/components/media_stream_information.dart';
import 'package:chudder/screens/shared/media/episode_posters.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/sticky_header_text.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/widgets/shared/ensure_visible.dart';
import 'package:chudder/widgets/shared/horizontal_list.dart';

class NextUpEpisode extends ConsumerWidget {
  final EpisodeModel nextEpisode;
  final Function(EpisodeModel episode)? onChanged;
  const NextUpEpisode({required this.nextEpisode, this.onChanged, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alreadyPlayed = nextEpisode.userData.played;
    final episodeSummary = nextEpisode.overview.summary.maxLength(limitTo: 250);
    final style = Theme.of(context).textTheme.titleMedium;
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StickyHeaderText(
          label: alreadyPlayed ? context.localized.reWatch : context.localized.nextUp,
        ),
        SelectableText(
          nextEpisode.seasonEpisodeLabelFull(context.localized),
          style: style?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        SelectableText(
          nextEpisode.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 550) {
              return Column(
                children: [
                  EpisodePoster(
                    episode: nextEpisode,
                    showLabel: false,
                    onTap: () => nextEpisode.navigateTo(context),
                    actions: const [],
                    onFocusChanged: (value) {
                      if (value) {
                        context.ensureVisible();
                      }
                    },
                    isCurrentEpisode: false,
                  ),
                  const SizedBox(height: 16),
                  if (nextEpisode.overview.summary.isNotEmpty)
                    HtmlWidget(
                      episodeSummary,
                      textStyle: Theme.of(context).textTheme.titleMedium,
                    ),
                ],
              );
            } else {
              return Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: horizontalListHeight(context, ref), maxWidth: MediaQuery.of(context).size.width / 2),
                    child: EpisodePoster(
                      episode: nextEpisode,
                      showLabel: false,
                      onTap: () => nextEpisode.navigateTo(context),
                      actions: const [],
                      onFocusChanged: (value) {
                        if (value) {
                          context.ensureVisible();
                        }
                      },
                      isCurrentEpisode: false,
                    ),
                  ),
                  const SizedBox(width: 32),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MediaStreamInformation(
                          mediaStream: nextEpisode.mediaStreams,
                          onVersionIndexChanged: (index) => onChanged?.call(nextEpisode.copyWith(
                            mediaStreams: nextEpisode.mediaStreams.copyWith(versionStreamIndex: index),
                          )),
                          onAudioIndexChanged: (index) => onChanged?.call(nextEpisode.copyWith(
                              mediaStreams: nextEpisode.mediaStreams.copyWith(defaultAudioStreamIndex: index))),
                          onSubIndexChanged: (index) => onChanged?.call(nextEpisode.copyWith(
                              mediaStreams: nextEpisode.mediaStreams.copyWith(defaultSubStreamIndex: index))),
                        ),
                        if (nextEpisode.overview.summary.isNotEmpty)
                          HtmlWidget(episodeSummary, textStyle: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                  ),
                ],
              );
            }
          },
        ),
      ],
    );
  }
}

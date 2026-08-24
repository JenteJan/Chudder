import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overflow_view/overflow_view.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/video_player/components/video_volume_slider.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/duration_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/shared/player_bar_shared.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/minimized_segment_skip.dart';

class VideoFloatingPlayerBarContent extends ConsumerWidget {
  const VideoFloatingPlayerBarContent({
    super.key,
    required this.constraints,
    required this.item,
    required this.itemActions,
    required this.showExpandButton,
    required this.onShowExpandButton,
    required this.openFullScreenPlayer,
  });

  final BoxConstraints constraints;
  final ItemBaseModel? item;
  final List<ItemActionButton> itemActions;
  final bool showExpandButton;
  final ValueChanged<bool> onShowExpandButton;
  final VoidCallback openFullScreenPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(mediaPlaybackProvider.select((state) => (
          state: state.state,
          duration: state.duration,
          playing: state.playing,
        )));
    final player = ref.read(videoPlayerProvider);
    final nextVideo = ref.watch(playBackModel.select((value) => value?.nextVideo));
    // Same window the fullscreen next-up card uses as its fallback rule; a
    // boolean select so the bar doesn't rebuild on every position tick.
    final inNextUpWindow = nextVideo != null &&
        ref.watch(mediaPlaybackProvider.select((s) =>
            s.duration > const Duration(seconds: 40) && (s.duration - s.position) < const Duration(seconds: 32)));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              spacing: 12,
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (playbackState.state == VideoPlayerState.minimized)
                  FloatingPlayerBarPreview(
                    ratio: 16 / 9,
                    showExpandButton: showExpandButton,
                    onShowExpandButton: onShowExpandButton,
                    openFullScreenPlayer: openFullScreenPlayer,
                    child: player.videoWidget(
                          const ValueKey("mini_player_video"),
                          BoxFit.fitHeight,
                        ) ??
                        const SizedBox.shrink(),
                  ),
                Expanded(
                  child: FloatingPlayerBarTitle(
                    title: item?.title ?? "",
                    subtitle: inNextUpWindow
                        ? "${context.localized.upNext}: ${nextVideo.detailedName(context.localized) ?? nextVideo.title}"
                        : item?.detailedName(context.localized) ?? "",
                    onTap: () => item?.navigateTo(context),
                  ),
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (constraints.maxWidth > 500)
                        Consumer(
                          builder: (context, ref, _) {
                            final pos = ref.watch(mediaPlaybackProvider.select((s) => s.position));
                            return Flexible(
                              child: Text(
                                "${pos.readAbleDuration} / ${playbackState.duration.readAbleDuration}",
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withAlpha(125),
                                    ),
                              ),
                            );
                          },
                        ),
                      // Desktop gets the same hover-to-unroll volume control
                      // as the fullscreen player; the panel opens upward,
                      // above the bar.
                      if (AdaptiveLayout.of(context).isDesktop)
                        const Flexible(child: VideoVolumeSlider(collapsed: true)),
                      // Intro/recap/commercial skip: the fullscreen controls
                      // that normally offer it are gone while minimized.
                      Flexible(
                        child: MinimizedSegmentSkip(
                          builder: (context, segment, skip, dimmed) => AnimatedOpacity(
                            opacity: dimmed ? 0.45 : 1,
                            duration: const Duration(milliseconds: 500),
                            child: constraints.maxWidth > 500
                                ? FilledButton.tonalIcon(
                                    onPressed: skip,
                                    icon: const Icon(Icons.fast_forward_rounded),
                                    label: Text(
                                      context.localized.skipButtonLabel(segment.type.label(context)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : IconButton.filledTonal(
                                    onPressed: skip,
                                    tooltip: context.localized.skipButtonLabel(segment.type.label(context)),
                                    icon: const Icon(Icons.fast_forward_rounded),
                                  ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: IconButton.filledTonal(
                            onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
                            icon: playbackState.playing
                                ? const Icon(Icons.pause_rounded)
                                : const Icon(Icons.play_arrow_rounded),
                          ),
                        ),
                      ),
                      if (nextVideo != null)
                        Flexible(
                          child: Tooltip(
                            message:
                                "${context.localized.upNext}: ${nextVideo.detailedName(context.localized) ?? nextVideo.title}",
                            // Lights up during the credits so the bar gets the
                            // same "next episode is ready" cue the fullscreen
                            // card gives.
                            child: inNextUpWindow
                                ? IconButton.filled(
                                    onPressed: () => ref.read(videoPlayerProvider).loadNextVideo(),
                                    icon: const Icon(Icons.skip_next_rounded),
                                  )
                                : IconButton.filledTonal(
                                    onPressed: () => ref.read(videoPlayerProvider).loadNextVideo(),
                                    icon: const Icon(Icons.skip_next_rounded),
                                  ),
                          ),
                        ),
                      Flexible(
                        child: OverflowView.flexible(
                          builder: (context, remainingItemCount) => PopupMenuButton(
                            iconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                            padding: EdgeInsets.zero,
                            itemBuilder: (context) => itemActions
                                .sublist(itemActions.length - remainingItemCount)
                                .map((e) => e.toPopupMenuItem(useIcons: true))
                                .toList(),
                          ),
                          children: itemActions.map((e) => e.toButton()).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        FloatingPlayerBarProgress(
          // Through userSeek, not the raw player: while in a SyncPlay group
          // the raw path never told the server, so a scrub here silently got
          // reverted by the next group command. userSeek also resumes
          // playback itself when it was playing.
          onSeek: (pos) => ref.read(videoPlayerProvider.notifier).userSeek(pos),
        ),
      ],
    );
  }
}

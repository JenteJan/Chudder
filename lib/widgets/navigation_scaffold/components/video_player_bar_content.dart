import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overflow_view/overflow_view.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/video_volume_slider.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/duration_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/widgets/navigation_scaffold/components/floating_video_window.dart';
import 'package:chudder/widgets/navigation_scaffold/components/shared/player_bar_shared.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/minimized_segment_skip.dart';

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
                  child: _BarControls(
                    constraints: constraints,
                    playing: playbackState.playing,
                    duration: playbackState.duration,
                    nextVideo: nextVideo,
                    inNextUpWindow: inNextUpWindow,
                    itemActions: itemActions,
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

/// The trailing controls, in the order they matter. What must always be
/// reachable has a seat of its own - play/pause, and the way into the
/// floating window - and everything after it folds into the menu at the end
/// as the width runs out, rather than spilling over the title. The time and
/// the volume control are extras the wider bars get.
class _BarControls extends ConsumerWidget {
  const _BarControls({
    required this.constraints,
    required this.playing,
    required this.duration,
    required this.nextVideo,
    required this.inNextUpWindow,
    required this.itemActions,
  });

  final BoxConstraints constraints;
  final bool playing;
  final Duration duration;
  final ItemBaseModel? nextVideo;
  final bool inNextUpWindow;
  final List<ItemActionButton> itemActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = constraints.maxWidth;
    final desktop = AdaptiveLayout.of(context).isDesktop;
    final showTime = width > 640;
    final showVolume = desktop && width > 540;
    final canFloat = canUseFloatingVideoWindow(context, ref);
    final next = nextVideo;
    final nextLabel =
        next == null ? null : "${context.localized.upNext}: ${next.detailedName(context.localized) ?? next.title}";

    // Each with an entry for the menu, for when it does not fit.
    final foldable = <(Widget, ItemActionButton)>[
      if (next != null)
        (
          Tooltip(
            message: nextLabel!,
            // Lights up during the credits so the bar gets the same "next
            // episode is ready" cue the fullscreen card gives.
            child: inNextUpWindow
                ? IconButton.filled(
                    onPressed: () => ref.read(videoPlayerProvider).loadNextVideo(),
                    icon: const Icon(Icons.skip_next_rounded),
                  )
                : IconButton(
                    onPressed: () => ref.read(videoPlayerProvider).loadNextVideo(),
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
          ),
          ItemActionButton(
            label: Text(nextLabel),
            icon: const Icon(Icons.skip_next_rounded),
            action: () => ref.read(videoPlayerProvider).loadNextVideo(),
          ),
        ),
      // The slider needs room; a plain mute stands in for it when there is none.
      if (desktop && !showVolume)
        (
          Consumer(
            builder: (context, ref, _) {
              final volume = ref.watch(videoPlayerSettingsProvider.select((value) => value.volume));
              return IconButton(
                tooltip: volume == 0 ? "Unmute" : context.localized.mute,
                onPressed: () => ref.read(videoPlayerSettingsProvider.notifier).toggleMute(),
                icon: Icon(volumeIcon(volume)),
              );
            },
          ),
          ItemActionButton(
            label: Text(context.localized.mute),
            icon: const Icon(Icons.volume_off_rounded),
            action: () => ref.read(videoPlayerSettingsProvider.notifier).toggleMute(),
          ),
        ),
      for (final action in itemActions) (action.toButton(), action),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showTime)
          Consumer(
            builder: (context, ref, _) {
              final pos = ref.watch(mediaPlaybackProvider.select((s) => s.position));
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  "${pos.readAbleDuration} / ${duration.readAbleDuration}",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(125),
                      ),
                ),
              );
            },
          ),
        // Desktop gets the same hover-to-unroll volume control as the
        // fullscreen player; the panel opens upward, above the bar.
        if (showVolume) const VideoVolumeSlider(collapsed: true),
        // Intro/recap/commercial skip: the fullscreen controls that normally
        // offer it are gone while minimized.
        MinimizedSegmentSkip(
          builder: (context, segment, skip, dimmed) => AnimatedOpacity(
            opacity: dimmed ? 0.45 : 1,
            duration: const Duration(milliseconds: 500),
            child: width > 640
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: IconButton.filledTonal(
            onPressed: () => ref.read(videoPlayerProvider.notifier).userPlayOrPause(),
            icon: playing ? const Icon(Icons.pause_rounded) : const Icon(Icons.play_arrow_rounded),
          ),
        ),
        // Only offered for playback the window can actually show; the bar is
        // the only option for audio and casting. Always in view: it used to
        // be one of the actions, and the first to vanish into the menu.
        if (canFloat)
          IconButton(
            tooltip: "Floating window",
            onPressed: () => ref.read(floatingVideoWindowOverrideProvider.notifier).state = true,
            icon: const Icon(Icons.picture_in_picture_alt_rounded),
          ),
        Flexible(
          child: OverflowView.flexible(
            builder: (context, remainingItemCount) => PopupMenuButton(
              iconColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
              padding: EdgeInsets.zero,
              itemBuilder: (context) => foldable
                  .sublist(foldable.length - remainingItemCount)
                  .map((e) => e.$2.toPopupMenuItem(useIcons: true))
                  .toList(),
            ),
            children: [for (final e in foldable) e.$1],
          ),
        ),
      ],
    );
  }
}

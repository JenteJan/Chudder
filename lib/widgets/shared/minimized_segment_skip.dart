import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/media_segments_model.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';

/// Segment skipping - intro, recap, commercial, preview - for the minimized
/// players.
///
/// The fullscreen controls carry both the skip button and the auto-skip, and
/// minimizing pops the player route out from under them: an intro reached from
/// the floating window or the bar could until now neither be skipped nor skip
/// itself. This puts both back and leaves the drawing to [builder], so each
/// surface can offer it in its own language.
///
/// Outros are deliberately left out: by then the next-up button is already on
/// screen offering the next episode, which is the better answer than seeking
/// to the last second of this one.
class MinimizedSegmentSkip extends ConsumerStatefulWidget {
  const MinimizedSegmentSkip({required this.builder, super.key});

  /// Draws the affordance for [segment]; only called while one is on offer.
  /// [dimmed] is set once the segment is well underway - the same fade the
  /// fullscreen button uses to get out of the way without vanishing.
  final Widget Function(BuildContext context, MediaSegment segment, VoidCallback skip, bool dimmed) builder;

  @override
  ConsumerState<MinimizedSegmentSkip> createState() => _MinimizedSegmentSkipState();
}

class _MinimizedSegmentSkipState extends ConsumerState<MinimizedSegmentSkip> {
  /// Segment an auto-skip is already on its way for, so the position ticks
  /// that arrive before the seek lands don't fire it again.
  String? _autoSkipping;

  void _skip(MediaSegment segment, {String? remember}) {
    ref.read(videoPlayerProvider.notifier).userSeek(segment.end);
    if (remember == null) return;
    // Deferred: this runs from build for an auto-skip, where providers can't
    // be written to.
    Future(() {
      if (!mounted) return;
      final skipped = ref.read(mediaPlaybackProvider).skippedSegments;
      ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(skippedSegments: {
            ...skipped,
            remember,
          }));
    });
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(playBackModel.select((value) => value?.mediaSegments));
    if (segments == null) return const SizedBox.shrink();

    final position = ref.watch(mediaPlaybackProvider.select((value) => value.position));
    final segment = segments.atPosition(position);
    if (segment == null || segment.type == MediaSegmentType.outro) {
      if (_autoSkipping != null) _autoSkipping = null;
      return const SizedBox.shrink();
    }

    final skipType = ref.watch(videoPlayerSettingsProvider.select((value) => value.segmentSkipSettings[segment.type]));
    if (skipType == null || skipType == SegmentSkip.none) return const SizedBox.shrink();

    final visibility = segment.visibility(position);
    if (visibility == SegmentVisibility.hidden) return const SizedBox.shrink();

    // A segment's range includes its end, so the one just skipped is still the
    // segment at the position landed on. Offering it again would seek to where
    // we already are.
    if (segment.end - position < const Duration(seconds: 1)) return const SizedBox.shrink();

    final buffering = ref.watch(mediaPlaybackProvider.select((value) => value.buffering));
    final skipped = ref.watch(mediaPlaybackProvider.select((value) => value.skippedSegments));
    final autoSkip = !buffering &&
        (skipType == SegmentSkip.skip || (skipType == SegmentSkip.skipOnce && !skipped.contains(segment.skipId)));

    if (autoSkip) {
      if (_autoSkipping != segment.skipId) {
        _autoSkipping = segment.skipId;
        _skip(segment, remember: segment.skipId);
      }
      // No button for a segment that is skipping itself.
      return const SizedBox.shrink();
    }
    _autoSkipping = null;

    // A manual skip stays unremembered, like the fullscreen button: "skip
    // once" means once by itself, not once ever.
    return widget.builder(context, segment, () => _skip(segment), visibility == SegmentVisibility.partially);
  }
}

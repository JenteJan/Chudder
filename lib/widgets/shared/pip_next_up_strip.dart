import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/providers/pip_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/localization_helper.dart';

/// The picture-in-picture stand-in for the next-up card. PiP windows can't
/// take touches for in-app UI, so instead of offering a button this does what
/// the fullscreen card's countdown does: names what's next, counts down the
/// remaining seconds, and starts it by itself when the episode runs out — no
/// more dead air at the end of an episode watched in PiP.
class PipNextUpStrip extends ConsumerStatefulWidget {
  const PipNextUpStrip({super.key});

  @override
  ConsumerState<PipNextUpStrip> createState() => _PipNextUpStripState();
}

class _PipNextUpStripState extends ConsumerState<PipNextUpStrip> {
  /// The item an auto-advance has already fired for, so one ending episode
  /// can't queue the next one twice off two position ticks.
  String? _advancedFromId;

  @override
  Widget build(BuildContext context) {
    final inPip = ref.watch(pipStateProvider).asData?.value ?? false;
    final nextVideo = ref.watch(playBackModel.select((value) => value?.nextVideo));
    final autoNext = ref.watch(videoPlayerSettingsProvider.select((value) => value.nextVideoType));

    ref.listen(mediaPlaybackProvider.select((s) => s.position), (previous, next) {
      if (!inPip || nextVideo == null || autoNext == AutoNextType.off) return;
      final model = ref.read(mediaPlaybackProvider);
      if (model.duration < const Duration(seconds: 40) || !model.playing) return;
      final currentId = ref.read(playBackModel)?.item.id;
      if (currentId == null || currentId == _advancedFromId) return;
      if (model.duration - next < const Duration(milliseconds: 750)) {
        _advancedFromId = currentId;
        ref.read(videoPlayerProvider).loadNextVideo();
      }
    });

    if (!inPip || nextVideo == null || autoNext == AutoNextType.off) return const SizedBox.shrink();

    final remaining = ref.watch(mediaPlaybackProvider.select((s) {
      if (s.duration < const Duration(seconds: 40)) return null;
      final left = s.duration - s.position;
      return left < const Duration(seconds: 32) ? left : null;
    }));
    if (remaining == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final seconds = remaining.inSeconds.clamp(0, 99);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Icon(Icons.skip_next_rounded, size: 14, color: scheme.onPrimaryContainer),
              Flexible(
                child: Text(
                  "${context.localized.upNext} ${seconds}s · ${nextVideo.detailedName(context.localized) ?? nextVideo.title}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

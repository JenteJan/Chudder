import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/providers/settings/subtitle_settings_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_timing_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/util/subtitle_position_calculator.dart';

/// The subtitles over the picture. The player draws them - except while
/// they are moved in time on a player that cannot move them itself; then
/// the app draws the same lines from the subtitle file, later or earlier.
class SubtitleLayer extends ConsumerWidget {
  const SubtitleLayer({
    required this.playerSubtitles,
    required this.showOverlay,
    this.controlsKey,
    super.key,
  });

  final Widget? playerSubtitles;
  final bool showOverlay;
  final GlobalKey? controlsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // While a line is timed by ear the subtitles would lead the tap.
    final tapping = ref.watch(subtitleTimingProvider.select((t) => t.match?.picked != null));
    if (tapping) return const SizedBox.shrink();
    final cues = ref.watch(subtitleTimingProvider.select((t) => t.cues != null));
    if (cues) return _AppSubtitles(showOverlay: showOverlay, controlsKey: controlsKey);
    return playerSubtitles ?? const SizedBox.shrink();
  }
}

class _AppSubtitles extends ConsumerStatefulWidget {
  const _AppSubtitles({required this.showOverlay, this.controlsKey});
  final bool showOverlay;
  final GlobalKey? controlsKey;

  @override
  ConsumerState<_AppSubtitles> createState() => _AppSubtitlesState();
}

class _AppSubtitlesState extends ConsumerState<_AppSubtitles> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  String _text = '';
  double? _menuHeight;

  /// The last position the player reported, and when: positions arrive a
  /// few times a second, the lines are placed between them.
  Duration _anchor = Duration.zero;
  final Stopwatch _since = Stopwatch();

  @override
  void initState() {
    super.initState();
    _anchor = ref.read(mediaPlaybackProvider).position;
    _since.start();
    _ticker = createTicker((_) => _tick())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick() {
    final playback = ref.read(mediaPlaybackProvider);
    final timing = ref.read(subtitleTimingProvider);
    final cues = timing.cues;
    if (cues == null) return;
    if (playback.position != _anchor) {
      _anchor = playback.position;
      _since
        ..reset()
        ..start();
    }
    final speed = playback.playing ? ref.read(playbackRateProvider) : 0.0;
    // Never run ahead of the next report by more than a moment.
    final elapsed = Duration(milliseconds: (_since.elapsedMilliseconds.clamp(0, 1000) * speed).round());
    // Moved later means a line shows when the picture is that much further on.
    final text = cues.textAt(_anchor + elapsed - timing.delay);
    if (text != _text) setState(() => _text = text);
  }

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = widget.controlsKey?.currentContext?.findRenderObject() as RenderBox?;
      final height = box?.hasSize == true ? box!.size.height : null;
      if (height != null && height != _menuHeight) setState(() => _menuHeight = height);
    });
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    if (_text.isEmpty) return const SizedBox.shrink();
    final SubtitleSettingsModel settings = ref.watch(subtitleSettingsProvider);
    return SubtitleText(
      subModel: settings,
      padding: MediaQuery.paddingOf(context),
      offset: SubtitlePositionCalculator.calculateOffset(
        settings: settings,
        showOverlay: widget.showOverlay,
        screenHeight: MediaQuery.sizeOf(context).height,
        menuHeight: _menuHeight,
      ),
      text: _text,
    );
  }
}

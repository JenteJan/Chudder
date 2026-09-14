import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:overflow_view/overflow_view.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/shared/flat_button.dart';
import 'package:chudder/screens/video_player/components/minimized_video_surfaces.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/duration_extensions.dart';
import 'package:chudder/widgets/shared/fladder_slider.dart';
import 'package:chudder/widgets/shared/item_actions.dart';

class FloatingPlayerBarPreview extends ConsumerStatefulWidget {
  const FloatingPlayerBarPreview({
    super.key,
    this.ratio = 1.0,
    required this.showExpandButton,
    required this.onShowExpandButton,
    required this.openFullScreenPlayer,
    required this.child,
  });

  final double ratio;
  final bool showExpandButton;
  final ValueChanged<bool> onShowExpandButton;
  final VoidCallback openFullScreenPlayer;
  final Widget child;

  @override
  ConsumerState<FloatingPlayerBarPreview> createState() => _FloatingPlayerBarPreviewState();
}

class _FloatingPlayerBarPreviewState extends ConsumerState<FloatingPlayerBarPreview> {
  static const _radius = 4.0;

  /// The thumbnail, signed in as the picture the full-screen player grows
  /// out of and shrinks back into.
  final GlobalKey _videoKey = GlobalKey(debugLabel: 'playerBarPreview');

  @override
  void initState() {
    super.initState();
    MinimizedVideoSurfaces.register(_videoKey, radius: _radius);
  }

  @override
  void dispose() {
    MinimizedVideoSurfaces.unregister(_videoKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: AspectRatio(
        aspectRatio: widget.ratio,
        child: MouseRegion(
          onEnter: (_) => widget.onShowExpandButton(true),
          onExit: (_) => widget.onShowExpandButton(false),
          child: Stack(
            children: [
              ClipRRect(
                key: _videoKey,
                borderRadius: BorderRadius.circular(_radius),
                // Blank while the big picture is on its way here (see
                // videoPictureInFlightProvider); over a details page this
                // bar sits above the player's route.
                child: Visibility(
                  visible: !ref.watch(videoPictureInFlightProvider),
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  child: widget.child,
                ),
              ),
              Positioned.fill(
                child: Tooltip(
                  message: "Expand player",
                  waitDuration: const Duration(milliseconds: 500),
                  child: AnimatedOpacity(
                    opacity: widget.showExpandButton ? 1 : 0,
                    duration: const Duration(milliseconds: 125),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      child: FlatButton(
                        onTap: widget.openFullScreenPlayer,
                        child: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class FloatingPlayerBarTitle extends StatelessWidget {
  const FloatingPlayerBarTitle({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}

class FloatingPlayerBarActionsRow extends StatelessWidget {
  const FloatingPlayerBarActionsRow({
    super.key,
    required this.constraints,
    required this.playbackInfo,
    required this.lastPosition,
    required this.onPlayPause,
    required this.itemActions,
  });

  final BoxConstraints constraints;
  final MediaPlaybackModel playbackInfo;
  final Duration lastPosition;
  final VoidCallback onPlayPause;
  final List<ItemActionButton> itemActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (constraints.maxWidth > 500)
          Flexible(
            child: Text("${lastPosition.readAbleDuration} / ${playbackInfo.duration.readAbleDuration}"),
          ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: IconButton.filledTonal(
              onPressed: onPlayPause,
              icon: playbackInfo.playing ? const Icon(Icons.pause_rounded) : const Icon(Icons.play_arrow_rounded),
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
        )
      ],
    );
  }
}

class FloatingPlayerBarProgress extends ConsumerStatefulWidget {
  const FloatingPlayerBarProgress({
    super.key,
    required this.onSeek,
  });

  final Future<void> Function(Duration) onSeek;

  @override
  ConsumerState<FloatingPlayerBarProgress> createState() => _FloatingPlayerBarProgressState();
}

class _FloatingPlayerBarProgressState extends ConsumerState<FloatingPlayerBarProgress> {
  Duration? _dragPosition;

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(mediaPlaybackProvider.select((s) => (
          position: s.position,
          duration: s.duration,
        )));
    final position = _dragPosition ?? playback.position;

    return AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer
        ? SizedBox(
            height: 8,
            child: FladderSlider(
              value: position.inMilliseconds.toDouble(),
              min: 0.0,
              max: playback.duration.inMilliseconds.toDouble(),
              thumbWidth: 8,
              onChangeStart: (value) => setState(() => _dragPosition = Duration(milliseconds: value.toInt())),
              onChanged: (value) => setState(() => _dragPosition = Duration(milliseconds: value.toInt())),
              onChangeEnd: (value) async {
                final seekPos = Duration(milliseconds: value.toInt());
                setState(() => _dragPosition = seekPos);
                await widget.onSeek(seekPos);
                if (mounted) setState(() => _dragPosition = null);
              },
            ),
          )
        : LinearProgressIndicator(
            minHeight: 8,
            backgroundColor: Colors.black.withValues(alpha: 0.25),
            color: Theme.of(context).colorScheme.primary,
            value: playback.duration.inMilliseconds > 0
                ? (position.inMilliseconds / playback.duration.inMilliseconds).clamp(0, 1)
                : 0,
          );
  }
}

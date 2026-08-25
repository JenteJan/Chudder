import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/widgets/shared/fladder_slider.dart';

class VideoVolumeSlider extends ConsumerStatefulWidget {
  final double? width;

  /// Called whenever the user touches the control — including hovering the
  /// collapsed one, which is what keeps the player's chrome from fading out
  /// from under an open slider.
  final Function()? onChanged;

  /// Shows the mute button alone and unrolls the slider upwards, over the
  /// video, while the pointer is on it. Only worth doing where the row cannot
  /// spare the 180px the slider takes lying down — laid out inline in a narrow
  /// window it pushed the full-screen button off the edge.
  final bool collapsed;

  /// Fires as the unrolled panel opens and closes. The panel floats in the
  /// app's overlay, above whatever chrome placed this button, so the chrome
  /// stops seeing the pointer and would otherwise fade out from under it.
  final Function(bool open)? onPanelVisible;

  /// Holds the panel open regardless of the pointer.
  ///
  /// A remote has no pointer to hover with, so the collapsed control had no way
  /// to unroll: focus landed on it and nothing happened. Set while it holds
  /// focus, the slider is up for as long as it is the selected control.
  final bool forceOpen;

  const VideoVolumeSlider({
    this.width,
    this.onChanged,
    this.collapsed = false,
    this.forceOpen = false,
    this.onPanelVisible,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoVolumeSliderState();
}

class _VideoVolumeSliderState extends ConsumerState<VideoVolumeSlider> {
  bool sliderActive = false;
  bool mouseHovering = false;

  double? previousVolume;

  final LayerLink _link = LayerLink();
  final OverlayPortalController _panel = OverlayPortalController();

  /// Tracked apart because the pointer crosses between the two: the panel
  /// floats in the app's overlay, not inside the button.
  bool _onButton = false;
  bool _onPanel = false;

  void onPointerScroll(PointerScrollEvent event) {
    // Not gated on [mouseHovering]: a Listener only ever sees signals over its
    // own subtree, so the pointer being there is already established - and the
    // unrolled panel sits in the app's overlay, where the button's MouseRegion
    // never fires and that flag stays false.
    if (sliderActive) return;
    final volume = ref.read(videoPlayerSettingsProvider).volume;
    final delta = event.scrollDelta.dy / 100.0 * 4.5;
    final newVolume = (volume - delta).clamp(0.0, 100.0);
    ref.read(videoPlayerSettingsProvider.notifier).setVolume(newVolume);
    widget.onChanged?.call();
  }

  /// The wheel sets the volume anywhere the control is, the floating panel
  /// included - which needs its own listener, being a separate subtree.
  Widget _scrollable(Widget child) => Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) onPointerScroll(signal);
        },
        child: child,
      );

  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    if (widget.forceOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.forceOpen) _openPanel();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.forceOpen == oldWidget.forceOpen) return;
    if (widget.forceOpen) {
      _openPanel();
    } else {
      _closePanelSoon();
    }
  }

  void _openPanel() {
    _closeTimer?.cancel();
    if (_panel.isShowing) return;
    _panel.show();
    widget.onPanelVisible?.call(true);
  }

  /// Leaving the button and arriving on the panel are separate events, and the
  /// leave lands first — reaching up to grab the slider passes through a moment
  /// where the pointer belongs to neither. Closing on a grace period rather
  /// than on the next frame lets that moment go by.
  void _closePanelSoon() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _onButton || _onPanel || sliderActive || widget.forceOpen) return;
      if (!_panel.isShowing) return;
      _panel.hide();
      widget.onPanelVisible?.call(false);
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    if (_panel.isShowing) widget.onPanelVisible?.call(false);
    super.dispose();
  }

  void _setVolume(double value) {
    widget.onChanged?.call();
    ref.read(videoPlayerSettingsProvider.notifier).setVolume(value);
  }

  void _toggleMute(double volume) {
    if (volume != 0) previousVolume = volume;
    widget.onChanged?.call();
    ref.read(videoPlayerSettingsProvider.notifier).setVolume(volume == 0 ? (previousVolume ?? 100) : 0);
  }

  Widget _muteButton(double volume) => IconButton(
        icon: Icon(volumeIcon(volume)),
        onPressed: () => _toggleMute(volume),
      );

  Widget _slider(double volume) => FladderSlider(
        min: 0,
        max: 100,
        value: volume,
        onChangeStart: (value) => setState(() => sliderActive = true),
        onChangeEnd: (value) {
          setState(() => sliderActive = false);
          _closePanelSoon();
        },
        onChanged: _setVolume,
      );

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(videoPlayerSettingsProvider.select((value) => value.volume));
    return _scrollable(
      MouseRegion(
        onEnter: (_) {
          setState(() => mouseHovering = true);
          widget.onChanged?.call();
        },
        onExit: (_) => setState(() => mouseHovering = false),
        child: widget.collapsed ? _collapsed(volume) : _expanded(volume),
      ),
    );
  }

  Widget _expanded(double volume) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _muteButton(volume),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: SizedBox(height: 30, width: 75, child: _slider(volume)),
        ),
        SizedBox(
          width: 40,
          child: Text(
            (volume).toStringAsFixed(0),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ].addInBetween(const SizedBox(width: 6)),
    );
  }

  Widget _collapsed(double volume) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _panel,
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            child: MouseRegion(
              onEnter: (_) {
                _onPanel = true;
                widget.onChanged?.call();
                _openPanel();
              },
              onExit: (_) {
                _onPanel = false;
                _closePanelSoon();
              },
              // Transparent skirt down to the button's top edge, so the two
              // hover regions meet rather than leaving a seam to fall through.
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _scrollable(_panelBody(volume)),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            _onButton = true;
            _openPanel();
          },
          onExit: (_) {
            _onButton = false;
            _closePanelSoon();
          },
          child: _muteButton(volume),
        ),
      ),
    );
  }

  Widget _panelBody(double volume) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // Deeper at the bottom than the top: the readout and its gap already
        // stand the track well clear of the top edge, so an even inset left
        // the zero end of the slider sitting almost on the panel's rim.
        padding: const EdgeInsets.only(top: 12, bottom: 20, left: 9, right: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              volume.toStringAsFixed(0),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            // Turned three quarters rather than one so zero sits at the bottom
            // and the track fills upwards, the way the level reads.
            RotatedBox(
              quarterTurns: 3,
              child: SizedBox(height: 30, width: 110, child: _slider(volume)),
            ),
          ],
        ),
      ),
    );
  }
}

IconData volumeIcon(double value) {
  if (value <= 0) {
    return IconsaxPlusLinear.volume_mute;
  }
  if (value < 50) {
    return IconsaxPlusLinear.volume_low_1;
  }
  return IconsaxPlusLinear.volume_high;
}

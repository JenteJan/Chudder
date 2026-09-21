import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PinchPosterZoom extends ConsumerStatefulWidget {
  final Widget child;
  final Function(double difference)? scaleDifference;
  const PinchPosterZoom({required this.child, this.scaleDifference, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _PinchPosterZoomState();
}

class _PinchPosterZoomState extends ConsumerState<PinchPosterZoom> {
  double lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    // Asked before the gesture rather than after it. The recognizer used to be
    // installed whichever way the setting was set - it was only read once a
    // scale had already begun - and on a mouse a scale recognizer claims the
    // press a pixel or two of movement in, before a tap has any say. So a
    // press made without stopping the pointer first was taken from the card
    // under it and nothing happened at all, on every page that offers the
    // zoom: the dashboards, the favourites, the library.
    final enabled = ref.watch(clientSettingsProvider.select((value) => value.pinchPosterZoom));
    if (!enabled) return widget.child;
    return GestureDetector(
      // Pinching is a touch and a trackpad gesture. A mouse cannot make one,
      // so it is never allowed to start one and a press of a mouse is left to
      // whatever was pressed.
      supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.trackpad},
      onScaleStart: (details) {
        lastScale = 1;
      },
      onScaleUpdate: (details) {
        final difference = details.scale - lastScale;
        widget.scaleDifference?.call(difference);
        lastScale = details.scale;
      },
      child: widget.child,
    );
  }
}

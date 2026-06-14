import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether to expose the system AirPlay picker. iOS and macOS — both register a
/// native `AVRoutePickerView` platform view. No AirPlay sender on
/// Android/Windows/Linux.
bool get airPlaySupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// Wraps the iOS `AVRoutePickerView` as a Flutter widget. Tapping opens
/// Apple's AirPlay sheet; the system handles connection state and audio
/// routing once the user picks a target. Video AirPlay is not supported
/// (media-kit/mpv ≠ AVPlayer).
class AirPlayRouteButton extends StatelessWidget {
  const AirPlayRouteButton({
    super.key,
    this.size = 36,
    this.tintColor,
    this.activeTintColor,
  });

  final double size;
  final Color? tintColor;
  final Color? activeTintColor;

  @override
  Widget build(BuildContext context) {
    if (!airPlaySupported) return const SizedBox.shrink();

    final tint = tintColor ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final activeTint = activeTintColor ?? Theme.of(context).colorScheme.primary;

    const viewType = 'nl.jknaapen.fladder/airplay_route_picker';
    final creationParams = <String, double>{
      'tintR': tint.r,
      'tintG': tint.g,
      'tintB': tint.b,
      'tintA': tint.a,
      'activeR': activeTint.r,
      'activeG': activeTint.g,
      'activeB': activeTint.b,
      'activeA': activeTint.a,
    };

    return SizedBox(
      width: size,
      height: size,
      child: Platform.isMacOS
          ? AppKitView(
              viewType: viewType,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            )
          : UiKitView(
              viewType: viewType,
              creationParams: creationParams,
              creationParamsCodec: const StandardMessageCodec(),
            ),
    );
  }
}

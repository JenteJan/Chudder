import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

/// iOS AirPlay entry: the native `AVRoutePickerView`. Tapping it opens Apple's
/// device sheet. When an AirPlay device is actually selected, the native side
/// reports it (`onAirPlayRouteChanged`) and we swap in the AVPlayer-backed
/// player; if the user cancels or deselects, nothing stays "connected".
class AirPlayRoutePicker extends ConsumerStatefulWidget {
  const AirPlayRoutePicker({super.key, this.size = 40});

  final double size;

  @override
  ConsumerState<AirPlayRoutePicker> createState() => _AirPlayRoutePickerState();
}

class _AirPlayRoutePickerState extends ConsumerState<AirPlayRoutePicker> {
  static const _channel = MethodChannel('nl.jknaapen.fladder/airplay');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_onNativeCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method != 'onAirPlayRouteChanged') return;
    final active = (call.arguments as Map?)?['active'] == true;
    final notifier = ref.read(castProvider.notifier);
    final state = ref.read(castProvider);
    final airPlayConnected = state.isConnected && state.connectedDeviceId == RemoteDevice.airplay().id;

    if (active && !airPlayConnected && state.status != CastConnectionStatus.connecting) {
      // A device was picked — hand playback to the AVPlayer path; it routes to
      // the now-selected AirPlay target.
      await notifier.connect(RemoteDevice.airplay());
    } else if (!active && airPlayConnected) {
      // The user deselected AirPlay (or it dropped) — back to local playback.
      await notifier.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tint = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    final activeTint = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: UiKitView(
        viewType: 'nl.jknaapen.fladder/airplay_route_picker',
        creationParams: <String, double>{
          'tintR': tint.r,
          'tintG': tint.g,
          'tintB': tint.b,
          'tintA': tint.a,
          'activeR': activeTint.r,
          'activeG': activeTint.g,
          'activeB': activeTint.b,
          'activeA': activeTint.a,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/screens/video_player/components/airplay_route_button.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

/// Whether the cast button should be shown. True on every native platform —
/// Android/iOS get the native Google Cast SDK + DLNA, desktops get DLNA only.
/// Web has no transport (no raw UDP/SSDP, no Cast Web Sender wired up).
bool get castSupported => !kIsWeb;

/// Cast button. Lives in the player controls and in the home app bar (casting
/// can start before any playback — the app then acts as a remote control).
class CastButton extends ConsumerWidget {
  const CastButton({super.key, this.onConnected});

  /// Called when a cast session is established from this button (the player
  /// passes its minimize action so the app drops to the bottom player bar).
  final VoidCallback? onConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!castSupported) return const SizedBox.shrink();

    final connected = ref.watch(castProvider.select((value) => value.isConnected));

    return IconButton(
      tooltip: connected
          ? ref.watch(castProvider.select((value) => value.connectedDeviceName)) ?? 'Casting'
          : 'Cast',
      onPressed: () => showCastPicker(context, ref, onConnected: onConnected),
      icon: Icon(connected ? Icons.cast_connected : Icons.cast),
      color: connected ? Theme.of(context).colorScheme.primary : null,
    );
  }
}

Future<void> showCastPicker(BuildContext context, WidgetRef ref, {VoidCallback? onConnected}) async {
  final wasConnected = ref.read(castProvider).isConnected;
  // Kick off a fresh scan whenever the picker opens.
  unawaited(ref.read(castProvider.notifier).discover());
  await showModalBottomSheet(
    context: context,
    // Host on the root navigator so the sheet renders above the bottom
    // navigation and the minimized player bar.
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => const _CastPickerSheet(),
  );
  if (!wasConnected && ref.read(castProvider).isConnected && context.mounted) {
    onConnected?.call();
  }
}

class _CastPickerSheet extends ConsumerWidget {
  const _CastPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(castProvider);
    final notifier = ref.read(castProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text('Play to a device', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  // System AirPlay picker on iOS — taps open Apple's sheet so
                  // the user can route audio out to AirPlay receivers.
                  if (airPlaySupported) ...[
                    const AirPlayRouteButton(),
                    const SizedBox(width: 8),
                  ],
                  if (state.discovering)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: () => notifier.discover(),
                    ),
                ],
              ),
            ),
            if (state.isConnected)
              ListTile(
                leading: const Icon(Icons.cast_connected),
                title: Text(state.connectedDeviceName ?? 'Connected'),
                subtitle: const Text('Tap to stop casting'),
                trailing: const Icon(Icons.stop_circle_outlined),
                onTap: () async {
                  await notifier.disconnect();
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (state.status == CastConnectionStatus.connecting)
              const ListTile(
                leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text('Connecting…'),
              ),
            if (state.devices.isEmpty && !state.discovering)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Text('No devices found on your network.'),
              ),
            ...state.devices.map(
              (device) => ListTile(
                leading: Icon(switch (device.kind) {
                  RemoteDeviceKind.chromecast => Icons.cast,
                  RemoteDeviceKind.dlna => Icons.tv,
                  RemoteDeviceKind.airplay => Icons.airplay,
                }),
                title: Text(device.name),
                subtitle: Text(switch (device.kind) {
                  RemoteDeviceKind.chromecast => 'Chromecast',
                  RemoteDeviceKind.dlna => 'DLNA',
                  RemoteDeviceKind.airplay => 'AirPlay (video) — then pick your Apple TV',
                }),
                enabled: state.status != CastConnectionStatus.connecting,
                onTap: () async {
                  await notifier.connect(device);
                  if (context.mounted && ref.read(castProvider).isConnected) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

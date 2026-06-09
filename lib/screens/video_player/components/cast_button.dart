import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/cast_provider.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

/// Whether the Chromecast button should be shown. Android only for now.
bool get castSupported => !kIsWeb && Platform.isAndroid;

/// Chromecast button for the video player controls. Android only for now.
class CastButton extends ConsumerWidget {
  const CastButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!castSupported) return const SizedBox.shrink();

    final connected = ref.watch(castProvider.select((value) => value.isConnected));

    return IconButton(
      tooltip: connected
          ? ref.watch(castProvider.select((value) => value.connectedDeviceName)) ?? 'Casting'
          : 'Cast',
      onPressed: () => showCastPicker(context, ref),
      icon: Icon(connected ? Icons.cast_connected : Icons.cast),
      color: connected ? Theme.of(context).colorScheme.primary : null,
    );
  }
}

Future<void> showCastPicker(BuildContext context, WidgetRef ref) async {
  // Kick off a fresh scan whenever the picker opens.
  unawaited(ref.read(castProvider.notifier).discover());
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => const _CastPickerSheet(),
  );
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
                }),
                title: Text(device.name),
                subtitle: Text(switch (device.kind) {
                  RemoteDeviceKind.chromecast => 'Chromecast',
                  RemoteDeviceKind.dlna => 'DLNA',
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

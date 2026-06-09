import 'package:flutter_chrome_cast/entities/cast_device.dart';

import 'package:fladder/wrappers/players/dlna_discovery.dart';

enum RemoteDeviceKind { chromecast, dlna }

/// A unified "play to" target shown in the device picker, backing either a
/// Chromecast receiver or a DLNA/UPnP renderer.
class RemoteDevice {
  final RemoteDeviceKind kind;
  final String id;
  final String name;
  final GoogleCastDevice? cast;
  final DlnaRenderer? dlna;

  RemoteDevice.chromecast(GoogleCastDevice device)
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast:${device.deviceID}',
        name = device.friendlyName,
        cast = device,
        dlna = null;

  RemoteDevice.dlna(DlnaRenderer renderer)
      : kind = RemoteDeviceKind.dlna,
        id = 'dlna:${renderer.id}',
        name = renderer.name,
        cast = null,
        dlna = renderer;
}

/// Implemented by the remote [BasePlayer]s (Chromecast / DLNA) so the playback
/// wrapper can surface the connected device name regardless of protocol.
abstract class RemotePlayer {
  String get deviceName;
}

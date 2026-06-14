import 'package:flutter_chrome_cast/entities/cast_device.dart';

import 'package:fladder/wrappers/players/cast/dart_cast_discovery.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';

enum RemoteDeviceKind { chromecast, dlna, airplay }

/// A unified "play to" target shown in the device picker, backing either a
/// Chromecast receiver or a DLNA/UPnP renderer.
class RemoteDevice {
  final RemoteDeviceKind kind;
  final String id;
  final String name;
  final GoogleCastDevice? cast;
  final DlnaRenderer? dlna;

  /// Set for Chromecasts found by the pure-Dart desktop sender (mDNS + CASTV2)
  /// instead of `flutter_chrome_cast`. [kind] stays `chromecast` so the picker
  /// presents it identically; [CastNotifier.connect] branches on this field.
  final DartCastTarget? dartCast;

  RemoteDevice.chromecast(GoogleCastDevice device)
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast:${device.deviceID}',
        name = device.friendlyName,
        cast = device,
        dlna = null,
        dartCast = null;

  RemoteDevice.dartCast(DartCastTarget target)
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast-dart:${target.id}',
        name = target.name,
        cast = null,
        dlna = null,
        dartCast = target;

  /// Web: a single Chromecast entry. The Cast Web Sender owns device discovery
  /// (Chrome's own picker pops on connect), so there's nothing to enumerate.
  RemoteDevice.webCast()
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast-web',
        name = 'Chromecast',
        cast = null,
        dlna = null,
        dartCast = null;

  RemoteDevice.dlna(DlnaRenderer renderer)
      : kind = RemoteDeviceKind.dlna,
        id = 'dlna:${renderer.id}',
        name = renderer.name,
        cast = null,
        dlna = renderer,
        dartCast = null;

  /// A synthetic "play to AirPlay" target (iOS/macOS). There's no per-device
  /// discovery here — selecting it swaps in an `AVPlayer`-backed player; the
  /// user then picks the actual Apple TV via the system AirPlay picker.
  RemoteDevice.airplay()
      : kind = RemoteDeviceKind.airplay,
        id = 'airplay',
        name = 'AirPlay',
        cast = null,
        dlna = null,
        dartCast = null;
}

/// Implemented by the remote [BasePlayer]s (Chromecast / DLNA) so the playback
/// wrapper can surface the connected device name regardless of protocol.
abstract class RemotePlayer {
  String get deviceName;

  /// Whether the remote device maintains its own playback session with the
  /// Jellyfin server (registering capabilities and reporting start/progress/
  /// stop itself). When true, the phone must suppress its own session
  /// reporting or the server sees two conflicting sessions for the same item.
  ///
  /// True for the Jellyfin Cast receiver; false for the default Cast receiver
  /// and DLNA renderers, which just pull a stream — there the phone remains
  /// the only reporter, so watched-state still updates.
  bool get reportsOwnProgress;
}

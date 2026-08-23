import 'package:flutter_chrome_cast/entities/cast_device.dart';

import 'package:fladder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';

enum RemoteDeviceKind { chromecast, dlna, airplay }

/// A unified "play to" target shown in the device picker, backing a Chromecast
/// receiver (native SDK on mobile, Cast Web Sender on web), a DLNA/UPnP
/// renderer, or AirPlay.
class RemoteDevice {
  final RemoteDeviceKind kind;
  final String id;
  final String name;
  final GoogleCastDevice? cast;
  final DlnaRenderer? dlna;

  /// Set for Chromecasts found by mDNS on desktop, where there's no Cast SDK to
  /// hand us a [GoogleCastDevice].
  final CastDeviceInfo? desktopCast;

  RemoteDevice.chromecast(GoogleCastDevice device)
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast:${device.deviceID}',
        name = device.friendlyName,
        cast = device,
        desktopCast = null,
        dlna = null;

  /// Desktop: a Chromecast discovered over mDNS and driven by our own CASTV2
  /// client. Same [RemoteDeviceKind] as the SDK-backed entry, so the picker and
  /// connect flow don't need to care which platform found it.
  RemoteDevice.desktopChromecast(CastDeviceInfo device)
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast:${device.id}',
        name = device.name,
        cast = null,
        desktopCast = device,
        dlna = null;

  /// Web: a single Chromecast entry. The Cast Web Sender owns device discovery
  /// (Chrome's own picker pops on connect), so there's nothing to enumerate.
  RemoteDevice.webCast()
      : kind = RemoteDeviceKind.chromecast,
        id = 'cast-web',
        name = 'Chromecast',
        cast = null,
        desktopCast = null,
        dlna = null;

  RemoteDevice.dlna(DlnaRenderer renderer)
      : kind = RemoteDeviceKind.dlna,
        id = 'dlna:${renderer.id}',
        name = renderer.name,
        cast = null,
        desktopCast = null,
        dlna = renderer;

  /// A synthetic "play to AirPlay" target (iOS/macOS). There's no per-device
  /// discovery here — selecting it swaps in an `AVPlayer`-backed player; the
  /// user then picks the actual Apple TV via the system AirPlay picker.
  RemoteDevice.airplay()
      : kind = RemoteDeviceKind.airplay,
        id = 'airplay',
        name = 'AirPlay',
        cast = null,
        desktopCast = null,
        dlna = null;
}

/// Implemented by the remote [BasePlayer]s (Chromecast / DLNA / AirPlay) so the
/// playback wrapper can surface the connected device name regardless of
/// protocol.
abstract class RemotePlayer {
  String get deviceName;

  /// Whether the remote device maintains its own playback session with the
  /// Jellyfin server (registering capabilities and reporting start/progress/
  /// stop itself). When true, the phone must suppress its own session
  /// reporting or the server sees two conflicting sessions for the same item.
  ///
  /// True for the Jellyfin Cast receiver; false for the default Cast receiver,
  /// AirPlay and DLNA renderers, which just pull a stream — there the phone
  /// remains the only reporter, so watched-state still updates.
  bool get reportsOwnProgress;

  /// The receiver's current device volume (0–100) when it reports one, so the
  /// phone's volume keys and media-session slider can track it. Null when the
  /// device doesn't report volume.
  int? get remoteVolumeLevel => null;
}

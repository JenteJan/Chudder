import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';

final _log = Logger('Cast.mdns');

/// The Cast service type every Chromecast, Google TV and Cast-enabled speaker
/// advertises.
const _castService = '_googlecast._tcp.local';

/// A Chromecast found on the LAN by mDNS — the desktop equivalent of the SDK's
/// `GoogleCastDevice`.
class CastDeviceInfo {
  const CastDeviceInfo({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.model,
  });

  /// The device's stable Cast id (TXT `id=`), falling back to the mDNS instance
  /// name so a device with a malformed TXT record is still selectable.
  final String id;

  /// TXT `fn=` — the name the user set ("Living Room TV").
  final String name;
  final String host;
  final int port;

  /// TXT `md=` — e.g. "Chromecast Ultra". Used to tell devices apart when two
  /// share a friendly name.
  final String? model;

  @override
  bool operator ==(Object other) => other is CastDeviceInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// mDNS discovery of Cast receivers, for the platforms with no first-party Cast
/// SDK (Windows/Linux/macOS).
///
/// Unlike the SDK this does *not* filter by receiver app id — every Cast device
/// on the network is returned, and an old device that can't run the Jellyfin
/// receiver will simply fail at launch with a clear error rather than silently
/// never appearing.
class CastMdnsDiscovery {
  /// Scans for [timeout], calling [onDevice] as each receiver resolves.
  ///
  /// Resolution is per-device: a PTR gives an instance name, SRV gives host+port,
  /// TXT gives the friendly name, and A/AAAA gives the address. Devices are
  /// emitted as soon as their own records are in, so the picker fills in
  /// progressively instead of waiting out the whole window.
  static Future<List<CastDeviceInfo>> discover({
    Duration timeout = const Duration(seconds: 5),
    void Function(CastDeviceInfo device)? onDevice,
  }) async {
    final found = <String, CastDeviceInfo>{};
    // Reusing the port lets us coexist with other mDNS responders on the box
    // (Bonjour on Windows, avahi on Linux); without it binding can fail outright.
    final client = MDnsClient(
      rawDatagramSocketFactory: (dynamic host, int port,
              {bool reuseAddress = true, bool reusePort = true, int ttl = 1}) =>
          RawDatagramSocket.bind(host, port, reuseAddress: true, reusePort: false, ttl: ttl),
    );

    try {
      // The package default (`allInterfacesFactory`) includes loopback and
      // link-local adapters, and `start()` joins multicast on every interface it
      // is handed — one failure aborts the whole scan. On Windows the loopback
      // adapter rejects the join with WSAENOPROTOOPT (10042), so discovery never
      // ran at all. Restricting the set to real, routable adapters fixes it.
      await client.start(
        interfacesFactory: (type) => NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: false,
          type: type,
        ),
      );
      final deadline = Future<void>.delayed(timeout);
      final resolving = <Future<void>>[];

      final ptrSub = client.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer(_castService)).listen((ptr) {
        resolving.add(_resolve(client, ptr.domainName, found, onDevice));
      });

      await deadline;
      await ptrSub.cancel();
      // Let any in-flight SRV/TXT/A lookups finish, but never past the window.
      await Future.wait(resolving).timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <void>[],
      );
    } catch (error, stack) {
      _log.warning('mDNS discovery failed', error, stack);
    } finally {
      client.stop();
    }

    _log.info('mDNS found ${found.length} Cast device(s)');
    return found.values.toList();
  }

  static Future<void> _resolve(
    MDnsClient client,
    String instance,
    Map<String, CastDeviceInfo> found,
    void Function(CastDeviceInfo device)? onDevice,
  ) async {
    try {
      final srv = await client
          .lookup<SrvResourceRecord>(ResourceRecordQuery.service(instance))
          .first
          .timeout(const Duration(seconds: 3));

      final txt = <String, String>{};
      await for (final record in client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(instance))
          .timeout(const Duration(seconds: 3), onTimeout: (sink) => sink.close())) {
        // Each TXT record is newline-joined `key=value` pairs.
        for (final line in const LineSplitter().convert(record.text)) {
          final split = line.indexOf('=');
          if (split > 0) txt[line.substring(0, split)] = line.substring(split + 1);
        }
      }

      final address = await client
          .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target))
          .first
          .timeout(const Duration(seconds: 3));

      final id = txt['id'] ?? instance;
      if (found.containsKey(id)) return;

      final device = CastDeviceInfo(
        id: id,
        name: txt['fn']?.trim().isNotEmpty == true ? txt['fn']!.trim() : srv.target,
        host: address.address.address,
        port: srv.port,
        model: txt['md'],
      );
      found[id] = device;
      _log.info('Found Cast device "${device.name}" at ${device.host}:${device.port} (${device.model ?? 'unknown'})');
      onDevice?.call(device);
    } on TimeoutException {
      // A device that answered the PTR but not the follow-ups — skip it rather
      // than failing the whole scan.
      _log.fine('Timed out resolving $instance');
    } catch (error, stack) {
      _log.warning('Failed to resolve $instance', error, stack);
    }
  }
}

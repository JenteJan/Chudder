import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';

final _log = Logger('Cast.mdns');

/// A Chromecast discovered over mDNS by the pure-Dart desktop sender (no
/// `flutter_chrome_cast`, which is android/ios only). Carries everything the
/// CASTV2 client needs to open a control channel.
class DartCastTarget {
  final String id;
  final String name;
  final String host;
  final int port;

  const DartCastTarget({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });
}

/// Discovers Chromecast receivers via mDNS (`_googlecast._tcp`) — the same
/// browse the native Cast SDK does, reimplemented in Dart so it runs on
/// macOS/Windows/Linux where Google ships no SDK.
class DartCastDiscovery {
  static const _service = '_googlecast._tcp.local';

  static Future<List<DartCastTarget>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _log.info('mDNS Cast scan starting (timeout ${timeout.inSeconds}s)');
    final client = MDnsClient();
    final found = <String, DartCastTarget>{};
    try {
      await client.start();
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_service),
        timeout: timeout,
      )) {
        try {
          final target = await _resolve(client, ptr.domainName, timeout);
          if (target != null) found[target.id] = target;
        } catch (error) {
          _log.fine('Failed to resolve ${ptr.domainName}: $error');
        }
      }
    } catch (error, stack) {
      _log.warning('mDNS Cast discovery failed', error, stack);
    } finally {
      client.stop();
    }
    _log.info('mDNS Cast discovery found ${found.length} device(s)');
    return found.values.toList();
  }

  /// Resolves one service instance to host/port/name via its SRV, TXT and A
  /// records. Takes the first answer of each (a receiver advertises one).
  static Future<DartCastTarget?> _resolve(MDnsClient client, String domainName, Duration timeout) async {
    SrvResourceRecord? srv;
    await for (final record in client.lookup<SrvResourceRecord>(
      ResourceRecordQuery.service(domainName),
      timeout: timeout,
    )) {
      srv = record;
      break;
    }
    if (srv == null) return null;

    // TXT carries the friendly name (`fn`) and stable device id (`id`).
    String? friendlyName;
    String? deviceId;
    await for (final txt in client.lookup<TxtResourceRecord>(
      ResourceRecordQuery.text(domainName),
      timeout: timeout,
    )) {
      for (final line in txt.text.split('\n')) {
        final eq = line.indexOf('=');
        if (eq <= 0) continue;
        final key = line.substring(0, eq);
        final value = line.substring(eq + 1);
        if (key == 'fn') friendlyName = value;
        if (key == 'id') deviceId = value;
      }
      if (friendlyName != null && deviceId != null) break;
    }

    // Resolve the SRV target host to an IPv4 address for the TLS socket.
    String? host;
    await for (final ip in client.lookup<IPAddressResourceRecord>(
      ResourceRecordQuery.addressIPv4(srv.target),
      timeout: timeout,
    )) {
      host = ip.address.address;
      break;
    }
    host ??= srv.target;

    return DartCastTarget(
      id: deviceId ?? domainName,
      name: friendlyName ?? srv.target,
      host: host,
      port: srv.port,
    );
  }
}

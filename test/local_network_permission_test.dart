import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/util/local_network_permission.dart';

void main() {
  group('LocalNetworkPermission.isLocalUrl', () {
    test('accepts private IPv4 ranges', () async {
      expect(await LocalNetworkPermission.isLocalUrl('http://192.168.1.10:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://10.0.0.5:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://172.16.0.1'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://172.31.255.254'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://127.0.0.1:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://169.254.10.10'), isTrue);
    });

    test('rejects public IPv4 addresses, including the ranges next to private ones', () async {
      expect(await LocalNetworkPermission.isLocalUrl('https://8.8.8.8'), isFalse);
      expect(await LocalNetworkPermission.isLocalUrl('https://172.15.0.1'), isFalse);
      expect(await LocalNetworkPermission.isLocalUrl('https://172.32.0.1'), isFalse);
      expect(await LocalNetworkPermission.isLocalUrl('https://192.169.0.1'), isFalse);
      expect(await LocalNetworkPermission.isLocalUrl('https://11.0.0.1'), isFalse);
    });

    test('accepts unique-local and mapped IPv6, rejects global IPv6', () async {
      expect(await LocalNetworkPermission.isLocalUrl('http://[fd12:3456::1]:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://[::1]:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://[fe80::1]'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://[::ffff:192.168.1.10]'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://[2606:4700::1111]'), isFalse);
    });

    test('accepts hostnames that only exist on the local network', () async {
      expect(await LocalNetworkPermission.isLocalUrl('http://localhost:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://jellyfin.local:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://nas.lan'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl('http://media.home.arpa'), isTrue);
    });

    test('reads the host out of an address typed without a scheme', () async {
      expect(await LocalNetworkPermission.isLocalUrl('192.168.1.10:8096'), isTrue);
      expect(await LocalNetworkPermission.isLocalUrl(' JELLYFIN.LOCAL '), isTrue);
    });

    test('treats an unresolvable name as remote rather than prompting', () async {
      expect(
        await LocalNetworkPermission.isLocalUrl('http://not-a-real-host.invalid'),
        isFalse,
      );
    });

    test('handles a missing address', () async {
      expect(await LocalNetworkPermission.isLocalUrl(null), isFalse);
      expect(await LocalNetworkPermission.isLocalUrl('   '), isFalse);
    });
  });
}

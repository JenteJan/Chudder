// The server address check stops only what no server could answer to.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/server_address_check.dart';

void main() {
  test('every way a private or public server can be reached passes', () {
    const fine = [
      'jellyfin',
      'localhost',
      'localhost:8096',
      'nas.local',
      'nas.local:8096',
      'my_server.lan',
      'jellyfin.example.com',
      'jellyfin.example.com.',
      'Jellyfin.Example.COM',
      'media.example.com/jellyfin',
      'media.example.com/jellyfin/',
      'https://media.example.com',
      'HTTPS://media.example.com',
      'http://192.168.1.10:8096',
      '192.168.1.10',
      '192.168.1.10:8096/jf',
      '10.0.0.5:8920',
      '100.64.1.2',
      '[fd00::5]:8096',
      'http://[::1]:8096',
      '[fe80::1%25eth0]',
      'xn--jellyfn-9wa.example',
      'jéllyfin.example',
      '例子.测试',
      'user:pass@host.example',
      'jellyfin-1.home-lab.internal:443',
      ' jellyfin.example.com ',
      'http:8096',
    ];
    for (final address in fine) {
      expect(checkServerAddress(address), isNull, reason: address);
    }
  });

  test('what can never reach a server is caught', () {
    const broken = {
      'jellyfin example.com': ServerAddressProblem.spaces,
      'ftp://media.example.com': ServerAddressProblem.scheme,
      'smb://nas': ServerAddressProblem.scheme,
      'https:/media.example.com': ServerAddressProblem.scheme,
      'https//media.example.com': ServerAddressProblem.scheme,
      'http:media.example.com': ServerAddressProblem.scheme,
      'https://': ServerAddressProblem.malformed,
      'media.example.com:99999': ServerAddressProblem.malformed,
      'media.example.com:abc': ServerAddressProblem.malformed,
      'media,example.com': ServerAddressProblem.malformed,
      'media..example.com': ServerAddressProblem.malformed,
      '.example.com': ServerAddressProblem.malformed,
      'jelly!fin': ServerAddressProblem.malformed,
      '[not:ipv6:zz]': ServerAddressProblem.malformed,
    };
    broken.forEach((address, problem) {
      expect(checkServerAddress(address), problem, reason: address);
    });
  });

  test('nothing typed is not a problem yet', () {
    expect(checkServerAddress(''), isNull);
    expect(checkServerAddress('   '), isNull);
  });
}

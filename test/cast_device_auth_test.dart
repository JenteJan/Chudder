import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/wrappers/players/cast/desktop/cast_device_auth.dart';

// A real answer, from a Chromecast on 2026-11-25: its device certificate,
// the "Chromecast ICA 12" intermediate, the TLS certificate of that
// connection, the nonce it was challenged with and its signature (SHA-256).
final _device = base64.decode(
    'MIIDsTCCApmgAwIBAgIHR1UwVEdXQjANBgkqhkiG9w0BAQsFADB6MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5p'
    'YTEWMBQGA1UEBwwNTW91bnRhaW4gVmlldzETMBEGA1UECgwKR29vZ2xlIEluYzENMAsGA1UECwwEQ2FzdDEaMBgGA1UEAwwR'
    'Q2hyb21lY2FzdCBJQ0EgMTIwHhcNMTkwMzA1MDgwMDAwWhcNNDEwNjAxMDMwMjA0WjB9MQswCQYDVQQGEwJVUzETMBEGA1UE'
    'CAwKQ2FsaWZvcm5pYTEWMBQGA1UEBwwNTW91bnRhaW4gVmlldzETMBEGA1UECgwKR29vZ2xlIEluYzENMAsGA1UECwwEQ2Fz'
    'dDEdMBsGA1UEAwwUR1UwVEdXQiBGQThGQ0E4QzdEOUEwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC4FQf6F9ip'
    'YdovJMo3xSWtvCXsYx3fvbwxs78VtD9TyvlAFL06aubiYNVYT0xhRehnYj/oqJLg++y/bT/JA0octPgSg5CYwakw4+NqLV2l'
    '9AEUbVQTUexXNKGR20tO+QTUnUUH06iYB25PYyDxJYVlGD0plhwYwCRMfLdkcMJbVGlVbUqE9ENAzQG38jnGCUYwKc5A+zPQ'
    '96HJG01iJ22O9XCb3Waz5KH/7hLVJT8n/maLCbe3oDy6uerS0WBAnJVj2AGLNwFRcxQyiRku9HtfZEDky1SR/MEuhh2mtueH'
    'If55MD4XZQu+1GtQZZkH5HUxlRnp7Mi39SGy7Qz1xiAFAgMBAAGjOTA3MAkGA1UdEwQCMAAwCwYDVR0PBAQDAgeAMB0GA1Ud'
    'JQQWMBQGCCsGAQUFBwMCBggrBgEFBQcDATANBgkqhkiG9w0BAQsFAAOCAQEAR9PGwC04x23oUxMnA7sOqngZmWdY3tt/3QCd'
    '1g+rYPRUGPtyha00FyRp03oW0QVYONfoMkssBJ2JPu43qlMv+M1rYf3q+74hr7bHn/yvZZ3h9c5i/e+fFIQkXfH6lHZDqj8T'
    'GUfaOWSc4271/BJpMB7c9Uczd21qOz2/XYv040cr4OAQ/St2iX1xIJ/RgFbqqoKEUUPFE0DtriPW3Z+90y1JfIfd1lKEi6pd'
    'QzzgdkvYoxxhYobCOEhFb/8f6BaZglir5cT1HRICTZVw2Rc5vz3pLx46cB+ZMbhwM29Y8s3huRm8qJ4oMnMFZWRkkB8JSht4'
    'jhBw/Nhep/hHlZsZTQ==');
final _intermediate = base64.decode(
    'MIIDyzCCArOgAwIBAgICATIwDQYJKoZIhvcNAQELBQAwdTELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3JuaWExFjAU'
    'BgNVBAcMDU1vdW50YWluIFZpZXcxEzARBgNVBAoMCkdvb2dsZSBJbmMxDTALBgNVBAsMBENhc3QxFTATBgNVBAMMDENhc3Qg'
    'Um9vdCBDQTAeFw0xODAyMDIxOTQ2NTVaFw0zODAxMjgxOTQ2NTVaMHoxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxpZm9y'
    'bmlhMRYwFAYDVQQHDA1Nb3VudGFpbiBWaWV3MRMwEQYDVQQKDApHb29nbGUgSW5jMQ0wCwYDVQQLDARDYXN0MRowGAYDVQQD'
    'DBFDaHJvbWVjYXN0IElDQSAxMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKOPE0n8hU+tPmA0DpzENHfuxeDI'
    'H2XFRB25XaYzG/eVYs8LdOE87QU4DC522WXQXq4oZUO97YMZZFgsWl/nLf2XYoB1/QhWPIEyPYiApq8A+nhbWMJkdNlvCov4'
    '9PHkKGQ4qLyf5sU5vvLtfBCHC4sBTz4Uwd+oMoZdoTrTEfEEAFuOZ4GFLL3difALJ3+QLp3Ac4ZS/c4QWKSa1gi+spdAgT48'
    'Hv/1pIGC2NT5jHAQGo3gXzOk3e7xKa1HyE8aYQTvMVo+mzsqPkO0h+RBSl/y4iZve1OOCommWC5yC0FafhpK5kmd2hcximNR'
    'vCtH8pFpa6jV2uTdQXYKGp1DLicCAwEAAaNgMF4wDwYDVR0TBAgwBgEB/wIBADAdBgNVHQ4EFgQU56PENciX9/vtBXU6EvWa'
    'WMiY9qcwHwYDVR0jBBgwFoAUfJoefd95VLzXzF7KmYZFeWV0KBkwCwYDVR0PBAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQBf'
    'F0j6+pfltjyG0TSpGDaBub9RGIyOaXwDvQuHvnUs/RWG0u0VyQigU30klMQT2Ilzfl+8hqI7ao6lN/RVglWMsCubVp4J4rZH'
    'X2lQaDJi5+2q2sqHBVD7hH0pqbBl85p4Dkr5s4secVjMdLAcYECUqLseEb4xd1jiHL6cuXn7JnUazI3YHMIuu8WOnyD/f+b7'
    'gEVaR0kjFzOBWm/Yb0ErEdGgDx6T+KFxf6VZxeXunV9nEUZkfVt3pfF137sXax5ufk6OzzgwaTODTqdmGAHmtTTCEqaa28Ei'
    '4XvIf31z987gJlZoZMygL3pxk4GKS60wTFUkGoyKoDcWUMLn0Pqy');
final _peer = base64.decode(
    'MIIC2jCCAcKgAwIBAgIEGHWAvjANBgkqhkiG9w0BAQsFADAvMS0wKwYDVQQDDCQ2YzY3ODc5NS1kMGZkLTY0NjUtYWRkYi01'
    'YTI1MjhlZjBlNDIwHhcNMjYxMTI0MjIxNzI2WhcNMjYxMTI2MjIxNzI2WjAvMS0wKwYDVQQDDCQ2YzY3ODc5NS1kMGZkLTY0'
    'NjUtYWRkYi01YTI1MjhlZjBlNDIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDOseiCU6saZLHy207uPzbER5EJ'
    'WHfnTMekvWjW32SopXs95vZ5l3Qr57yDRoiS5ye3bbQYVhxXGPUdmWMYyVMj9AyAlKV9suYFcILpxIn0nUduuR6IIE26aq+L'
    'fEJRdbuyXMLtaAzv8ti/UvEzlj+ovkMyAZt/sPpqrdaWeLJ+mdICzCha6IfGERk0Hs0IydTwUrCH/j+tmxC6oSh+lVMQpgAH'
    'FrSmdoWNDkskGYA7sk0MScIjgyK4ME8c45bAngod4T3hMAvkZWmybBBCGxI/XhmeLwh161YbhVKJvJBUg0QdX4jAtrO7tLdO'
    'xZDJHjnLB7ClBqKOhWtqahXBaRZ7AgMBAAEwDQYJKoZIhvcNAQELBQADggEBAAU78R98MZYLYpF6l7vZXbF3mFmd3SAZJ2Vq'
    'McuSwWE5u0cInUBmI3UsjkjrCDn6JHx/SEivk+rSmH+oGrP11pxTtvAlleFgmxiC8QFMP8j4MpMJieWzf/vjlAtfbcJ1ouop'
    'tHg8NyK+LEn9E1eqQTmQOO5IJA3HtnMOONYuvURBR52I5xMPe5HFLNB6bs+Oc5ah7pizrHCB5v/lQeWxC6L1d7TD2cp6Gp5c'
    'mK0QMQybenTL7Fkgo+VJOeYri2qz6POdOMEX0TMbM4ZqxeqO45A19I6wpQoDCk2Wl+mnW/kdjVJNg9Zh6zKTHBqsT47xOoCc'
    'gZLn4zqBY1ydMRg6Alk=');
final _nonce = base64.decode(
    '0dDX2S6MJw4e9T9F/eT3Ig==');
final _signature = base64.decode(
    'PW7lMBGXl2AfEXgSLNcwDVZRgUN8bIcONDA+s+9Gs3irzeSiVmY/JsoBX6uubpqhA+p/gvCqAMpEo7FGACqT/COKBo8ft8SV'
    'fme207Amtr28vrO42zqkECa4lhGi9eYKOeDhXq4i3kJUwvHBvCBTq3OTzo1AxAIhiiPfMAvJd08ZFdUCkldjZCuRbJBNJ7kD'
    'EpmYVS7cSUCLEhYeVdDMfcNezlIypMyMpwBEqUVsVxgFButtm95oU2bHnkYRX8KQyHFA40pSLboZ+zuCwXNpteVjOtsVH5/R'
    '8nFTBSeo+3/w65LDLQ8CWQjn9f5kYMuEQwwOcWbos6C2NmzpfenBew==');

final _when = DateTime.utc(2026, 11, 25);

Uint8List _varint(int value) {
  final out = <int>[];
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return Uint8List.fromList(out);
}

List<int> _field(int number, List<int> bytes) => [..._varint((number << 3) | 2), ..._varint(bytes.length), ...bytes];

/// A DeviceAuthMessage carrying an AuthResponse.
Uint8List _reply({
  List<int>? signature,
  List<int>? device,
  List<List<int>>? intermediates,
  List<int>? nonce,
}) {
  final response = [
    ..._field(1, signature ?? _signature),
    ..._field(2, device ?? _device),
    for (final certificate in intermediates ?? [_intermediate]) ..._field(3, certificate),
    ..._varint(4 << 3), ..._varint(1), // RSASSA_PKCS1v15
    ..._field(5, nonce ?? _nonce),
    ..._varint(6 << 3), ..._varint(1), // SHA256
  ];
  return Uint8List.fromList(_field(2, response));
}

void _verify(Uint8List reply, {Uint8List? peer, Uint8List? nonce, DateTime? now}) =>
    verifyAuthReply(reply, nonce: nonce ?? _nonce, peerCertificateDer: peer ?? _peer, now: now ?? _when);

Matcher get _refused => throwsA(isA<CastDeviceAuthException>());

void main() {
  test('a genuine Chromecast is accepted', () {
    expect(() => _verify(_reply()), returnsNormally);
  });

  test('an answer for another connection is refused, so a fake cannot relay a real one', () {
    final otherPeer = Uint8List.fromList(_peer)..[_peer.length - 40] ^= 0x01;
    expect(() => _verify(_reply(), peer: otherPeer), _refused);
  });

  test('an answer to another challenge is refused', () {
    final otherNonce = Uint8List.fromList(_nonce)..[0] ^= 0x01;
    expect(() => _verify(_reply(nonce: otherNonce), nonce: otherNonce), _refused);
    expect(() => _verify(_reply(), nonce: otherNonce), _refused);
  });

  test('a tampered signature is refused', () {
    final signature = Uint8List.fromList(_signature)..[10] ^= 0x01;
    expect(() => _verify(_reply(signature: signature)), _refused);
  });

  test('a device certificate that does not lead to Google\'s root is refused', () {
    expect(() => _verify(_reply(intermediates: [])), _refused);
  });

  test('a device certificate changed after Google signed it is refused', () {
    final device = Uint8List.fromList(_device)..[300] ^= 0x01;
    expect(() => _verify(_reply(device: device)), _refused);
  });

  test('an expired chain is refused', () {
    expect(() => _verify(_reply(), now: DateTime.utc(2045)), _refused);
  });

  test('an error answer or garbage is refused', () {
    expect(() => _verify(Uint8List.fromList(_field(3, [..._varint(1 << 3), 0]))), _refused);
    expect(() => _verify(Uint8List.fromList([0xFF, 0xFF])), _refused);
  });

  test('the challenge asks for SHA-256 with the nonce', () {
    final inner = [..._varint(1 << 3), 1, ..._field(2, _nonce), ..._varint(3 << 3), 1];
    expect(buildAuthChallenge(_nonce), _field(1, inner));
  });
}

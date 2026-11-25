import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// Cast device authentication, as Chrome and the Cast SDKs do it.
///
/// A Chromecast's TLS certificate is self-signed, so the connection alone
/// proves nothing: anything on the network can call itself "Living Room TV"
/// and would be handed a Jellyfin session. After connecting, the sender sends
/// a random nonce; a genuine device signs the nonce plus the TLS certificate
/// of this very connection with its device key, and sends that key's
/// certificate chain, which leads to one of Google's Cast roots. Binding the
/// TLS certificate in means a fake device can't pass a real one's answer on.
///
/// Only what this needs is implemented: DER reading, X.509 fields, and
/// RSASSA-PKCS1-v1_5 with SHA-1 or SHA-256, which every Cast certificate uses.

const deviceAuthNamespace = 'urn:x-cast:com.google.cast.tp.deviceauth';

/// Why a device failed authentication.
class CastDeviceAuthException implements Exception {
  const CastDeviceAuthException(this.reason);
  final String reason;

  @override
  String toString() => 'Not a genuine Cast device: $reason';
}

/// The challenge sent to the device: a `DeviceAuthMessage` with an
/// `AuthChallenge` asking for RSASSA-PKCS1-v1_5 over SHA-256 of [nonce].
Uint8List buildAuthChallenge(Uint8List nonce) {
  final challenge = BytesBuilder()
    ..add(_varintField(1, 1)) // signature_algorithm: RSASSA_PKCS1v15
    ..add(_bytesField(2, nonce)) // sender_nonce
    ..add(_varintField(3, 1)); // hash_algorithm: SHA256
  return _bytesField(1, challenge.toBytes()); // DeviceAuthMessage.challenge
}

/// Random bytes for [buildAuthChallenge].
Uint8List newAuthNonce() {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
}

/// Checks the device's reply to [buildAuthChallenge] with [nonce], for the
/// connection whose TLS certificate is [peerCertificateDer]. Throws a
/// [CastDeviceAuthException] unless the device is genuine.
void verifyAuthReply(
  Uint8List reply, {
  required Uint8List nonce,
  required Uint8List peerCertificateDer,
  DateTime? now,
  List<Uint8List>? roots,
}) {
  final message = _protoFields(reply);
  final error = message.firstWhereOrNull((field) => field.number == 3);
  if (error != null) throw const CastDeviceAuthException('the device answered with an error');
  final responseBytes = message.firstWhereOrNull((field) => field.number == 2)?.bytes;
  if (responseBytes == null) throw const CastDeviceAuthException('no answer to the challenge');

  Uint8List? signature;
  Uint8List? deviceCertificate;
  Uint8List? echoedNonce;
  var hashAlgorithm = 0; // SHA1, the protocol's default
  final intermediates = <Uint8List>[];
  for (final field in _protoFields(responseBytes)) {
    switch (field.number) {
      case 1:
        signature = field.bytes;
      case 2:
        deviceCertificate = field.bytes;
      case 3:
        intermediates.add(field.bytes!);
      case 5:
        echoedNonce = field.bytes;
      case 6:
        hashAlgorithm = field.value ?? 0;
    }
  }
  if (signature == null || deviceCertificate == null) {
    throw const CastDeviceAuthException('the answer has no signature or certificate');
  }
  if (echoedNonce != null && !const ListEquality<int>().equals(echoedNonce, nonce)) {
    throw const CastDeviceAuthException('the answer is for another challenge');
  }

  final device = _Certificate.parse(deviceCertificate);
  _verifyChain(device, intermediates.map(_Certificate.parse).toList(), now ?? DateTime.now(),
      (roots ?? castRootCertificates).map(_Certificate.parse).toList());

  final signed = Uint8List.fromList([...nonce, ...peerCertificateDer]);
  if (!device.key.verify(signed, signature, hashAlgorithm == 1 ? _Hash.sha256 : _Hash.sha1)) {
    throw const CastDeviceAuthException('the signature does not match this connection');
  }
}

void _verifyChain(_Certificate leaf, List<_Certificate> intermediates, DateTime now, List<_Certificate> roots) {
  var current = leaf;
  for (var depth = 0; depth < 5; depth++) {
    if (now.isBefore(current.notBefore) || now.isAfter(current.notAfter)) {
      throw const CastDeviceAuthException('a certificate in its chain is out of date');
    }
    final root = roots.firstWhereOrNull((candidate) => _sameName(candidate.subject, current.issuer));
    final issuer = root ?? intermediates.firstWhereOrNull((candidate) => _sameName(candidate.subject, current.issuer));
    if (issuer == null) throw const CastDeviceAuthException('its certificate does not lead to Google\'s Cast root');
    if (!issuer.key.verify(current.tbs, current.signature, current.signatureHash)) {
      throw const CastDeviceAuthException('a certificate in its chain is not signed by its issuer');
    }
    if (root != null) return;
    current = issuer;
  }
  throw const CastDeviceAuthException('its certificate chain is too long');
}

bool _sameName(Uint8List a, Uint8List b) => const ListEquality<int>().equals(a, b);

// --- Protobuf (the two wire types the auth messages use) ---------------------

class _ProtoField {
  _ProtoField(this.number, {this.value, this.bytes});
  final int number;
  final int? value;
  final Uint8List? bytes;
}

List<_ProtoField> _protoFields(Uint8List data) {
  final fields = <_ProtoField>[];
  var offset = 0;
  int readVarint() {
    var result = 0, shift = 0;
    while (true) {
      if (offset >= data.length) throw const CastDeviceAuthException('a malformed answer');
      final byte = data[offset++];
      result |= (byte & 0x7F) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
    }
  }

  while (offset < data.length) {
    final tag = readVarint();
    switch (tag & 7) {
      case 0:
        fields.add(_ProtoField(tag >> 3, value: readVarint()));
      case 2:
        final length = readVarint();
        if (offset + length > data.length) throw const CastDeviceAuthException('a malformed answer');
        fields.add(_ProtoField(tag >> 3, bytes: Uint8List.sublistView(data, offset, offset + length)));
        offset += length;
      default:
        throw const CastDeviceAuthException('a malformed answer');
    }
  }
  return fields;
}

Uint8List _varint(int value) {
  final out = BytesBuilder();
  var v = value;
  while (v >= 0x80) {
    out.addByte((v & 0x7F) | 0x80);
    v >>= 7;
  }
  out.addByte(v);
  return out.toBytes();
}

Uint8List _varintField(int number, int value) => Uint8List.fromList([..._varint(number << 3), ..._varint(value)]);

Uint8List _bytesField(int number, Uint8List bytes) =>
    Uint8List.fromList([..._varint((number << 3) | 2), ..._varint(bytes.length), ...bytes]);

// --- DER and X.509 -----------------------------------------------------------

class _Der {
  _Der(this.tag, this.content, this.whole);
  final int tag;
  final Uint8List content;

  /// Header and content, as signed.
  final Uint8List whole;

  List<_Der> get children {
    final out = <_Der>[];
    var offset = 0;
    while (offset < content.length) {
      final (element, next) = _Der.read(content, offset);
      out.add(element);
      offset = next;
    }
    return out;
  }

  static (_Der, int) read(Uint8List data, int offset) {
    if (offset + 2 > data.length) throw const CastDeviceAuthException('a malformed certificate');
    final start = offset;
    final tag = data[offset++];
    var length = data[offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4) throw const CastDeviceAuthException('a malformed certificate');
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[offset++];
      }
    }
    if (offset + length > data.length) throw const CastDeviceAuthException('a malformed certificate');
    return (
      _Der(tag, Uint8List.sublistView(data, offset, offset + length), Uint8List.sublistView(data, start, offset + length)),
      offset + length,
    );
  }
}

enum _Hash { sha1, sha256 }

// sha1WithRSAEncryption and sha256WithRSAEncryption.
const _sha1WithRsa = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x05];
const _sha256WithRsa = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b];

class _Certificate {
  _Certificate({
    required this.tbs,
    required this.signature,
    required this.signatureHash,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.key,
  });

  final Uint8List tbs;
  final Uint8List signature;
  final _Hash signatureHash;
  final Uint8List issuer;
  final Uint8List subject;
  final DateTime notBefore;
  final DateTime notAfter;
  final _RsaKey key;

  static _Certificate parse(Uint8List der) {
    try {
      final (certificate, _) = _Der.read(der, 0);
      final [tbs, algorithm, signatureBits, ...] = certificate.children;
      var fields = tbs.children;
      if (fields.first.tag == 0xA0) fields = fields.sublist(1); // explicit version
      final [_, _, issuer, validity, subject, keyInfo, ...] = fields;
      final [notBefore, notAfter, ...] = validity.children;
      return _Certificate(
        tbs: tbs.whole,
        signature: Uint8List.sublistView(signatureBits.content, 1), // skip the unused-bits byte
        signatureHash: _hashOf(algorithm.children.first.content),
        issuer: issuer.whole,
        subject: subject.whole,
        notBefore: _time(notBefore),
        notAfter: _time(notAfter),
        key: _RsaKey.parse(keyInfo),
      );
    } on CastDeviceAuthException {
      rethrow;
    } catch (_) {
      throw const CastDeviceAuthException('a malformed certificate');
    }
  }

  static _Hash _hashOf(Uint8List oid) {
    if (const ListEquality<int>().equals(oid, _sha256WithRsa)) return _Hash.sha256;
    if (const ListEquality<int>().equals(oid, _sha1WithRsa)) return _Hash.sha1;
    throw const CastDeviceAuthException('a certificate signed in an unknown way');
  }

  /// UTCTime (YYMMDDhhmmssZ) or GeneralizedTime (YYYYMMDDhhmmssZ).
  static DateTime _time(_Der element) {
    final text = ascii.decode(element.content);
    final full = element.tag == 0x17 ? '${int.parse(text.substring(0, 2)) < 50 ? '20' : '19'}$text' : text;
    return DateTime.utc(
      int.parse(full.substring(0, 4)),
      int.parse(full.substring(4, 6)),
      int.parse(full.substring(6, 8)),
      int.parse(full.substring(8, 10)),
      int.parse(full.substring(10, 12)),
      int.parse(full.substring(12, 14)),
    );
  }
}

class _RsaKey {
  _RsaKey(this.modulus, this.exponent);
  final BigInt modulus;
  final BigInt exponent;

  /// From a SubjectPublicKeyInfo holding an RSAPublicKey.
  static _RsaKey parse(_Der keyInfo) {
    final [_, bits, ...] = keyInfo.children;
    final (rsaKey, _) = _Der.read(Uint8List.sublistView(bits.content, 1), 0);
    final [modulus, exponent, ...] = rsaKey.children;
    return _RsaKey(_unsigned(modulus.content), _unsigned(exponent.content));
  }

  int get _length => (modulus.bitLength + 7) ~/ 8;

  /// RSASSA-PKCS1-v1_5: the signature, raised to the exponent, must be exactly
  /// the padded DigestInfo of [message].
  bool verify(Uint8List message, Uint8List signature, _Hash hash) {
    if (signature.length != _length) return false;
    final s = _unsigned(signature);
    if (s >= modulus) return false;
    final encoded = _bytes(s.modPow(exponent, modulus), _length);
    final digestInfo = switch (hash) {
      _Hash.sha1 => [..._sha1DigestInfo, ...sha1.convert(message).bytes],
      _Hash.sha256 => [..._sha256DigestInfo, ...sha256.convert(message).bytes],
    };
    final padding = _length - digestInfo.length - 3;
    if (padding < 8) return false;
    final expected = [0x00, 0x01, ...List.filled(padding, 0xFF), 0x00, ...digestInfo];
    return const ListEquality<int>().equals(encoded, expected);
  }

  static const _sha1DigestInfo = [0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14];
  static const _sha256DigestInfo = [
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, //
    0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];

  static BigInt _unsigned(Uint8List bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }

  static List<int> _bytes(BigInt value, int length) {
    final out = List<int>.filled(length, 0);
    var v = value;
    for (var i = length - 1; i >= 0 && v > BigInt.zero; i--) {
      out[i] = (v & BigInt.from(0xFF)).toInt();
      v >>= 8;
    }
    return out;
  }
}

/// Google's Cast roots, from Chromium's
/// components/media_router/common/providers/cast/certificate: "Cast Root CA"
/// (2014-2034) and the older "Eureka Root CA" (2012-2032).
final List<Uint8List> castRootCertificates = [
  base64.decode(_castRootCa),
  base64.decode(_eurekaRootCa),
];

const _castRootCa = 
    'MIIDxTCCAq2gAwIBAgIBAjANBgkqhkiG9w0BAQUFADB1MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQG'
    'A1UEBwwNTW91bnRhaW4gVmlldzETMBEGA1UECgwKR29vZ2xlIEluYzENMAsGA1UECwwEQ2FzdDEVMBMGA1UEAwwMQ2FzdCBS'
    'b290IENBMB4XDTE0MDQwMjE3MzQyNloXDTM0MDMyODE3MzQyNlowdTELMAkGA1UEBhMCVVMxEzARBgNVBAgMCkNhbGlmb3Ju'
    'aWExFjAUBgNVBAcMDU1vdW50YWluIFZpZXcxEzARBgNVBAoMCkdvb2dsZSBJbmMxDTALBgNVBAsMBENhc3QxFTATBgNVBAMM'
    'DENhc3QgUm9vdCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALrZZZ3aOdPBd/bU0K6PWAhoOUqV7XDP/XkI'
    'qarl6binLaBnR4qeyc9wswWHaRHscJiXw+bDw+u9xrA9/E/BXjif2s9zMAZbeTfBXoyHR5SaQZIq1pXEcVwnXQixgMaSvRvj'
    'QZeh7HWfVZ4+n48cx2VkB9OzlqEEn5HE3gp7bNnIwHgxoBlCqeiD48788c7CLiRGlQkZysBGsuUButdP87/2aa2ZBPqgBzkO'
    '5t9RRwfA5KlcS5TFL7OgMH/nlWuyrzIN8YzVbct7R6cIq8sno03PSlrxBdH4YsUQKnRpquZLlvub2GPkWGbTrYpu/3te+aVW'
    'Hi2CMVvw4iTmQUofrhMCAwEAAaNgMF4wDwYDVR0TBAgwBgEB/wIBAjAdBgNVHQ4EFgQUfJoefd95VLzXzF7KmYZFeWV0KBkw'
    'HwYDVR0jBBgwFoAUfJoefd95VLzXzF7KmYZFeWV0KBkwCwYDVR0PBAQDAgEGMA0GCSqGSIb3DQEBBQUAA4IBAQCA9Fr7PSgZ'
    'USDX1PsSl0pl8lg1kncwavHXtlEaf5rNx3sDQq1VagCv8OEGwr1reHXb/kERU0o5u5o6xlk0Lywz47LWXH/deOtxWznag5DF'
    'MeI/I+/a6ystd17ew0PSyWtZgsrV7fqhZFvL8Q0aYuGc6KcYcPBfF5b47Ybbrh3gzz5dLu4WbZUrPP2X8wVaJGhNObb45Fi6'
    '9eAmeFHFW11OCeVsR4t6Wi6JU+bMNlsmPPhyQwKC0ivN8NOj7BM+UtWDPQfcHUNlejMCAaPOt9ZgUTsJwiOKMv6YGWBik4XN'
    'NEbb1SMPedp3ACoCbYNYzgN3NeGjIJPCSqKkRhx1LB9N';
const _eurekaRootCa = 
    'MIIDwzCCAqugAwIBAgIBATANBgkqhkiG9w0BAQUFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECAwKQ2FsaWZvcm5pYTEWMBQG'
    'A1UEBwwNTW91bnRhaW4gVmlldzETMBEGA1UECgwKR29vZ2xlIEluYzESMBAGA1UECwwJR29vZ2xlIFRWMRcwFQYDVQQDDA5F'
    'dXJla2EgUm9vdCBDQTAeFw0xMjEyMTcyMjM5MzNaFw0zMjEyMTIyMjM5MzNaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApD'
    'YWxpZm9ybmlhMRYwFAYDVQQHDA1Nb3VudGFpbiBWaWV3MRMwEQYDVQQKDApHb29nbGUgSW5jMRIwEAYDVQQLDAlHb29nbGUg'
    'VFYxFzAVBgNVBAMMDkV1cmVrYSBSb290IENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuRHQ6hLcMuHfXDNr'
    'GXMdnZ7QOXa/pYQJpv1ubencjzZO6YgCvZ/06ET9TPWaAlZqRypjbFhFzHxmJNx5ecMqpLKLoPeitc0Gftu+7AyG8g0kYHSE'
    'yikjhALYp+078ewmR1TjsS3mZA/2csXpmFIXwPzyLCDIQPhHyTKeO5exi/WYJHBjZhnBUugEBT1fjbzYS693mG8feNG2UCdN'
    '5OwUaWcfWK+poBEmPJQyB3/X6Wkfrj9PY4qPidbyGXhcIY6xtlfYwOHufW7d8ToKavG6//mDL9y1pCAXYzbvyGIZzFbOsuox'
    'iUt4WMG/AxOZ4BLyiKqblNrddnkXHjTRCsQHRQIDAQABo1AwTjAdBgNVHQ4EFgQURE4qR1jYuUiR9k/OdKkdMpqNjekwHwYD'
    'VR0jBBgwFoAURE4qR1jYuUiR9k/OdKkdMpqNjekwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQUFAAOCAQEAP8gmoG5cBUB5'
    'oZipM95odIXurrccM1mwEd6f9E/T61EJfUd+blGF9FTNg5glsbqwV+yT2xLi7FFJepZzm8iWbYWM0+E8+jLiWAx3bYcMNAGq'
    'MKl24MDn214b6RAwpOAJSSa5WM1aB+VQdd6aO/ZTfrFTXkUnTxfjCDOyUAq79PwllyneQXUw+nc4qmWKc0/qEXvrfBdgJw68'
    'PnZS2IvtGvjrN7sR/a5wFwr+4K0Gsx9pinIEwsAzC9YvY0wzERS4YjaIxQNlARmj7wC7bw6S/zQcodYx0Fxen5l9x8q9fHIL'
    '9Fylfm4EqNKZLFEBFP6iSPB+voQNtNPi8w593ov1Mw==';

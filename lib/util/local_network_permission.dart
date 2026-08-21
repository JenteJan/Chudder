import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'package:logging/logging.dart';

final _log = Logger('LocalNetwork');

/// Android 17 (targetSdk 37+) puts *all* local-network sockets behind the
/// runtime permission `ACCESS_LOCAL_NETWORK`, not just discovery: until it's
/// granted, every connection to a LAN address is dropped. A Jellyfin server on
/// the home network then looks unreachable — the library never loads and
/// nothing explains why, because the system shows no prompt of its own.
///
/// So the app has to ask, and it has to ask *before* the first request that
/// leaves for a local address ([ensureForUrl]) rather than only when the user
/// opens the cast picker ([ensure]).
///
/// Everywhere else — other Android versions, iOS, desktop, web — the gate
/// doesn't exist and every call here resolves to `true` without touching the
/// platform channel.
class LocalNetworkPermission {
  LocalNetworkPermission._();

  static const _channel = MethodChannel('nl.jknaapen.fladder/local_network');

  /// Whether this device+build enforces the permission at all. Asked once; the
  /// answer can't change while the app runs.
  static bool? _required;

  /// Only ever cached once granted — a denial can be undone from system
  /// settings, so that side is re-checked natively instead of remembered.
  static bool _granted = false;

  /// Set after a denial so a failing server doesn't re-prompt on every retry.
  /// The system stops showing the dialog after two denials anyway, but without
  /// this each request would still round-trip to native.
  static bool _deniedThisSession = false;

  /// In-flight request, so the concurrent probes the login screen fires share
  /// one dialog instead of racing (native rejects a second request outright).
  static Future<bool>? _pending;

  /// Locality verdict per host, since it costs a DNS lookup to reach.
  static final Map<String, bool> _hostIsLocal = {};

  /// Requests the permission if this platform needs it. For callers that are
  /// about to touch the local network no matter what the server address is —
  /// mDNS/SSDP discovery.
  static Future<bool> ensure() => _ensureGranted(prompt: true);

  /// Requests the permission only when [url] actually points at the local
  /// network. A server reached over the internet doesn't need it, and asking
  /// anyway would be a dialog the user can't make sense of.
  static Future<bool> ensureForUrl(String? url) async {
    if (!await _isRequired) return true;
    if (_granted) return true;
    if (!await isLocalUrl(url)) return true;
    return _ensureGranted(prompt: true);
  }

  /// Whether local-network access is currently available — false only when the
  /// gate applies and the permission isn't granted. Never prompts.
  static Future<bool> get isGranted => _ensureGranted(prompt: false);

  static Future<bool> get _isRequired async {
    if (kIsWeb || !Platform.isAndroid) return false;
    // A channel that can't answer (no activity attached, a background isolate)
    // reads as "no gate here", so a broken bridge never blocks traffic that
    // would have worked.
    return _required ??= (await _invoke('required')) ?? false;
  }

  static Future<bool> _ensureGranted({required bool prompt}) async {
    if (!await _isRequired) return true;
    if (_granted) return true;

    // Re-ask native rather than trusting [_deniedThisSession]: the user may
    // have granted it from system settings since we last looked.
    if (await _invoke('granted') ?? false) {
      _granted = true;
      return true;
    }
    if (!prompt || _deniedThisSession) return false;

    return _pending ??= _request().whenComplete(() => _pending = null);
  }

  static Future<bool> _request() async {
    final granted = await _invoke('request');
    if (granted == null) return false;
    _granted = granted;
    _deniedThisSession = !granted;
    if (!granted) {
      _log.warning('ACCESS_LOCAL_NETWORK denied — nothing on the local network is reachable');
    }
    return granted;
  }

  /// Null when the platform side couldn't answer, so a channel problem stays
  /// distinguishable from a real "no".
  static Future<bool?> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method);
    } on PlatformException catch (error, stack) {
      _log.warning('Local network permission call "$method" failed', error, stack);
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Whether [url] points at an address on this network — a literal private
  /// IP, a name that only resolves locally, or one a LAN resolver maps to a
  /// private address (split-horizon DNS, so the same hostname works from
  /// either side).
  static Future<bool> isLocalUrl(String? url) async {
    final host = _hostOf(url);
    if (host == null) return false;
    final cached = _hostIsLocal[host];
    if (cached != null) return cached;
    return _hostIsLocal[host] = await _isLocalHost(host);
  }

  static String? _hostOf(String? url) {
    final trimmed = url?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    // Without a scheme `Uri.parse` reads the whole thing as a path, so a bare
    // "192.168.1.10:8096" would come back with an empty host.
    final parsed = Uri.tryParse(trimmed.contains('://') ? trimmed : 'http://$trimmed');
    final host = parsed?.host;
    return host == null || host.isEmpty ? null : host.toLowerCase();
  }

  static Future<bool> _isLocalHost(String host) async {
    if (host == 'localhost') return true;
    // `.local` resolves over mDNS, which is local-network traffic itself, so
    // the lookup below would fail before it could tell us anything.
    if (_localSuffixes.any(host.endsWith)) return true;

    final literal = InternetAddress.tryParse(host);
    if (literal != null) return _isPrivateAddress(literal);

    try {
      // DNS itself isn't gated, so this still answers while the permission is
      // missing — including for names a LAN resolver maps to private IPs.
      final addresses = await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));
      return addresses.any(_isPrivateAddress);
    } catch (error) {
      // Unresolvable: assume remote rather than prompting for a host we can't
      // place — a name that only exists on the LAN would have resolved.
      _log.fine('Could not resolve $host to decide local-network use: $error');
      return false;
    }
  }

  static const _localSuffixes = ['.local', '.lan', '.home', '.home.arpa', '.internal'];

  static bool _isPrivateAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4) return _isPrivateIPv4(bytes);
    if (bytes.length != 16) return false;
    // IPv4-mapped (::ffff:a.b.c.d) carries a v4 address in the last four bytes.
    final mapped = bytes.take(10).every((byte) => byte == 0) && bytes[10] == 0xFF && bytes[11] == 0xFF;
    if (mapped) return _isPrivateIPv4(bytes.sublist(12));
    // Unique local addresses, fc00::/7.
    return bytes[0] & 0xFE == 0xFC;
  }

  static bool _isPrivateIPv4(List<int> bytes) {
    if (bytes.length != 4) return false;
    return switch (bytes[0]) {
      10 => true,
      127 => true,
      169 => bytes[1] == 254,
      172 => bytes[1] >= 16 && bytes[1] <= 31,
      192 => bytes[1] == 168,
      _ => false,
    };
  }
}

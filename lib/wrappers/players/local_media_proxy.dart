import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';

final _log = Logger('Cast.proxy');

/// DLNA content feature flags advertised to the renderer. `DLNA.ORG_OP=01`
/// signals byte-range seek support (so the TV shows a working seek bar); the
/// FLAGS mark the content as seekable streaming. Sent both in the DIDL
/// protocolInfo and as the `contentFeatures.dlna.org` HTTP header.
const dlnaOrgContentFeatures = 'DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000000000000000000000000000';

/// A tiny on-device HTTP server that re-serves a (typically HTTPS) Jellyfin
/// stream to a DLNA renderer over plain HTTP on the phone's LAN address.
///
/// DLNA renderers such as webOS/Tizen TVs frequently can't fetch an HTTPS URL
/// (no TLS in the renderer, won't follow redirects). Proxying through the phone
/// means casting works with zero server configuration: the TV always gets a
/// plain-http, directly-reachable, range-capable URL.
class LocalMediaProxy {
  HttpServer? _server;
  String? _upstreamUrl;
  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  /// Content type discovered from the upstream (used for DIDL metadata).
  String contentType = 'video/mp4';
  int _token = 0;

  bool get isRunning => _server != null;

  /// Points the proxy at [upstreamUrl] (starting the server if needed) and
  /// returns a plain-http URL on the phone's LAN address for the renderer to
  /// fetch. Returns null if no server/LAN address is available.
  ///
  /// [rendererHost] is the renderer's address; on a multi-homed machine
  /// (Ethernet + Wi-Fi + VPN) the proxy URL must use the local IP on the *same*
  /// subnet, or the renderer can't reach it ("device no longer connected").
  Future<String?> start(String upstreamUrl, {String? rendererHost}) async {
    _upstreamUrl = upstreamUrl;
    await _probe(upstreamUrl);
    _server ??= await _bind();
    final server = _server;
    if (server == null) return null;
    final ip = await _localIp(rendererHost: rendererHost);
    if (ip == null) {
      _log.warning('No LAN address found — cannot build a proxy URL for the renderer');
      return null;
    }
    _token++;
    final url = 'http://$ip:${server.port}/media${_extensionForType(contentType)}?t=$_token';
    _log.info('Proxy URL for renderer: $url (upstream type $contentType)');
    return url;
  }

  /// Learns the upstream content type (and warms the connection) via a HEAD.
  Future<void> _probe(String url) async {
    try {
      final request = await _client.openUrl('HEAD', Uri.parse(url));
      final response = await request.close();
      final type = response.headers.contentType?.value;
      if (type != null && type.isNotEmpty) contentType = type;
      await response.drain();
    } catch (error) {
      _log.fine('Upstream HEAD probe failed (continuing): $error');
    }
  }

  Future<HttpServer?> _bind() async {
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      server.listen(_handle, onError: (error) => _log.warning('Proxy server error: $error'));
      _log.info('Local media proxy listening on port ${server.port}');
      return server;
    } catch (error) {
      _log.severe('Failed to start local media proxy: $error');
      return null;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final upstream = _upstreamUrl;
    final response = request.response;
    if (upstream == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final range = request.headers.value(HttpHeaders.rangeHeader);
    _log.fine('${request.method} from ${request.connectionInfo?.remoteAddress.address} range=${range ?? '-'}');

    try {
      final upstreamReq = await _client.openUrl(request.method, Uri.parse(upstream));
      if (range != null) upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
      final upstreamResp = await upstreamReq.close();

      response.statusCode = upstreamResp.statusCode;
      for (final header in const [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final values = upstreamResp.headers[header];
        if (values != null) response.headers.set(header, values.join(','));
      }
      // Renderers rely on Accept-Ranges to enable seeking.
      if (upstreamResp.headers[HttpHeaders.acceptRangesHeader] == null) {
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }
      // DLNA seek/streaming capability headers — without these many TVs treat
      // the stream as non-seekable.
      response.headers.set('contentFeatures.dlna.org', dlnaOrgContentFeatures);
      response.headers.set('transferMode.dlna.org', 'Streaming');

      if (request.method == 'HEAD') {
        await upstreamResp.drain();
        await response.close();
        return;
      }

      await upstreamResp.pipe(response);
    } catch (error) {
      // The renderer disconnecting mid-stream is normal (seek/stop) — log quietly.
      _log.fine('Proxy request ended: $error');
      try {
        response.statusCode = HttpStatus.badGateway;
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    _upstreamUrl = null;
    final server = _server;
    _server = null;
    try {
      await server?.close(force: true);
    } catch (_) {}
    try {
      _client.close(force: true);
    } catch (_) {}
    _log.info('Local media proxy stopped');
  }

  /// Picks the local IPv4 the renderer can actually reach. On a multi-homed
  /// machine this matters: prefer an address on the **same /24 subnet** as
  /// [rendererHost] (the right NIC), then any private LAN address, then any.
  static Future<String?> _localIp({String? rendererHost}) async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = [
        for (final iface in interfaces)
          for (final addr in iface.addresses) addr.address,
      ];

      // Same-subnet match (the interface on the renderer's network).
      final rendererPrefix = _slash24(rendererHost);
      if (rendererPrefix != null) {
        for (final ip in candidates) {
          if (_slash24(ip) == rendererPrefix) {
            _log.info('Proxy using $ip (same subnet as renderer $rendererHost)');
            return ip;
          }
        }
        _log.warning('No local interface on the renderer\'s subnet ($rendererHost) — '
            'falling back to a private LAN address');
      }

      for (final ip in candidates) {
        if (_isPrivate(ip)) return ip;
      }
      return candidates.isNotEmpty ? candidates.first : null;
    } catch (error) {
      _log.warning('Could not determine local IP: $error');
    }
    return null;
  }

  static bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);

  /// The first three octets of an IPv4 address (its /24 prefix), or null if
  /// [host] isn't a dotted-quad IPv4 (e.g. a hostname).
  static String? _slash24(String? host) {
    if (host == null) return null;
    final match = RegExp(r'^(\d{1,3}\.\d{1,3}\.\d{1,3})\.\d{1,3}$').firstMatch(host);
    return match?.group(1);
  }

  static String _extensionForType(String type) {
    final t = type.toLowerCase();
    if (t.contains('matroska')) return '.mkv';
    if (t.contains('mp4')) return '.mp4';
    if (t.contains('webm')) return '.webm';
    if (t.contains('mpegurl')) return '.m3u8';
    if (t.contains('mp2t')) return '.ts';
    if (t.contains('avi')) return '.avi';
    return '.mp4';
  }
}

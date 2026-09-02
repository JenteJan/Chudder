import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:logging/logging.dart';

import 'package:fladder/wrappers/players/cast/desktop/cast_mdns_discovery.dart' show CastDeviceInfo;

final _log = Logger('Cast.dlna');

/// A discovered UPnP/DLNA MediaRenderer (a "play to" target such as an LG/Samsung
/// TV, a Sonos speaker, or a generic DLNA renderer).
class DlnaRenderer {
  final String id;
  final String name;

  /// Absolute control URLs resolved against the device's base address.
  final Uri avTransportControlUrl;
  final Uri? renderingControlUrl;

  /// Whether the renderer's ConnectionManager sink lists any video formats
  /// (false for audio-only renderers such as Sonos speakers).
  final bool supportsVideo;

  const DlnaRenderer({
    required this.id,
    required this.name,
    required this.avTransportControlUrl,
    this.renderingControlUrl,
    this.supportsVideo = true,
  });
}

/// Discovers DLNA renderers via SSDP (the UPnP discovery protocol).
class DlnaDiscovery {
  static const _multicastChannel = MethodChannel('uk.jentejan.chudder/multicast');
  static final InternetAddress _ssdpAddress = InternetAddress('239.255.255.250');
  static const _ssdpPort = 1900;
  // Some TVs only answer the specific MediaRenderer search; others (incl. some
  // LG webOS sets) only answer the broad `ssdp:all`. Send both to be safe.
  static const _searchTargets = [
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'ssdp:all',
  ];

  static Future<List<DlnaRenderer>> discover({
    Duration timeout = const Duration(seconds: 5),
    void Function(DlnaRenderer renderer)? onRenderer,
    void Function(CastDeviceInfo device)? onCastDevice,
  }) async {
    _log.info('DLNA scan starting (timeout ${timeout.inSeconds}s)');
    await _acquireMulticastLock();
    final locations = <String>{};
    int responses = 0;

    // One client for the whole scan, and each device described the moment
    // it answers. Every location used to wait for the full window to close
    // before being fetched, so a TV that replied within a second showed up
    // six seconds later; and each fetch opened its own client.
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    final describes = <Future<DlnaRenderer?>>[];
    void describeNew(String location) {
      if (!locations.add(location)) return;
      describes.add(_describe(location, client, onCastDevice: onCastDevice).then((renderer) {
        if (renderer != null) onRenderer?.call(renderer);
        return renderer;
      }));
    }

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        responses++;
        final response = String.fromCharCodes(datagram.data);
        final location = _headerValue(response, 'location');
        final st = _headerValue(response, 'st') ?? _headerValue(response, 'nt');
        _log.fine('SSDP reply from ${datagram.address.address}: ST=$st LOCATION=$location');
        if (location != null) describeNew(location);
      }, onError: (Object error) {
        // "Send failed (Operation not permitted)" arrives here, as an event on
        // the socket, not from send() - and unhandled, it was an uncaught error
        // in the zone at every launch on Android.
        _log.fine('SSDP socket error: $error');
      });

      final searches = [
        for (final target in _searchTargets)
          [
            'M-SEARCH * HTTP/1.1',
            'HOST: 239.255.255.250:1900',
            'MAN: "ssdp:discover"',
            'MX: 3',
            'ST: $target',
            '',
            '',
          ].join('\r\n').codeUnits,
      ];
      // Send each twice — SSDP is UDP and lossy. Both targets go out
      // together and are repeated together, so the pause is paid once.
      for (final bytes in searches) {
        socket.send(bytes, _ssdpAddress, _ssdpPort);
      }
      await Future.delayed(const Duration(milliseconds: 300));
      for (final bytes in searches) {
        socket.send(bytes, _ssdpAddress, _ssdpPort);
      }

      await Future.delayed(timeout);
    } catch (error, stack) {
      _log.warning('DLNA scan error', error, stack);
    } finally {
      socket?.close();
      await _releaseMulticastLock();
    }

    _log.info('DLNA scan: $responses SSDP reply packet(s), ${locations.length} unique location(s)');
    // Most have resolved by now; this only waits for the late ones.
    final renderers = await Future.wait(describes);
    client.close();
    final result = renderers.whereType<DlnaRenderer>().toList();
    _log.info('DLNA scan finished: ${result.length} renderer(s) — ${result.map((r) => r.name).toList()}');
    return result;
  }

  /// Fetches and parses a device description, returning a renderer if it exposes
  /// an AVTransport service. Devices without one that look like Google Cast
  /// receivers (DIAL device type / Google manufacturer) are probed on the Cast
  /// port and surfaced via [onCastDevice] — Chromecasts announce over SSDP too,
  /// which makes them discoverable even when mDNS is broken on the host
  /// (Windows' 5353 is contested: the system resolver always holds it and e.g.
  /// adb's mDNS can starve every other listener).
  static Future<DlnaRenderer?> _describe(
    String location,
    HttpClient client, {
    void Function(CastDeviceInfo device)? onCastDevice,
  }) async {
    try {
      final uri = Uri.parse(location);
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      final base = Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
      final name = _firstTag(body, 'friendlyName') ?? uri.host;
      final udn = _firstTag(body, 'UDN');

      Uri? avTransport;
      Uri? renderingControl;
      Uri? connectionManager;
      for (final service in _serviceBlocks(body)) {
        final type = _firstTag(service, 'serviceType') ?? '';
        final controlUrl = _firstTag(service, 'controlURL');
        if (controlUrl == null) continue;
        final resolved = base.resolve(controlUrl);
        if (type.contains('AVTransport')) {
          avTransport = resolved;
        } else if (type.contains('RenderingControl')) {
          renderingControl = resolved;
        } else if (type.contains('ConnectionManager')) {
          connectionManager = resolved;
        }
      }

      if (avTransport == null) {
        final deviceType = _firstTag(body, 'deviceType') ?? '';
        final manufacturer = _firstTag(body, 'manufacturer') ?? '';
        final castCandidate = deviceType.contains('dial') || manufacturer.contains('Google');
        if (castCandidate && onCastDevice != null) {
          // DIAL is also announced by smart TVs that aren't Cast receivers
          // (LG webOS), so an open Cast protocol port is the real test.
          if (await _castPortOpen(uri.host)) {
            final device = CastDeviceInfo(
              id: udn ?? uri.host,
              name: name,
              host: uri.host,
              port: 8009,
              model: _firstTag(body, 'modelName'),
            );
            _log.info('Found Cast device via SSDP: "$name" @ ${uri.host} (${device.model ?? 'unknown model'})');
            onCastDevice(device);
            return null;
          }
        }
        _log.info('Skipping "$name" @ ${uri.host} — no AVTransport service (not a media renderer)');
        return null;
      }
      final supportsVideo = connectionManager == null ? true : await _sinkSupportsVideo(connectionManager, client);
      _log.info('Resolved DLNA renderer: "$name" @ ${uri.host} '
          '(AVTransport=${avTransport.path}, video=${supportsVideo ? 'yes' : 'no'})');
      return DlnaRenderer(
        id: udn ?? uri.host,
        name: name,
        avTransportControlUrl: avTransport,
        renderingControlUrl: renderingControl,
        supportsVideo: supportsVideo,
      );
    } catch (error) {
      _log.fine('Failed to describe $location: $error');
      return null;
    }
  }

  /// Whether the Cast protocol port (8009) accepts connections on [host] —
  /// the definitive marker of a Google Cast receiver.
  static Future<bool> _castPortOpen(String host) async {
    try {
      final socket = await Socket.connect(host, 8009, timeout: const Duration(milliseconds: 900));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Asks the renderer's ConnectionManager which formats it can play. A sink
  /// without any video entries is an audio-only renderer (e.g. Sonos). Fails
  /// open: a flaky/absent reply must not hide a capable TV.
  static Future<bool> _sinkSupportsVideo(Uri connectionManagerUrl, HttpClient client) async {
    try {
      final request = await client.postUrl(connectionManagerUrl);
      request.headers.set('Content-Type', 'text/xml; charset="utf-8"');
      request.headers.set('SOAPACTION', '"urn:schemas-upnp-org:service:ConnectionManager:1#GetProtocolInfo"');
      request.write('<?xml version="1.0" encoding="utf-8"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
          '<s:Body><u:GetProtocolInfo xmlns:u="urn:schemas-upnp-org:service:ConnectionManager:1"/></s:Body>'
          '</s:Envelope>');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final sink = _firstTag(body, 'Sink') ?? '';
      if (sink.isEmpty) return true;
      // Entries are `protocol:network:contentFormat:additionalInfo`. Only
      // http-get matters for our streaming; proprietary schemes (Sonos's
      // x-rincon-*:*:*:*) carry wildcard formats and must not count as video.
      return sink.split(',').any((entry) {
        final fields = entry.trim().split(':');
        if (fields.length < 3 || !fields[0].startsWith('http-get')) return false;
        final format = fields[2];
        return format.startsWith('video/') || format == '*';
      });
    } catch (error) {
      _log.fine('GetProtocolInfo failed (assuming video-capable): $error');
      return true;
    }
  }

  static String? _headerValue(String response, String header) {
    for (final line in const LineSplitter().convert(response)) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toLowerCase() == header) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  static Iterable<String> _serviceBlocks(String xml) sync* {
    final pattern = RegExp(r'<service>(.*?)</service>', dotAll: true);
    for (final match in pattern.allMatches(xml)) {
      yield match.group(1) ?? '';
    }
  }

  static final Map<String, RegExp> _tagPatterns = {};

  static String? _firstTag(String xml, String tag) {
    final pattern = _tagPatterns.putIfAbsent(tag, () => RegExp('<$tag>(.*?)</$tag>', dotAll: true));
    return pattern.firstMatch(xml)?.group(1)?.trim();
  }

  static Future<void> _acquireMulticastLock() async {
    try {
      await _multicastChannel.invokeMethod('acquire');
    } catch (_) {}
  }

  static Future<void> _releaseMulticastLock() async {
    try {
      await _multicastChannel.invokeMethod('release');
    } catch (_) {}
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:logging/logging.dart';

final _log = Logger('Cast.dlna');

/// A discovered UPnP/DLNA MediaRenderer (a "play to" target such as an LG/Samsung
/// TV, a Sonos speaker, or a generic DLNA renderer).
class DlnaRenderer {
  final String id;
  final String name;

  /// Absolute control URLs resolved against the device's base address.
  final Uri avTransportControlUrl;
  final Uri? renderingControlUrl;

  const DlnaRenderer({
    required this.id,
    required this.name,
    required this.avTransportControlUrl,
    this.renderingControlUrl,
  });
}

/// Discovers DLNA renderers via SSDP (the UPnP discovery protocol).
class DlnaDiscovery {
  static const _multicastChannel = MethodChannel('nl.jknaapen.fladder/multicast');
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
  }) async {
    _log.info('DLNA scan starting (timeout ${timeout.inSeconds}s)');
    await _acquireMulticastLock();
    final locations = <String>{};
    int responses = 0;

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
        if (location != null) locations.add(location);
      });

      for (final target in _searchTargets) {
        final search = [
          'M-SEARCH * HTTP/1.1',
          'HOST: 239.255.255.250:1900',
          'MAN: "ssdp:discover"',
          'MX: 3',
          'ST: $target',
          '',
          '',
        ].join('\r\n');
        final bytes = search.codeUnits;
        // Send each twice — SSDP is UDP and lossy.
        socket.send(bytes, _ssdpAddress, _ssdpPort);
        await Future.delayed(const Duration(milliseconds: 300));
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
    final renderers = await Future.wait(locations.map(_describe));
    final result = renderers.whereType<DlnaRenderer>().toList();
    _log.info('DLNA scan finished: ${result.length} renderer(s) — ${result.map((r) => r.name).toList()}');
    return result;
  }

  /// Fetches and parses a device description, returning a renderer if it exposes
  /// an AVTransport service.
  static Future<DlnaRenderer?> _describe(String location) async {
    try {
      final uri = Uri.parse(location);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final base = Uri(scheme: uri.scheme, host: uri.host, port: uri.port);
      final name = _firstTag(body, 'friendlyName') ?? uri.host;
      final udn = _firstTag(body, 'UDN');

      Uri? avTransport;
      Uri? renderingControl;
      for (final service in _serviceBlocks(body)) {
        final type = _firstTag(service, 'serviceType') ?? '';
        final controlUrl = _firstTag(service, 'controlURL');
        if (controlUrl == null) continue;
        final resolved = base.resolve(controlUrl);
        if (type.contains('AVTransport')) {
          avTransport = resolved;
        } else if (type.contains('RenderingControl')) {
          renderingControl = resolved;
        }
      }

      if (avTransport == null) {
        _log.info('Skipping "$name" @ ${uri.host} — no AVTransport service (not a media renderer)');
        return null;
      }
      _log.info('Resolved DLNA renderer: "$name" @ ${uri.host} (AVTransport=${avTransport.path})');
      return DlnaRenderer(
        id: udn ?? uri.host,
        name: name,
        avTransportControlUrl: avTransport,
        renderingControlUrl: renderingControl,
      );
    } catch (error) {
      _log.fine('Failed to describe $location: $error');
      return null;
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

  static String? _firstTag(String xml, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return match?.group(1)?.trim();
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

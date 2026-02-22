import 'package:fladder/util/application_info.dart';
import 'package:xid/xid.dart';

/// Sanitizes a string for use in HTTP headers by normalizing accents and removing spaces
String sanitizeHeaderValue(String value) {
  // Normalize to NFD (decomposed form) then remove combining diacritical marks
  final normalized = value
      .replaceAllMapped(
        RegExp(r'[àáâãäå]'),
        (m) => 'a',
      )
      .replaceAllMapped(
        RegExp(r'[èéêë]'),
        (m) => 'e',
      )
      .replaceAllMapped(
        RegExp(r'[ìíîï]'),
        (m) => 'i',
      )
      .replaceAllMapped(
        RegExp(r'[òóôõö]'),
        (m) => 'o',
      )
      .replaceAllMapped(
        RegExp(r'[ùúûü]'),
        (m) => 'u',
      )
      .replaceAllMapped(
        RegExp(r'[ýÿ]'),
        (m) => 'y',
      )
      .replaceAllMapped(
        RegExp(r'[ñ]'),
        (m) => 'n',
      )
      .replaceAllMapped(
        RegExp(r'[ç]'),
        (m) => 'c',
      );
  return normalized
      .replaceAll(RegExp(r'[^\x00-\x7F]'), '') // Remove remaining non-ASCII
      .replaceAll(' ', '_'); // Replace spaces with underscores
}

Map<String, String> generateHeader(ApplicationInfo application) {
  var xid = Xid();
  final clientName = sanitizeHeaderValue(application.name);
  return {
    'content-type': 'application/json',
    'x-emby-authorization':
        'MediaBrowser Client="$clientName", Device="${application.platformLabel}", DeviceId="$xid", Version="${application.version}"',
  };
}

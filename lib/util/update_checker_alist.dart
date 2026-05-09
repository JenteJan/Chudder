import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fladder/util/alist_release_extras.dart';
import 'package:fladder/util/update_checker.dart';

const _allowedDownloadKeys = {'android', 'windows_installer'};

class AlistFetchResult {
  final List<ReleaseInfo> releases;
  final Map<String, AlistReleaseExtras> extras;

  const AlistFetchResult({
    required this.releases,
    required this.extras,
  });

  static const empty = AlistFetchResult(releases: [], extras: {});
}

AlistFetchResult parseAlistManifest(
  String body, {
  required String currentVersion,
  int count = 5,
}) {
  late final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      return AlistFetchResult.empty;
    }
    json = decoded;
  } catch (e) {
    dev.log('AList manifest: malformed JSON', error: e);
    return AlistFetchResult.empty;
  }

  final schema = json['schema'];
  if (schema != 1) {
    dev.log('AList manifest: unsupported schema $schema');
    return AlistFetchResult.empty;
  }

  final list = (json['releases'] as List<dynamic>?) ?? const [];

  final releases = <ReleaseInfo>[];
  final extras = <String, AlistReleaseExtras>{};

  for (final entry in list.take(count)) {
    if (entry is! Map<String, dynamic>) continue;
    final version = entry['version'] as String?;
    if (version == null || version.isEmpty) continue;

    final downloads = <String, String>{};
    final dlMap = entry['downloads'];
    if (dlMap is Map<String, dynamic>) {
      for (final dl in dlMap.entries) {
        if (!_allowedDownloadKeys.contains(dl.key)) continue;
        final url = dl.value;
        if (url is String && url.isNotEmpty) {
          downloads[dl.key] = url;
        }
      }
    }

    final isNewer = compareSemverParts(version, currentVersion) > 0;

    releases.add(ReleaseInfo(
      version: version,
      changelog: (entry['changelog'] as String?)?.trim() ?? '',
      url: '',
      isNewerThanCurrent: isNewer,
      downloads: downloads,
    ));

    final sha256Map = <String, String>{};
    final shaJson = entry['sha256'];
    if (shaJson is Map<String, dynamic>) {
      for (final sha in shaJson.entries) {
        if (sha.value is String) {
          sha256Map[sha.key] = sha.value as String;
        }
      }
    }

    extras[version] = AlistReleaseExtras(
      publishedAt: DateTime.tryParse(entry['publishedAt'] as String? ?? ''),
      sha256: sha256Map,
      minSupported: entry['minSupported'] as String?,
    );
  }

  return AlistFetchResult(releases: releases, extras: extras);
}

int compareSemverParts(String a, String b) {
  final aParts = a.split('.').map(int.tryParse).toList();
  final bParts = b.split('.').map(int.tryParse).toList();

  for (var i = 0; i < aParts.length || i < bParts.length; i++) {
    final aVal = i < aParts.length ? (aParts[i] ?? 0) : 0;
    final bVal = i < bParts.length ? (bParts[i] ?? 0) : 0;
    if (aVal != bVal) return aVal.compareTo(bVal);
  }
  return 0;
}

class AlistUpdateChecker {
  static const _baseUrl = String.fromEnvironment('ALIST_BASE_URL');
  static const _manifestPath = String.fromEnvironment(
    'ALIST_MANIFEST_PATH',
    defaultValue: '/manifest.json',
  );

  final http.Client _client;

  AlistUpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<AlistFetchResult> fetchRecentReleases({int count = 5}) async {
    if (!isConfigured) {
      dev.log('ALIST_BASE_URL is not set; AList updater disabled');
      return AlistFetchResult.empty;
    }

    final info = await PackageInfo.fromPlatform();
    final url = Uri.parse('$_baseUrl$_manifestPath');

    try {
      final response = await _client.get(url);
      if (response.statusCode != 200) {
        dev.log('AList manifest fetch failed: HTTP ${response.statusCode}');
        return AlistFetchResult.empty;
      }
      return parseAlistManifest(
        response.body,
        currentVersion: info.version,
        count: count,
      );
    } catch (e, st) {
      dev.log('AList manifest fetch error', error: e, stackTrace: st);
      return AlistFetchResult.empty;
    }
  }
}

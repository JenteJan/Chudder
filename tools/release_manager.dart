// Maktep release manager: builds Android + Windows artifacts, uploads to
// AList over WebDAV, and updates manifest.json.

import 'dart:convert';
import 'dart:io';

class PubspecVersion {
  final String version;
  final int buildNumber;
  const PubspecVersion(this.version, this.buildNumber);
}

final _versionLine = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', multiLine: true);

PubspecVersion parsePubspecVersion(String yamlText) {
  final m = _versionLine.firstMatch(yamlText);
  if (m == null) {
    throw const FormatException(
      "could not find a 'version: X.Y.Z+N' line in pubspec.yaml",
    );
  }
  return PubspecVersion(m.group(1)!, int.parse(m.group(2)!));
}

String bumpPubspecVersion(String yamlText, String level) {
  final current = parsePubspecVersion(yamlText);
  final parts = current.version.split('.').map(int.parse).toList();
  var build = current.buildNumber;

  switch (level) {
    case 'major':
      parts[0]++;
      parts[1] = 0;
      parts[2] = 0;
    case 'minor':
      parts[1]++;
      parts[2] = 0;
    case 'patch':
      parts[2]++;
    case 'build':
      build++;
    default:
      throw ArgumentError.value(level, 'level',
          'must be one of: major, minor, patch, build');
  }

  final newVersion = '${parts[0]}.${parts[1]}.${parts[2]}';
  return yamlText.replaceFirst(_versionLine, 'version: $newVersion+$build');
}

Map<String, dynamic> emptyManifest() => {
      'schema': 1,
      'latest': '',
      'releases': <Map<String, dynamic>>[],
    };

void upsertRelease(
  Map<String, dynamic> manifest,
  Map<String, dynamic> release, {
  required int maxReleases,
}) {
  final version = release['version'] as String;
  final list = (manifest['releases'] as List).cast<Map<String, dynamic>>();

  list.removeWhere((r) => r['version'] == version);
  list.insert(0, release);
  list.sort((a, b) =>
      compareSemverStrings(b['version'] as String, a['version'] as String));

  if (list.length > maxReleases) {
    list.removeRange(maxReleases, list.length);
  }

  manifest['releases'] = list;

  String latest = '';
  for (final r in list) {
    final v = r['version'] as String;
    if (latest.isEmpty || compareSemverStrings(v, latest) > 0) {
      latest = v;
    }
  }
  manifest['latest'] = latest;
}

int compareSemverStrings(String a, String b) {
  final aParts = a.split('.').map(int.tryParse).toList();
  final bParts = b.split('.').map(int.tryParse).toList();
  for (var i = 0; i < aParts.length || i < bParts.length; i++) {
    final aVal = i < aParts.length ? (aParts[i] ?? 0) : 0;
    final bVal = i < bParts.length ? (bParts[i] ?? 0) : 0;
    if (aVal != bVal) return aVal.compareTo(bVal);
  }
  return 0;
}

class ReleaseManagerConfig {
  final String alistDavUrl;
  final String alistDownloadUrl;
  final String alistUser;
  final String alistPass;
  final String? innoSetupPath;
  final int maxReleases;
  final String manifestPath;

  const ReleaseManagerConfig({
    required this.alistDavUrl,
    required this.alistDownloadUrl,
    required this.alistUser,
    required this.alistPass,
    required this.innoSetupPath,
    required this.maxReleases,
    required this.manifestPath,
  });
}

Future<ReleaseManagerConfig> loadReleaseManagerConfig(File f) async {
  if (!await f.exists()) {
    throw FileSystemException('config file not found', f.path);
  }
  final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;

  String required(String key) {
    final v = raw[key];
    if (v is! String || v.isEmpty) {
      throw FormatException("config: required field '$key' is missing", f.path);
    }
    return v;
  }

  final pass = required('alistPass');
  if (pass == 'PUT-IN-LOCAL-FILE') {
    throw StateError(
      "config: alistPass is still the placeholder. "
      "Edit ${f.path} and set a real value.",
    );
  }

  return ReleaseManagerConfig(
    alistDavUrl: required('alistDavUrl'),
    alistDownloadUrl: required('alistDownloadUrl'),
    alistUser: required('alistUser'),
    alistPass: pass,
    innoSetupPath: raw['innoSetupPath'] as String?,
    maxReleases: (raw['maxReleases'] as int?) ?? 10,
    manifestPath: (raw['manifestPath'] as String?) ?? '/manifest.json',
  );
}

void main(List<String> args) {
  stderr.writeln('release_manager: not yet implemented');
  exit(64);
}

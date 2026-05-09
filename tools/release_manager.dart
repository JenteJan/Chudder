// Maktep release manager: builds Android + Windows artifacts, uploads to
// AList over WebDAV, and updates manifest.json.

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

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

Future<String> sha256OfFile(File f) async {
  final digest = await sha256.bind(f.openRead()).first;
  return digest.toString().toLowerCase();
}

Future<int> runProcess(
  String executable,
  List<String> args, {
  String? cwd,
}) async {
  stdout.writeln('+ $executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  return process.exitCode;
}

class _Auth {
  final String user;
  final String pass;
  const _Auth(this.user, this.pass);

  String get basic => 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
}

Future<http.Response> _webdavGet(Uri url, _Auth auth) {
  return http.get(url, headers: {'Authorization': auth.basic});
}

Future<void> _webdavPutFile(Uri url, File file, _Auth auth) async {
  final bytes = await file.readAsBytes();
  final res = await http.put(
    url,
    headers: {
      'Authorization': auth.basic,
      'Content-Type': 'application/octet-stream',
    },
    body: bytes,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException(
      'WebDAV PUT $url failed: ${res.statusCode} ${res.body}',
    );
  }
}

Future<void> _webdavPutJson(Uri url, Object json, _Auth auth) async {
  final body = const JsonEncoder.withIndent('  ').convert(json);
  final res = await http.put(
    url,
    headers: {
      'Authorization': auth.basic,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: utf8.encode(body),
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw HttpException(
      'WebDAV PUT $url failed: ${res.statusCode} ${res.body}',
    );
  }
}

const _changelogDir = 'tools/changelogs';
const _defaultConfigPath = 'tools/release_manager.config.local.json';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('bump',
        allowed: ['major', 'minor', 'patch', 'build'],
        help: 'Bump pubspec.yaml version before building.')
    ..addOption('version',
        help: 'Override version (test-only). Bypasses pubspec read.')
    ..addOption('platforms',
        defaultsTo: 'android,windows',
        help: 'Comma-separated subset.')
    ..addFlag('dry-run',
        defaultsTo: false, help: 'Build + hash; skip uploads + manifest PUT.')
    ..addFlag('skip-build', defaultsTo: false, help: 'Skip flutter builds.')
    ..addOption('config',
        defaultsTo: _defaultConfigPath, help: 'Config file path.')
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (parsed['help'] as bool) {
    stdout.writeln('Usage: dart run tools/release_manager.dart [options]');
    stdout.writeln(parser.usage);
    return;
  }

  final configFile = File(parsed['config'] as String);
  late final ReleaseManagerConfig cfg;
  try {
    cfg = await loadReleaseManagerConfig(configFile);
  } on FileSystemException {
    stderr.writeln(
      'Config file ${configFile.path} not found.\n'
      'Copy tools/release_manager.config.example.json to that path and fill it in.',
    );
    exit(2);
  } on FormatException catch (e) {
    stderr.writeln('Config error: $e');
    exit(2);
  } on StateError catch (e) {
    stderr.writeln('Config error: $e');
    exit(2);
  }

  final pubspecFile = File('pubspec.yaml');
  final pubspecText = await pubspecFile.readAsString();
  String version;
  int buildNumber;

  final overrideVersion = parsed['version'] as String?;
  final bumpLevel = parsed['bump'] as String?;

  if (overrideVersion != null) {
    version = overrideVersion;
    buildNumber = parsePubspecVersion(pubspecText).buildNumber;
  } else if (bumpLevel != null) {
    final updated = bumpPubspecVersion(pubspecText, bumpLevel);
    await pubspecFile.writeAsString(updated);
    final v = parsePubspecVersion(updated);
    version = v.version;
    buildNumber = v.buildNumber;
    stdout.writeln('Bumped pubspec.yaml to $version+$buildNumber');
  } else {
    final v = parsePubspecVersion(pubspecText);
    version = v.version;
    buildNumber = v.buildNumber;
  }

  final changelogFile = File('$_changelogDir/$version.md');
  if (!await changelogFile.exists()) {
    stderr.writeln(
      'Changelog ${changelogFile.path} not found.\n'
      'Create it before running the release manager.',
    );
    exit(3);
  }
  final changelog = (await changelogFile.readAsString()).trim();

  final platforms = (parsed['platforms'] as String)
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();

  final dryRun = parsed['dry-run'] as bool;
  final skipBuild = parsed['skip-build'] as bool;

  String? iscc;
  if (platforms.contains('windows')) {
    iscc = cfg.innoSetupPath;
    if (iscc == null || iscc.isEmpty) {
      iscc = await _which('iscc');
    }
    if (iscc == null) {
      stderr.writeln(
        "Inno Setup 'iscc' not found. Set 'innoSetupPath' in the config "
        "or add it to PATH.",
      );
      exit(4);
    }
  }

  if (!skipBuild) {
    final pgCode = await runProcess('flutter', ['pub', 'get']);
    if (pgCode != 0) exit(pgCode);
    if (platforms.contains('android')) {
      final code = await runProcess('flutter', [
        'build', 'apk', '--release',
        '--flavor=production',
        '--build-number=$buildNumber',
        '--dart-define=UPDATE_SOURCE=alist',
        '--dart-define=ALIST_BASE_URL=${cfg.alistDownloadUrl}',
      ]);
      if (code != 0) exit(code);
    }
    if (platforms.contains('windows')) {
      final wcode = await runProcess('flutter', [
        'build', 'windows', '--release',
        '--build-number=$buildNumber',
        '--dart-define=UPDATE_SOURCE=alist',
        '--dart-define=ALIST_BASE_URL=${cfg.alistDownloadUrl}',
      ]);
      if (wcode != 0) exit(wcode);

      final icode = await runProcess(iscc!, [
        '/DFLADDER_VERSION=$version',
        r'windows\windows_setup.iss',
      ]);
      if (icode != 0) exit(icode);
    }
  }

  final artifacts = <String, File>{};
  if (platforms.contains('android')) {
    final apk = File('build/app/outputs/flutter-apk/app-production-release.apk');
    if (!apk.existsSync()) {
      stderr.writeln('Android APK not found at ${apk.path}');
      exit(5);
    }
    artifacts['android'] = apk;
  }
  if (platforms.contains('windows')) {
    final exe = File(r'windows\Output\cinemaktep_setup.exe');
    if (!exe.existsSync()) {
      stderr.writeln('Windows installer not found at ${exe.path}');
      exit(5);
    }
    artifacts['windows_installer'] = exe;
  }

  final downloadsByKey = <String, String>{};
  final hashesByKey = <String, String>{};
  for (final entry in artifacts.entries) {
    final platformKey = entry.key;
    final file = entry.value;
    final filename = platformKey == 'android'
        ? 'Fladder-Android.apk'
        : 'Fladder-Windows-Setup.exe';
    final hash = await sha256OfFile(file);
    hashesByKey[platformKey] = hash;
    downloadsByKey[platformKey] =
        '${_stripTrailingSlash(cfg.alistDownloadUrl)}/$version/$filename';

    final davTarget = Uri.parse(
      '${_stripTrailingSlash(cfg.alistDavUrl)}/$version/$filename',
    );
    if (dryRun) {
      stdout.writeln('[dry-run] would PUT ${file.path} -> $davTarget');
    } else {
      await _webdavPutFile(davTarget, file, _Auth(cfg.alistUser, cfg.alistPass));
      stdout.writeln('uploaded ${file.path} -> $davTarget');
    }
  }

  final manifestUri = Uri.parse(
    '${_stripTrailingSlash(cfg.alistDavUrl)}${cfg.manifestPath}',
  );
  Map<String, dynamic> manifest;
  if (dryRun) {
    stdout.writeln('[dry-run] would GET $manifestUri');
    manifest = emptyManifest();
  } else {
    final res = await _webdavGet(manifestUri, _Auth(cfg.alistUser, cfg.alistPass));
    if (res.statusCode == 404) {
      manifest = emptyManifest();
    } else if (res.statusCode >= 200 && res.statusCode < 300) {
      manifest = jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      stderr.writeln(
        'WebDAV GET $manifestUri failed: ${res.statusCode} ${res.body}',
      );
      exit(5);
    }
  }

  final newRelease = <String, dynamic>{
    'version': version,
    'publishedAt': DateTime.now().toUtc().toIso8601String(),
    'changelog': changelog,
    'downloads': downloadsByKey,
    'sha256': hashesByKey,
  };
  upsertRelease(manifest, newRelease, maxReleases: cfg.maxReleases);

  if (dryRun) {
    stdout.writeln('[dry-run] would PUT manifest:');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(manifest));
  } else {
    await _webdavPutJson(manifestUri, manifest, _Auth(cfg.alistUser, cfg.alistPass));
    stdout.writeln('manifest updated at $manifestUri');
  }

  stdout.writeln('--- release $version ---');
  for (final entry in downloadsByKey.entries) {
    stdout.writeln('${entry.key}: ${entry.value}  (sha256 ${hashesByKey[entry.key]})');
  }
}

String _stripTrailingSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

Future<String?> _which(String binary) async {
  final isWindows = Platform.isWindows;
  final cmd = isWindows ? 'where' : 'which';
  try {
    final result = await Process.run(cmd, [binary], runInShell: true);
    if (result.exitCode != 0) return null;
    final out = (result.stdout as String).trim();
    if (out.isEmpty) return null;
    return out.split(RegExp(r'\r?\n')).first.trim();
  } catch (_) {
    return null;
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// Every directory the app asks Windows for, moved under the bench profile.
///
/// A bench run must never read or write the real `JenteJan\chudder` folders:
/// the person at this PC runs Chudder from them with a login and a device id
/// of their own, and a second process with that device id takes their server
/// pushes away.
class BenchPathProvider extends PathProviderWindows {
  BenchPathProvider(this.root);

  final String root;

  String _dir(String name) {
    final dir = Directory(p.join(root, name));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  String get temp => _dir('temp');

  @override
  Future<String?> getTemporaryPath() async => temp;

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationCachePath() async => _dir('cache');

  @override
  Future<String?> getDownloadsPath() async => _dir('downloads');
}

/// Installs the profile directories before anything asks for a path.
///
/// `shared_preferences_windows` does not go through [PathProviderPlatform]: it
/// keeps a `PathProviderWindows` of its own, so it is handed ours.
BenchPathProvider installBenchPaths(String root) {
  final provider = BenchPathProvider(root);
  PathProviderPlatform.instance = provider;
  final prefs = SharedPreferencesWindows();
  // ignore: invalid_use_of_visible_for_testing_member
  prefs.pathProvider = provider;
  SharedPreferencesStorePlatform.instance = prefs;
  IOOverrides.global = _AuditingIOOverrides(provider);
  return provider;
}

/// Paths the app touched outside the profile, for the output to report. Reads
/// of the app's own install folder and of Windows itself are expected.
final Set<String> outsideProfilePaths = <String>{};

/// Local servers the app opened during the run.
final List<String> serverSocketBinds = <String>[];

final class _AuditingIOOverrides extends IOOverrides {
  _AuditingIOOverrides(this.provider)
      : _allowed = [
          p.normalize(provider.root).toLowerCase(),
          p.normalize(p.dirname(Platform.resolvedExecutable)).toLowerCase(),
          (Platform.environment['WINDIR'] ?? r'C:\Windows').toLowerCase(),
        ];

  final BenchPathProvider provider;
  final List<String> _allowed;

  void _audit(String path) {
    if (outsideProfilePaths.length >= 50 || path.isEmpty) return;
    final String full;
    try {
      full = p.normalize(p.absolute(path)).toLowerCase();
    } catch (_) {
      return;
    }
    for (final allowed in _allowed) {
      if (full.startsWith(allowed)) return;
    }
    outsideProfilePaths.add(path);
  }

  @override
  File createFile(String path) {
    _audit(path);
    return super.createFile(path);
  }

  @override
  Directory createDirectory(String path) {
    _audit(path);
    return super.createDirectory(path);
  }

  @override
  Link createLink(String path) {
    _audit(path);
    return super.createLink(path);
  }

  @override
  Directory getSystemTempDirectory() => super.createDirectory(provider.temp);

  @override
  Future<ServerSocket> serverSocketBind(dynamic address, int port, {int backlog = 0, bool v6Only = false, bool shared = false}) {
    serverSocketBinds.add('$address:$port');
    return super.serverSocketBind(address, port, backlog: backlog, v6Only: v6Only, shared: shared);
  }
}

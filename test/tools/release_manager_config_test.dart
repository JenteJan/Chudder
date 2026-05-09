import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tools/release_manager.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('release-cfg-');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('loadReleaseManagerConfig parses every supported field', () async {
    final f = File('${tmp.path}/c.json')
      ..writeAsStringSync(jsonEncode({
        'alistDavUrl': 'https://x/dav',
        'alistDownloadUrl': 'https://x/d',
        'alistUser': 'u',
        'alistPass': 'p',
        'innoSetupPath': 'C:/iscc.exe',
        'maxReleases': 5,
        'manifestPath': '/m.json',
      }));

    final cfg = await loadReleaseManagerConfig(f);
    expect(cfg.alistDavUrl, 'https://x/dav');
    expect(cfg.alistDownloadUrl, 'https://x/d');
    expect(cfg.alistUser, 'u');
    expect(cfg.alistPass, 'p');
    expect(cfg.innoSetupPath, 'C:/iscc.exe');
    expect(cfg.maxReleases, 5);
    expect(cfg.manifestPath, '/m.json');
  });

  test('loadReleaseManagerConfig fills defaults for optional fields', () async {
    final f = File('${tmp.path}/c.json')
      ..writeAsStringSync(jsonEncode({
        'alistDavUrl': 'https://x/dav',
        'alistDownloadUrl': 'https://x/d',
        'alistUser': 'u',
        'alistPass': 'p',
      }));

    final cfg = await loadReleaseManagerConfig(f);
    expect(cfg.maxReleases, 10);
    expect(cfg.manifestPath, '/manifest.json');
    expect(cfg.innoSetupPath, isNull);
  });

  test('loadReleaseManagerConfig throws on missing required field', () async {
    final f = File('${tmp.path}/c.json')
      ..writeAsStringSync(jsonEncode({'alistDavUrl': 'x'}));

    expect(() => loadReleaseManagerConfig(f), throwsFormatException);
  });

  test('loadReleaseManagerConfig throws when file does not exist', () async {
    final f = File('${tmp.path}/missing.json');
    expect(() => loadReleaseManagerConfig(f), throwsA(isA<FileSystemException>()));
  });

  test('loadReleaseManagerConfig flags placeholder password', () async {
    final f = File('${tmp.path}/c.json')
      ..writeAsStringSync(jsonEncode({
        'alistDavUrl': 'https://x/dav',
        'alistDownloadUrl': 'https://x/d',
        'alistUser': 'u',
        'alistPass': 'PUT-IN-LOCAL-FILE',
      }));

    expect(() => loadReleaseManagerConfig(f), throwsStateError);
  });
}

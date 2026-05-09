import 'package:fladder/util/update_checker_alist.dart';
import 'package:flutter_test/flutter_test.dart';

const _validManifest = '''
{
  "schema": 1,
  "latest": "0.10.4",
  "releases": [
    {
      "version": "0.10.4",
      "publishedAt": "2026-05-09T10:00:00Z",
      "changelog": "- Faster syncplay\\n- Live TV fix",
      "minSupported": "0.10.0",
      "downloads": {
        "android": "https://alist.example/d/fladder/0.10.4/Fladder-Android.apk",
        "windows_installer": "https://alist.example/d/fladder/0.10.4/Fladder-Windows-Setup.exe",
        "linux_appimage": "https://ignore.example/old.AppImage"
      },
      "sha256": {
        "android": "ab12",
        "windows_installer": "cd34"
      }
    },
    {
      "version": "0.10.3",
      "changelog": "- Earlier release",
      "downloads": {
        "android": "https://alist.example/d/fladder/0.10.3/Fladder-Android.apk"
      }
    }
  ]
}
''';

void main() {
  group('parseAlistManifest', () {
    test('parses releases newest first and flags newer-than-current', () {
      final result = parseAlistManifest(_validManifest, currentVersion: '0.10.3');

      expect(result.releases, hasLength(2));
      expect(result.releases[0].version, '0.10.4');
      expect(result.releases[0].isNewerThanCurrent, isTrue);
      expect(result.releases[1].version, '0.10.3');
      expect(result.releases[1].isNewerThanCurrent, isFalse);
    });

    test('keeps only allowed download keys (android, windows_installer)', () {
      final result = parseAlistManifest(_validManifest, currentVersion: '0.10.3');

      expect(result.releases[0].downloads.keys,
          unorderedEquals(['android', 'windows_installer']));
      expect(result.releases[0].downloads['android'], contains('Fladder-Android.apk'));
    });

    test('captures extras (publishedAt, sha256, minSupported) keyed by version', () {
      final result = parseAlistManifest(_validManifest, currentVersion: '0.10.3');

      final extras = result.extras['0.10.4'];
      expect(extras, isNotNull);
      expect(extras!.publishedAt, DateTime.utc(2026, 5, 9, 10));
      expect(extras.sha256['android'], 'ab12');
      expect(extras.minSupported, '0.10.0');
    });

    test('returns empty result for unsupported schema', () {
      const body = '{"schema": 99, "releases": []}';
      final result = parseAlistManifest(body, currentVersion: '0.10.3');

      expect(result.releases, isEmpty);
      expect(result.extras, isEmpty);
    });

    test('skips releases missing version or downloads gracefully', () {
      const body = '''
      {
        "schema": 1,
        "latest": "0.10.4",
        "releases": [
          {"version": "0.10.4", "downloads": {"android": "https://x/a.apk"}},
          {"changelog": "no version"},
          {"version": "0.10.3"}
        ]
      }
      ''';
      final result = parseAlistManifest(body, currentVersion: '0.10.0');

      expect(result.releases.map((r) => r.version), ['0.10.4', '0.10.3']);
      expect(result.releases[1].downloads, isEmpty);
    });

    test('returns empty result on malformed JSON', () {
      final result = parseAlistManifest('not json', currentVersion: '0.10.3');
      expect(result.releases, isEmpty);
    });

    test('honors count parameter', () {
      const body = '''
      {
        "schema": 1,
        "latest": "1.0.0",
        "releases": [
          {"version": "1.0.0", "downloads": {}},
          {"version": "0.9.0", "downloads": {}},
          {"version": "0.8.0", "downloads": {}}
        ]
      }
      ''';
      final result = parseAlistManifest(body, currentVersion: '0.0.1', count: 2);
      expect(result.releases, hasLength(2));
    });
  });
}

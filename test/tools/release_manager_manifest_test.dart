import 'package:flutter_test/flutter_test.dart';

import '../../tools/release_manager.dart';

void main() {
  group('emptyManifest', () {
    test('returns schema 1, empty latest, empty releases', () {
      final m = emptyManifest();
      expect(m['schema'], 1);
      expect(m['latest'], '');
      expect((m['releases'] as List), isEmpty);
    });
  });

  group('upsertRelease', () {
    test('inserts a new release at the top of an empty manifest', () {
      final m = emptyManifest();
      upsertRelease(m, _release('0.10.4'), maxReleases: 10);
      final releases = m['releases'] as List;
      expect(releases, hasLength(1));
      expect(releases[0]['version'], '0.10.4');
      expect(m['latest'], '0.10.4');
    });

    test('replaces an existing entry with the same version', () {
      final m = emptyManifest();
      upsertRelease(m, _release('0.10.4', changelog: 'first'),
          maxReleases: 10);
      upsertRelease(m, _release('0.10.4', changelog: 'second'),
          maxReleases: 10);
      final releases = m['releases'] as List;
      expect(releases, hasLength(1));
      expect(releases[0]['changelog'], 'second');
    });

    test('keeps newest first across multiple inserts', () {
      final m = emptyManifest();
      upsertRelease(m, _release('0.10.3'), maxReleases: 10);
      upsertRelease(m, _release('0.10.5'), maxReleases: 10);
      upsertRelease(m, _release('0.10.4'), maxReleases: 10);
      final versions =
          (m['releases'] as List).map((r) => r['version']).toList();
      expect(versions, ['0.10.5', '0.10.4', '0.10.3']);
    });

    test('latest tracks highest semver, not most recently inserted', () {
      final m = emptyManifest();
      upsertRelease(m, _release('0.10.5'), maxReleases: 10);
      upsertRelease(m, _release('0.10.3'), maxReleases: 10);
      expect(m['latest'], '0.10.5');
    });

    test('trims to maxReleases', () {
      final m = emptyManifest();
      for (final v in ['0.10.1', '0.10.2', '0.10.3', '0.10.4']) {
        upsertRelease(m, _release(v), maxReleases: 2);
      }
      final versions =
          (m['releases'] as List).map((r) => r['version']).toList();
      expect(versions, ['0.10.4', '0.10.3']);
    });

    test('preserves arbitrary unknown fields on a release', () {
      final m = emptyManifest();
      (m['releases'] as List).add({
        'version': '0.10.4',
        'futureField': 'preserved',
        'downloads': {},
      });
      upsertRelease(m, _release('0.10.4', changelog: 'updated'),
          maxReleases: 10);
      final entry = (m['releases'] as List).first as Map;
      expect(entry['futureField'], isNull,
          reason: 'replacement is full overwrite for the matching version');
      expect(entry['changelog'], 'updated');
    });
  });

  group('compareSemverStrings', () {
    test('handles 1.10 > 1.2', () {
      expect(compareSemverStrings('1.10.0', '1.2.0'), greaterThan(0));
    });

    test('equal versions return 0', () {
      expect(compareSemverStrings('1.2.3', '1.2.3'), 0);
    });
  });
}

Map<String, dynamic> _release(String version, {String changelog = ''}) {
  return {
    'version': version,
    'publishedAt': '2026-05-09T10:00:00.000Z',
    'changelog': changelog,
    'downloads': {
      'android': 'https://x/$version/Fladder-Android.apk',
    },
    'sha256': {
      'android': 'abc',
    },
  };
}

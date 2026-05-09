import 'package:flutter_test/flutter_test.dart';

import '../../tools/release_manager.dart';

const _samplePubspec = '''
name: fladder
description: A simple cross-platform Jellyfin client.
publish_to: "none"

version: 0.10.3+1

environment:
  sdk: ">=3.1.3 <4.0.0"
''';

void main() {
  group('parsePubspecVersion', () {
    test('reads major.minor.patch and build number', () {
      final v = parsePubspecVersion(_samplePubspec);
      expect(v.version, '0.10.3');
      expect(v.buildNumber, 1);
    });

    test('throws when version line is missing', () {
      const noVersion = 'name: fladder\nenvironment:\n  sdk: any\n';
      expect(() => parsePubspecVersion(noVersion), throwsFormatException);
    });

    test('throws when build number is missing', () {
      const noBuild = 'name: x\nversion: 1.2.3\n';
      expect(() => parsePubspecVersion(noBuild), throwsFormatException);
    });
  });

  group('bumpPubspecVersion', () {
    test('patch bump increments patch only', () {
      final out = bumpPubspecVersion(_samplePubspec, 'patch');
      expect(parsePubspecVersion(out).version, '0.10.4');
      expect(parsePubspecVersion(out).buildNumber, 1);
    });

    test('minor bump resets patch', () {
      final out = bumpPubspecVersion(_samplePubspec, 'minor');
      expect(parsePubspecVersion(out).version, '0.11.0');
    });

    test('major bump resets minor and patch', () {
      final out = bumpPubspecVersion(_samplePubspec, 'major');
      expect(parsePubspecVersion(out).version, '1.0.0');
    });

    test('build bump increments build number only', () {
      final out = bumpPubspecVersion(_samplePubspec, 'build');
      expect(parsePubspecVersion(out).version, '0.10.3');
      expect(parsePubspecVersion(out).buildNumber, 2);
    });

    test('preserves surrounding lines', () {
      final out = bumpPubspecVersion(_samplePubspec, 'patch');
      expect(out, contains('publish_to: "none"'));
      expect(out, contains('environment:'));
      expect(out, contains('  sdk: ">=3.1.3 <4.0.0"'));
    });

    test('rejects unknown level', () {
      expect(() => bumpPubspecVersion(_samplePubspec, 'epoch'),
          throwsArgumentError);
    });
  });
}

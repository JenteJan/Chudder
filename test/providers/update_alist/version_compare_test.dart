import 'package:fladder/util/update_checker_alist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('compareSemverParts', () {
    test('equal versions return 0', () {
      expect(compareSemverParts('1.2.3', '1.2.3'), 0);
    });

    test('compares parts numerically (10 > 2)', () {
      expect(compareSemverParts('1.10.0', '1.2.0'), greaterThan(0));
    });

    test('shorter version treats missing parts as 0', () {
      expect(compareSemverParts('1.0', '1.0.0'), 0);
      expect(compareSemverParts('1.0.1', '1.0'), greaterThan(0));
    });

    test('non-numeric parts are treated as 0', () {
      expect(compareSemverParts('1.2.foo', '1.2.0'), 0);
    });

    test('newer minor beats same major', () {
      expect(compareSemverParts('0.10.4', '0.10.3'), greaterThan(0));
    });
  });
}

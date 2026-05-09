import 'dart:io';

import 'package:fladder/util/alist_sha256_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('alist-sha-test-');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('verifySha256 returns true on match', () async {
    final file = File('${tmp.path}/payload.bin')..writeAsStringSync('hello');
    // sha256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
    final ok = await verifySha256(
      file,
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
    expect(ok, isTrue);
  });

  test('verifySha256 is case-insensitive on the expected hex', () async {
    final file = File('${tmp.path}/payload.bin')..writeAsStringSync('hello');
    final ok = await verifySha256(
      file,
      '2CF24DBA5FB0A30E26E83B2AC5B9E29E1B161E5C1FA7425E73043362938B9824',
    );
    expect(ok, isTrue);
  });

  test('verifySha256 returns false on mismatch', () async {
    final file = File('${tmp.path}/payload.bin')..writeAsStringSync('hello');
    final ok = await verifySha256(file, 'deadbeef');
    expect(ok, isFalse);
  });

  test('verifySha256 returns false for missing file', () async {
    final ok = await verifySha256(File('${tmp.path}/missing.bin'), 'whatever');
    expect(ok, isFalse);
  });
}

import 'dart:math';

import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/blur_placeholder_image.dart';

void main() {
  const alphabet = r'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~';

  /// A hash of [numX] by [numY] components, the same one every run.
  String hashOf(int numX, int numY) {
    final random = Random(numX * 10 + numY);
    final buffer = StringBuffer(alphabet[(numX - 1) + (numY - 1) * 9]);
    for (var i = 1; i < 4 + 2 * numX * numY; i++) {
      // The first colour is three bytes in four characters: it stops short
      // of what four characters could hold.
      buffer.write(alphabet[random.nextInt(i == 2 ? 29 : 83)]);
    }
    return buffer.toString();
  }

  final hashes = [
    'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
    'LGF5]+Yk^6#M@-5c,1J5@[or[Q6.',
    'L6PZfSi_.AyE_3t7t7R**0o#DgR4',
    for (final (numX, numY) in [(1, 1), (4, 3), (3, 4), (4, 4), (6, 5), (9, 9)]) hashOf(numX, numY),
  ];

  test('the same pixels as flutter_blurhash, to within a level', () async {
    for (final hash in hashes) {
      for (final size in [16, 32]) {
        final expected = await optimizedBlurHashDecode(blurHash: hash, width: size, height: size);
        final actual = decodeBlurHash(hash, size, size);
        expect(actual.length, expected.length);
        for (var i = 0; i < actual.length; i++) {
          expect((actual[i] - expected[i]).abs(), lessThanOrEqualTo(1),
              reason: '$hash at byte $i of a ${size}px decode');
        }
      }
    }
  });

  test('a string that is not a blurhash is refused, not drawn', () {
    expect(() => decodeBlurHash('', 16, 16), throwsFormatException);
    expect(() => decodeBlurHash('LEHV6nWB2yk8', 16, 16), throwsFormatException);
    expect(() => decodeBlurHash('LEHV6nWB2yk8pyo0adR*.7kCMd j', 16, 16), throwsFormatException);
  });

  test('two placeholders for one hash are one picture to the cache', () {
    expect(const BlurPlaceholderImage('00OZZy'), const BlurPlaceholderImage('00OZZy'));
    expect(const BlurPlaceholderImage('00OZZy'), isNot(const BlurPlaceholderImage('00OZZy', size: 32)));
  });
}

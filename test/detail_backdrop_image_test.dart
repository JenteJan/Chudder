import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/screens/shared/detail_scaffold.dart';
import 'package:chudder/util/fladder_image.dart';

void main() {
  testWidgets('a backdrop decoded again at a new size stays on screen instead of fading back in', (tester) async {
    final picture = MemoryImage(Uint8List.fromList(_pixelPng));

    Future<void> show(int height) => tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 200,
              height: 120,
              child: DetailBackdropImage(image: ResizeImage(picture, height: height)),
            ),
          ),
        );

    Finder inside(Type type) => find.descendant(of: find.byType(DetailBackdropImage), matching: find.byType(type));
    RawImage raw() => tester.widget<RawImage>(inside(RawImage));
    double opacity() => tester.widget<FadeTransition>(inside(FadeTransition)).opacity.value;

    Future<void> decoded() async {
      // Decoding happens outside the fake clock.
      for (var i = 0; i < 50 && raw().image == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(raw().image, isNotNull, reason: 'the picture never loaded');
    }

    await show(100);
    expect(opacity(), 0, reason: 'nothing to show yet');
    await decoded();
    // The first time, a short fade in over the blur.
    await tester.pump(kImageFadeIn);
    await tester.pump(const Duration(milliseconds: 20));
    expect(opacity(), 1.0);
    final first = raw().image;

    // The window is resized: the same picture at another decode size.
    await show(80);
    await tester.pump();
    expect(raw().image, isNotNull, reason: 'the picture blinked out while the new size decodes');
    expect(identical(raw().image, first), isTrue);
    expect(opacity(), 1.0, reason: 'the picture faded out while the new size decodes');

    for (var i = 0; i < 50 && identical(raw().image, first); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(identical(raw().image, first), isFalse, reason: 'the new size never landed');
    expect(opacity(), 1.0, reason: 'a picture that has shown is faded in again');
    expect(tester.binding.transientCallbackCount, 0, reason: 'a fade is running');
  });
}

/// A 1x1 transparent PNG.
const List<int> _pixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

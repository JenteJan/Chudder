import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/util/fladder_image.dart';

void main() {
  testWidgets('a picture starts to show on the frame after it is decoded', (tester) async {
    final file = File('${Directory.systemTemp.createTempSync('fladder_image_test').path}/pixel.png');
    await tester.runAsync(() => file.writeAsBytes(_pixelPng));
    addTearDown(() => file.parent.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: SizedBox(
            width: 100,
            height: 150,
            child: FladderImage(image: ImageData(path: file.path, key: 'pixel')),
          ),
        ),
      ),
    );

    // Loading a file and decoding it happen outside the fake clock.
    Image target() => tester
        .widgetList<Image>(find.byType(Image))
        .firstWhere((image) => image.image is FileImage || image.image is ResizeImage);
    for (var i = 0; i < 50 && target().opacity?.value != 1.0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      final opacity = target().opacity?.value ?? 0;
      if (opacity > 0 || _loaded(tester)) break;
    }
    expect(_loaded(tester), isTrue, reason: 'the picture never loaded');

    await tester.pump(const Duration(milliseconds: 40));
    expect(target().opacity!.value, greaterThan(0), reason: 'still invisible 40ms after it was decoded');
    await tester.pump(kImageFadeIn);
    expect(target().opacity!.value, 1.0);
  });
}

bool _loaded(WidgetTester tester) =>
    tester.widgetList<FadeInImage>(find.byType(FadeInImage)).isNotEmpty &&
    tester.stateList(find.byType(Image)).length >= 2 &&
    tester.binding.transientCallbackCount > 0;

/// A 1x1 transparent PNG.
const List<int> _pixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

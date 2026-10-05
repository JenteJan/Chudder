import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/util/fladder_image.dart';

/// A poster the size the server sends a phone: 600x900.
Future<File> _posterFile(WidgetTester tester, {int width = 600, int height = 900}) async {
  final dir = Directory.systemTemp.createTempSync('poster_decode_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/poster_${width}x$height.png');
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFF3366CC),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
  return file;
}

Future<ui.Image> _decoded(WidgetTester tester) async {
  ui.Image? found() {
    for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) {
      final image = raw.image;
      // The transparent placeholder is a single pixel.
      if (image != null && image.width > 1) return image;
    }
    return null;
  }

  for (var i = 0; i < 100 && found() == null; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  final image = found();
  expect(image, isNotNull, reason: 'the poster never decoded');
  return image!;
}

Widget _cell(File file, {required double width, required double height, required bool decodeToLayout}) {
  return ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: FladderImage(
              image: ImageData(path: file.path, key: file.path),
              decodeToLayout: decodeToLayout,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  tearDown(() => PaintingBinding.instance.imageCache
    ..clear()
    ..clearLiveImages());

  testWidgets('a poster in a grid cell is decoded at the size of the cell, not the size it was sent', (tester) async {
    final file = await _posterFile(tester);
    // 100x150 at 2x is 200x300 pixels; rounded up to the 64 step, 256x320.
    await tester.pumpWidget(_cell(file, width: 100, height: 150, decodeToLayout: true));
    final image = await _decoded(tester);
    expect(image.width, 256);
    expect(image.height, 384, reason: 'kept its shape, and covers the whole cell');
  });

  testWidgets('a wide picture in a tall cell still covers it top to bottom', (tester) async {
    final file = await _posterFile(tester, width: 900, height: 600);
    await tester.pumpWidget(_cell(file, width: 100, height: 150, decodeToLayout: true));
    final image = await _decoded(tester);
    expect(image.height, greaterThanOrEqualTo(300));
    expect(image.width / image.height, closeTo(1.5, 0.01));
  });

  testWidgets('a picture smaller than its cell is not scaled up', (tester) async {
    final file = await _posterFile(tester, width: 100, height: 150);
    await tester.pumpWidget(_cell(file, width: 100, height: 150, decodeToLayout: true));
    final image = await _decoded(tester);
    expect(image.width, 100);
    expect(image.height, 150);
  });

  testWidgets('without it, the picture is decoded as sent', (tester) async {
    final file = await _posterFile(tester);
    await tester.pumpWidget(_cell(file, width: 100, height: 150, decodeToLayout: false));
    final image = await _decoded(tester);
    expect(image.width, 600);
    expect(image.height, 900);
  });

  testWidgets('a cell a few pixels wider does not ask for a new decode', (tester) async {
    final file = await _posterFile(tester);
    await tester.pumpWidget(_cell(file, width: 100, height: 150, decodeToLayout: true));
    await _decoded(tester);
    final before = tester.widget<FadeInImage>(find.byType(FadeInImage)).image;

    await tester.pumpWidget(_cell(file, width: 104, height: 156, decodeToLayout: true));
    final after = tester.widget<FadeInImage>(find.byType(FadeInImage)).image;
    expect(after, before);
  });
}

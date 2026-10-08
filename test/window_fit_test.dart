import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/window_helper.dart';

void main() {
  test('a size saved on a larger monitor is cut down to the screen it opens on', () {
    // Maximised on a 1440p screen at 125 %, opened on a 1080p one.
    expect(fitWindowToDisplay(const Size(2062.4, 1118.4), const Size(1920, 1032)), const Size(1920, 1032));
  });

  test('a size that fits is left alone', () {
    expect(fitWindowToDisplay(const Size(1280, 720), const Size(1920, 1032)), const Size(1280, 720));
  });

  test('only the side that overhangs is cut', () {
    expect(fitWindowToDisplay(const Size(1280, 1400), const Size(1920, 1032)), const Size(1280, 1032));
  });

  test('an unknown screen leaves the saved size', () {
    expect(fitWindowToDisplay(const Size(2062, 1118), null), const Size(2062, 1118));
  });
}

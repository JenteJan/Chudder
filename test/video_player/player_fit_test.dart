import 'package:flutter/painting.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/screens/video_player/video_player.dart';

void main() {
  test('portrait is always contain, whatever was saved', () {
    for (final saved in BoxFit.values) {
      for (final fill in [true, false]) {
        expect(playerFit(portrait: true, fillScreen: fill, saved: saved), BoxFit.contain, reason: '$saved fill=$fill');
      }
    }
  });

  test('landscape follows the saved fit, and fill screen covers', () {
    expect(playerFit(portrait: false, fillScreen: false, saved: BoxFit.contain), BoxFit.contain);
    expect(playerFit(portrait: false, fillScreen: false, saved: BoxFit.fill), BoxFit.fill);
    expect(playerFit(portrait: false, fillScreen: true, saved: BoxFit.contain), BoxFit.cover);
  });
}

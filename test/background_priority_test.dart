// Behind a game, Chudder steps aside - less so while a film plays.

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/background_priority.dart';

void main() {
  test('in use: normal, whatever plays', () {
    expect(standingFor(inUse: true, playing: false), ProcessStanding.normal);
    expect(standingFor(inUse: true, playing: true), ProcessStanding.normal);
  });

  test('not in use: yields while a film plays, rests otherwise', () {
    expect(standingFor(inUse: false, playing: true), ProcessStanding.yielding);
    expect(standingFor(inUse: false, playing: false), ProcessStanding.resting);
  });
}

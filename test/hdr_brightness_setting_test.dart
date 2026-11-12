import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/settings/video_player_settings.dart';

void main() {
  test('HDR films are shown as mastered unless asked otherwise', () {
    expect(VideoPlayerSettingsModel().hdrBrightness, HdrBrightness.asMastered);
    expect(HdrBrightness.asMastered.paperWhiteNits, 203, reason: 'BT.2408 reference white');
  });

  test('the steps only ever get brighter', () {
    final levels = HdrBrightness.values.map((value) => value.paperWhiteNits).toList();
    expect(levels, orderedEquals([...levels]..sort()));
  });

  test('the level survives saving, and an old save without it reads as mastered', () {
    final saved = VideoPlayerSettingsModel(hdrBrightness: HdrBrightness.muchBrighter).toJson();
    expect(VideoPlayerSettingsModel.fromJson(saved).hdrBrightness, HdrBrightness.muchBrighter);
    final old = Map<String, dynamic>.of(saved)..remove('hdrBrightness');
    expect(VideoPlayerSettingsModel.fromJson(old).hdrBrightness, HdrBrightness.asMastered);
  });
}

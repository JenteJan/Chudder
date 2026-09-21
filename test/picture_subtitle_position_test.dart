import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/util/subtitle_position_calculator.dart';

void main() {
  group('mpvSubtitlePosition', () {
    test('the default offset puts a picture subtitle where the text sits', () {
      // 0.10 of the frame up from the bottom, which mpv counts from the top.
      expect(SubtitlePositionCalculator.mpvSubtitlePosition(0.10), 90);
    });

    test('the bottom edge and half way up', () {
      expect(SubtitlePositionCalculator.mpvSubtitlePosition(0), 100);
      expect(SubtitlePositionCalculator.mpvSubtitlePosition(0.5), 50);
    });

    test('an offset past the frame is held at its top', () {
      expect(SubtitlePositionCalculator.mpvSubtitlePosition(1.4), 0);
    });
  });

  group('the controls lift a picture subtitle too', () {
    const settings = SubtitleSettingsModel();

    test('a subtitle below the controls is raised above them', () {
      final offset = SubtitlePositionCalculator.calculateOffset(
        settings: settings,
        showOverlay: true,
        screenHeight: 1000,
        menuHeight: 250,
      );

      expect(offset, 0.25);
      expect(SubtitlePositionCalculator.mpvSubtitlePosition(offset), 75);
    });

    test('with the controls away it follows the setting again', () {
      final offset = SubtitlePositionCalculator.calculateOffset(
        settings: settings,
        showOverlay: false,
        screenHeight: 1000,
        menuHeight: 250,
      );

      expect(SubtitlePositionCalculator.mpvSubtitlePosition(offset), 90);
    });
  });
}

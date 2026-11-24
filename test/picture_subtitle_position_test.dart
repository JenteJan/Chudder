import 'package:flutter_test/flutter_test.dart';

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

  group('text moves only as far as the controls cover it', () {
    test('text already above the controls stays put', () {
      expect(SubtitlePositionCalculator.liftForControls(restBottom: 200, controlsHeight: 120), 0);
    });

    test('text under the controls rises just past their top', () {
      // Bottom at 100, controls 120 tall: up to 120 plus the gap.
      expect(
        SubtitlePositionCalculator.liftForControls(restBottom: 100, controlsHeight: 120),
        20 + SubtitlePositionCalculator.controlsGap,
      );
    });

    test('with the controls away nothing moves', () {
      expect(SubtitlePositionCalculator.liftForControls(restBottom: 0, controlsHeight: 0), 0);
    });
  });
}

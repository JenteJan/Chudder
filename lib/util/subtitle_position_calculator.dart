import 'dart:math' as math;

import 'package:chudder/models/settings/subtitle_settings_model.dart';

class SubtitlePositionCalculator {
  static const double _fallbackMenuHeightPercentage = 0.15;
  static const double _maxSubtitleOffset = 0.85;

  static double calculateOffset({
    required SubtitleSettingsModel settings,
    required bool showOverlay,
    required double screenHeight,
    double? menuHeight,
  }) {
    if (!showOverlay) {
      return settings.verticalOffset;
    }

    double menuHeightPercentage;

    if (menuHeight != null && screenHeight > 0) {
      menuHeightPercentage = menuHeight / screenHeight;
    } else {
      menuHeightPercentage = _fallbackMenuHeightPercentage;
    }

    final minSafeOffset = menuHeightPercentage;

    if (settings.verticalOffset >= minSafeOffset) {
      return math.min(settings.verticalOffset, _maxSubtitleOffset);
    }

    return math.max(0.0, math.min(minSafeOffset, _maxSubtitleOffset));
  }

  /// The same place, said the way mpv says it.
  ///
  /// [calculateOffset] gives a fraction of the frame measured up from the
  /// bottom, which is how the app draws its own subtitle text. mpv's
  /// `sub-pos` counts down from the top of the frame with 100 at the bottom
  /// edge, and it is what puts a picture subtitle - a DVD's, which the app
  /// cannot draw itself - at the same height as the text.
  static int mpvSubtitlePosition(double offset) => (100 - offset * 100).clamp(0.0, 100.0).round();
}

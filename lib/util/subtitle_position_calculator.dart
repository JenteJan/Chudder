import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Where subtitles sit, and how far the player's controls push them up.
///
/// Text moves for the controls only as far as the controls would cover it,
/// and not at all where they stay clear of it. It used to jump to the top of
/// the controls whenever those were up, even when it already sat above them.
/// A picture subtitle - drawn by mpv - does not move for them at all.
class SubtitlePositionCalculator {
  /// Space kept between the controls and a subtitle they pushed up.
  static const double controlsGap = 8;

  /// How far up a subtitle whose bottom sits [restBottom] pixels above the
  /// bottom edge must move to clear controls [controlsHeight] tall.
  static double liftForControls({required double restBottom, required double controlsHeight}) {
    if (controlsHeight <= 0) return 0;
    return math.max(0.0, controlsHeight + controlsGap - restBottom);
  }

  /// How far the controls marked by [controlsKey] reach up from the bottom
  /// of the subtitle area that [subtitles] lays out: from its bottom edge to
  /// the top of what the controls show. Their gradient, and the window's
  /// padding above them, are not counted - measured as one box they pushed
  /// text a good way past the buttons.
  static double? controlsReach(BuildContext subtitles, GlobalKey? controlsKey) {
    final controls = controlsKey?.currentContext?.findRenderObject();
    final area = subtitles.findRenderObject();
    if (controls is! RenderBox || area is! RenderBox) return null;
    if (!controls.hasSize || !area.hasSize || !controls.attached || !area.attached) return null;
    final top = controls.localToGlobal(Offset.zero).dy;
    final bottom = area.localToGlobal(Offset(0, area.size.height)).dy;
    return math.max(0.0, bottom - top);
  }

  /// [offset] - a fraction of the frame measured up from the bottom, the way
  /// the app draws its own subtitle text - said the way mpv says it: `sub-pos`
  /// counts down from the top of the frame with 100 at the bottom edge.
  static int mpvSubtitlePosition(double offset) => (100 - offset * 100).clamp(0.0, 100.0).round();
}

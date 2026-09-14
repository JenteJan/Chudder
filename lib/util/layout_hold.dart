import 'dart:async';

import 'package:flutter/widgets.dart';

/// A size taken from the layout that stays put while the layout is changing.
///
/// A window being resized lays out every frame, and a size that follows it -
/// a share of the screen, say - changes with every one of those frames. For
/// the floating video that meant a texture re-fitted and a shadow re-blurred
/// per frame for the length of the drag. This keeps the size it had until the
/// layout has held still for [settle], then takes the new one.
///
/// Only the size. Whether it still fits is the caller's to clamp every frame,
/// so a window dragged smaller than the held size never overflows it.
class LayoutHold {
  LayoutHold({required this.onSettled, this.settle = const Duration(milliseconds: 250)});

  /// How long the layout has to hold still before the size follows it.
  final Duration settle;

  /// Called, with the size the layout now wants, once the layout has held
  /// still - whether or not that is a new size, since whatever was put up
  /// for the duration has to come down again. A build after this takes the
  /// size. From a timer, never from a build, so it may start animations.
  final ValueChanged<double> onSettled;

  BoxConstraints? _seen;
  double? _held;
  double _wanted = 0;
  Timer? _timer;

  /// Whether the layout is still changing.
  bool get moving => _timer != null;

  /// The size to use under [constraints], which would like to be [wanted].
  double resolve(BoxConstraints constraints, double wanted) {
    _wanted = wanted;
    if (_seen != null && constraints != _seen) {
      _timer?.cancel();
      _timer = Timer(settle, _settleNow);
    }
    _seen = constraints;
    if (!moving || _held == null) _held = wanted;
    return _held!;
  }

  void _settleNow() {
    _timer = null;
    onSettled(_wanted);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart' show debugTraceFocusMoves;

/// Where a focused thing comes to rest on a remote: a little above centre.
///
/// The value matters far less than the fact that there is only one of it. On a
/// television nothing is under a cursor and nothing is under a finger — the
/// only thing telling you what is selected is where the highlight is, and the
/// only thing telling you where the highlight is, is where it was a moment
/// ago. A page that rests the header's buttons on the bottom edge, its
/// episodes four fifths down and everything else dead centre gives you three
/// places to look, so every press ends in a hunt for the outline.
///
/// Above centre rather than on it because a row is read downwards: the thing
/// you are about to move to should already be on screen when you decide to
/// move to it.
const double kTvFocusRest = 0.4;

extension EnsureVisibleHelper on BuildContext {
  /// Where a focused thing should come to rest, given what this spot would
  /// like when there is a pointer.
  ///
  /// On a remote the request is ignored in favour of [kTvFocusRest] — see
  /// there for why a page is not allowed its own opinion per row.
  double focusRestAlignment([double pointerAlignment = 0.5]) =>
      AdaptiveLayout.inputDeviceOf(this) == InputDevice.dPad ? kTvFocusRest : pointerAlignment;

  Future<void> ensureVisible({
    Duration duration = const Duration(milliseconds: 275),
    double? alignment,
    Curve curve = Curves.fastOutSlowIn,
    bool onlyNearest = false,
  }) {
    final scrollable = Scrollable.maybeOf(this);
    if (scrollable == null) return Future.value();

    // An alignment passed in is what this spot wants on a pointer; on a remote
    // every spot wants the same thing.
    final resolved = focusRestAlignment(alignment ?? 0.5);
    if (debugTraceFocusMoves) {
      debugPrint('[ensure] ${widget.runtimeType} alignment=$resolved axis=${scrollable.axisDirection} '
          'from=${scrollable.position.pixels.round()}');
    }

    final renderObject = findRenderObject();
    if (onlyNearest && renderObject != null) {
      final viewport = RenderAbstractViewport.of(renderObject);
      final offset = viewport.getOffsetToReveal(renderObject, resolved).offset;
      return scrollable.position.animateTo(
        offset.clamp(
          scrollable.position.minScrollExtent,
          scrollable.position.maxScrollExtent,
        ),
        duration: duration,
        curve: curve,
      );
    }
    return Scrollable.ensureVisible(
      this,
      duration: duration,
      alignment: resolved,
      curve: curve,
    );
  }
}

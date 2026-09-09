import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Two-finger page swipes on a macOS trackpad, as back and forward.
///
/// The window (MainFlutterWindow.swift) watches the scroll a two-finger swipe
/// arrives as and reports where it began and, at lift-off, which way it went;
/// a three-finger swipe arrives whole. A swipe over a row that could still
/// scroll that way belongs to the row - the dashboard is made of horizontal
/// rows - so the row under the pointer is checked when the swipe begins,
/// before it has moved anything, the way a browser only goes back once the
/// page is already at its edge.
class TrackpadNavigation {
  TrackpadNavigation._();

  static const _channel = MethodChannel('uk.jentejan.chudder/trackpad');

  /// A row this close to its end counts as being there.
  static const _slack = 4.0;

  static VoidCallback? _onBack;
  static VoidCallback? _onForward;
  static bool _rowTakesBack = false;
  static bool _rowTakesForward = false;
  static DateTime? _lastGestureAt;

  /// Whether a trackpad gesture began within [window] of now.
  ///
  /// Fingers landing for a two-finger swipe can register as a tap-to-click
  /// first, and a click on the video toggles playback. Whatever acts on a
  /// click can hold off for a moment and ask this before going ahead.
  static bool gestureBeganWithin(Duration window) {
    final at = _lastGestureAt;
    return at != null && DateTime.now().difference(at) <= window;
  }

  static void listen({required VoidCallback onBack, required VoidCallback onForward}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _onBack = onBack;
    _onForward = onForward;
    _channel.setMethodCallHandler(_handle);
  }

  static void stop() {
    _onBack = null;
    _onForward = null;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    _channel.setMethodCallHandler(null);
  }

  static Future<void> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    final position = Offset(
      (args['x'] as num?)?.toDouble() ?? 0,
      (args['y'] as num?)?.toDouble() ?? 0,
    );
    final back = args['back'] == true;
    if (call.method != 'swipeEnded') _lastGestureAt = DateTime.now();
    switch (call.method) {
      case 'swipeBegan':
        final row = _horizontalRowAt(position);
        _rowTakesBack = row != null && row.pixels > row.minScrollExtent + _slack;
        _rowTakesForward = row != null && row.pixels < row.maxScrollExtent - _slack;
      case 'swipeEnded':
        if (back ? _rowTakesBack : _rowTakesForward) return;
        _navigate(back);
      case 'swipe':
        final row = _horizontalRowAt(position);
        if (row != null) {
          final taken = back ? row.pixels > row.minScrollExtent + _slack : row.pixels < row.maxScrollExtent - _slack;
          if (taken) return;
        }
        _navigate(back);
    }
  }

  static void _navigate(bool back) => (back ? _onBack : _onForward)?.call();

  /// The horizontally scrolling viewport under [position], if any.
  static ScrollPosition? _horizontalRowAt(Offset position) {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return null;
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, view.viewId);
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderViewportBase && axisDirectionToAxis(target.axisDirection) == Axis.horizontal) {
        final offset = target.offset;
        if (offset is ScrollPosition) return offset;
      }
    }
    return null;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_html/html.dart' as html;

import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Full screen in the browser. The browser owns it - Esc, F11 and its own
/// controls leave it without asking - so [mode] follows the document's
/// `fullscreenchange` rather than what was last requested here.
class FullScreenHelper implements FullScreenWrapper {
  const FullScreenHelper._();
  factory FullScreenHelper.instantiate() => const FullScreenHelper._();

  static final ValueNotifier<WindowMode> _mode = ValueNotifier(WindowMode.normal);
  // For as long as the page is open.
  // ignore: cancel_subscriptions
  static StreamSubscription<html.Event>? _changes;

  static bool get _isFullScreen => html.document.fullscreenElement != null;

  static void _readBack() => _mode.value = _isFullScreen ? WindowMode.fullScreen : WindowMode.normal;

  @override
  ValueListenable<WindowMode> get mode {
    _changes ??= html.document.onFullscreenChange.listen((_) => _readBack());
    _readBack();
    return _mode;
  }

  @override
  Future<bool> closeFullScreen(WidgetRef ref) async {
    if (!_isFullScreen) return false;
    html.document.exitFullscreen();
    return true;
  }

  @override
  Future<void> toggleFullScreen(WidgetRef ref) async {
    if (_isFullScreen) {
      html.document.exitFullscreen();
    } else {
      await html.document.documentElement?.requestFullscreen();
    }
  }

  /// A browser tab has no maximise; the title bar that offers it is not drawn
  /// on the web.
  @override
  Future<void> toggleMaximized() async {}

  @override
  Future<void> minimize() async {}
}

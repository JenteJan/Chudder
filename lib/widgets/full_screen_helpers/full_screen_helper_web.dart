import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Full screen in the browser. The browser owns it - Esc, F11 and its own
/// controls leave it without asking - so [mode] follows the document's
/// `fullscreenchange` rather than what was last requested here.
///
/// Standard names only, through `package:web`: `dart:html` calls WebKit's
/// prefixed `webkitExitFullscreen` and listens for `webkitfullscreenchange`,
/// which Firefox has neither of - there the button could enter full screen
/// but never leave it, and its icon never changed.
class FullScreenHelper implements FullScreenWrapper {
  const FullScreenHelper._();
  factory FullScreenHelper.instantiate() => const FullScreenHelper._();

  static final ValueNotifier<WindowMode> _mode = ValueNotifier(WindowMode.normal);
  static bool _listening = false;

  static bool get _isFullScreen => web.document.fullscreenElement != null;

  static void _readBack() => _mode.value = _isFullScreen ? WindowMode.fullScreen : WindowMode.normal;

  @override
  ValueListenable<WindowMode> get mode {
    if (!_listening) {
      _listening = true;
      // For as long as the page is open.
      web.document.addEventListener('fullscreenchange', ((web.Event _) => _readBack()).toJS);
    }
    _readBack();
    return _mode;
  }

  @override
  Future<bool> closeFullScreen(WidgetRef ref) async {
    if (!_isFullScreen) return false;
    await _exit();
    return true;
  }

  @override
  Future<void> toggleFullScreen(WidgetRef ref) async {
    if (_isFullScreen) {
      await _exit();
    } else {
      try {
        await web.document.documentElement?.requestFullscreen().toDart;
      } catch (_) {
        // Refused, e.g. not from a click: the page stays as it is.
      }
    }
    _readBack();
  }

  static Future<void> _exit() async {
    try {
      await web.document.exitFullscreen().toDart;
    } catch (_) {
      // Already left, by Esc or the browser.
    }
  }

  /// A browser tab has no maximise; the title bar that offers it is not drawn
  /// on the web.
  @override
  Future<void> toggleMaximized() async {}

  @override
  Future<void> minimize() async {}
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Full screen for the desktop window.
///
/// On Windows and Linux this resizes the window to cover the display in one
/// move rather than calling `window_manager`'s own full screen, which changes
/// the window's frame and its bounds as separate steps — that is the jump to
/// the corner followed by a blink into place. The window is already frameless
/// (`TitleBarStyle.hidden`), so covering the display is all that is left to do,
/// and Windows hides the taskbar for a focused window that does.
///
/// macOS keeps its native full screen, which it animates properly and which
/// carries the traffic lights and the menu bar with it.
class FullScreenHelper implements FullScreenWrapper {
  const FullScreenHelper._();
  factory FullScreenHelper.instantiate() => const FullScreenHelper._();

  /// Where to put the window back, and whether we are the ones holding it
  /// full screen. Static so the state survives the const constructor.
  static Rect? _restoreBounds;
  static bool _borderless = false;

  static bool get _useBorderless => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// True whether it was us or the platform that made it full screen — the
  /// startup path for HTPC mode still uses the latter.
  static Future<bool> isFullScreen() async => _borderless || await windowManager.isFullScreen();

  static Future<void> setFullScreen(bool value) async {
    if (!_useBorderless) {
      await windowManager.setFullScreen(value);
      return;
    }

    if (value) {
      if (_borderless) return;
      final display = await _displayBounds();
      // Give up on the smooth path rather than guess at the display: a window
      // sized to the wrong rectangle is worse than a jump.
      if (display == null) {
        await windowManager.setFullScreen(true);
        return;
      }
      _restoreBounds = await windowManager.getBounds();
      _borderless = true;
      await windowManager.setBounds(display);
      return;
    }

    // Leave nothing holding the window full screen, whichever route put it
    // there, so it can never be stuck without a way back.
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (!_borderless) return;
    _borderless = false;
    final bounds = _restoreBounds;
    _restoreBounds = null;
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    } else {
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
    }
  }

  /// The display the window is currently on, at its full size rather than its
  /// work area, so the taskbar is covered too.
  static Future<Rect?> _displayBounds() async {
    try {
      final window = await windowManager.getBounds();
      final displays = await screenRetriever.getAllDisplays();
      for (final display in displays) {
        final rect = (display.visiblePosition ?? Offset.zero) & display.size;
        if (rect.contains(window.center)) return rect;
      }
      final primary = await screenRetriever.getPrimaryDisplay();
      return (primary.visiblePosition ?? Offset.zero) & primary.size;
    } catch (error, stack) {
      debugPrint('Could not resolve the display to fill: $error\n$stack');
      return null;
    }
  }

  @override
  Future<void> closeFullScreen(WidgetRef ref) async {
    if (ref.read(argumentsStateProvider.select((value) => value.htpcMode))) return;
    if (await isFullScreen()) {
      await setFullScreen(false);
    }
  }

  @override
  Future<void> toggleFullScreen(WidgetRef ref) async {
    if (ref.read(argumentsStateProvider.select((value) => value.htpcMode))) return;
    await setFullScreen(!await isFullScreen());
  }
}

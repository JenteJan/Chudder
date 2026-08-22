import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Full screen for the desktop window.
///
/// On Windows and Linux this resizes the window to cover the display in one
/// move rather than calling `window_manager`'s own full screen, which changes
/// the window's frame and its bounds as separate steps — that is the jump to
/// the corner followed by a blink into place.
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
  static bool _restoreMaximized = false;

  static bool get _useBorderless => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Windows insets the client area of a `TitleBarStyle.hidden` window by the
  /// invisible resize border it keeps for dragging the edges — eight pixels on
  /// the left, right and bottom. Covering the display with the window frame is
  /// therefore not enough: what gets painted stops short of the screen on three
  /// sides, and the transparent gutter it leaves is the desktop showing
  /// through. `window_manager` drops that inset for a frameless window, which
  /// is the only way to it from here — and it costs a second `SetWindowPos`,
  /// so full screen arrives as two steps rather than the one it should be.
  /// Fusing them means a `SetWindowPos` that changes the frame and the bounds
  /// together, which needs a patched `window_manager` to reach.
  static bool get _needsFramelessPass => !kIsWeb && Platform.isWindows;

  /// True whether it was us or the platform that made it full screen — the
  /// startup path for HTPC mode still uses the latter.
  static Future<bool> isFullScreen() async => _borderless || await windowManager.isFullScreen();

  static Future<void> setFullScreen(bool value) async {
    if (!_useBorderless) {
      await windowManager.setFullScreen(value);
      return;
    }

    if (value) {
      if (await isFullScreen()) return;
      // Windows will not move or resize a maximized window: `SetWindowPos` on
      // one is ignored outright, so setting the bounds to cover the display
      // does nothing whatsoever. `window_manager`'s own route drops the
      // maximized state before it moves the window, and it is the only one
      // that knows how to put that state back afterwards. Its two steps cost
      // nothing to look at from here anyway — a maximized window is already
      // everything but the taskbar, so both of them move it a few pixels. The
      // jump they are worth avoiding is the one from a small window, which is
      // what the rest of this does.
      if (await windowManager.isMaximized()) {
        _restoreMaximized = true;
        await windowManager.setFullScreen(true);
        return;
      }
      final display = await _displayBounds();
      // Give up on the smooth path rather than guess at the display: a window
      // sized to the wrong rectangle is worse than a jump.
      if (display == null) {
        await windowManager.setFullScreen(true);
        return;
      }
      _restoreBounds = await windowManager.getBounds();
      _borderless = true;
      // Bounds first, frame second, and neither order is free: each
      // `SetWindowPos` costs a relayout, so the two land as two steps about
      // eighty milliseconds apart however they are dispatched. This is the
      // cheaper of the two to look at — the window arrives at its full size
      // and only a hairline of desktop around the edge fills in afterwards,
      // rather than the whole layout reflowing at the old size first.
      unawaited(windowManager.setBounds(display));
      if (_needsFramelessPass) {
        await windowManager.setAsFrameless();
      }
      return;
    }

    // Leave nothing holding the window full screen, whichever route put it
    // there, so it can never be stuck without a way back.
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (_restoreMaximized) {
      _restoreMaximized = false;
      // `window_manager` only re-maximizes if it still sees the window as
      // maximized on the way out, and by then it does not: what comes back is
      // the shape of a maximized window without the state, sitting seven
      // pixels under the taskbar. Ask for the state itself.
      if (!await windowManager.isMaximized()) {
        await windowManager.maximize();
      }
    }
    if (!_borderless) return;
    _borderless = false;
    final bounds = _restoreBounds;
    _restoreBounds = null;
    // Puts the resize border — and with it the edges the window is dragged by
    // — back on the window. First, for the same reason as above: the hairline
    // it costs is spent while the window is still full screen, where there is
    // nothing to reflow, instead of after it has shrunk.
    if (_needsFramelessPass) {
      unawaited(windowManager.setTitleBarStyle(TitleBarStyle.hidden));
    }
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

  /// `window_manager` only reports entering and leaving full screen for its own
  /// route into it, so the borderless one has to say so itself — otherwise the
  /// button that just went full screen still offers to go full screen.
  static void _reportFullScreen(WidgetRef ref, bool value) {
    if (!_useBorderless) return;
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(fullScreen: value));
  }

  @override
  Future<void> closeFullScreen(WidgetRef ref) async {
    if (ref.read(argumentsStateProvider.select((value) => value.htpcMode))) return;
    if (await isFullScreen()) {
      await setFullScreen(false);
      _reportFullScreen(ref, false);
    }
  }

  @override
  Future<void> toggleFullScreen(WidgetRef ref) async {
    if (ref.read(argumentsStateProvider.select((value) => value.htpcMode))) return;
    final value = !await isFullScreen();
    await setFullScreen(value);
    _reportFullScreen(ref, value);
  }
}

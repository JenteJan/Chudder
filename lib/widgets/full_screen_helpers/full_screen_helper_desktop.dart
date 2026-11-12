import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// Full screen, maximise and minimise for the desktop window, and the one
/// owner of what the app believes the window is doing.
///
/// Every change runs in turn, never two at once, and ends by reading the
/// window back into [mode]. Anything that changes the window from outside -
/// Win+Up, snapping, the taskbar, a double click Windows handles itself - is
/// picked up the same way: whenever the view changes size or `window_manager`
/// reports anything at all, the window is read again. Nothing here trusts what
/// an event says happened, only that something did.
///
/// On Windows and Linux full screen resizes the window to cover the display in
/// one move rather than calling `window_manager`'s own full screen, which
/// changes the window's frame and its bounds as separate steps - that is the
/// jump to the corner followed by a blink into place.
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

  static final ValueNotifier<WindowMode> _mode = ValueNotifier(WindowMode.normal);

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

  @override
  ValueListenable<WindowMode> get mode {
    _watch();
    return _mode;
  }

  // -- Running changes in turn ------------------------------------------------

  static Future<void> _tail = Future.value();

  /// Runs [change] once everything queued before it has finished, then reads
  /// the window back. A failure is reported to the caller and does not stall
  /// the queue.
  static Future<T> _inTurn<T>(Future<T> Function() change) {
    final result = _tail.then((_) async {
      try {
        return await change();
      } finally {
        await _readBack();
      }
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  static bool _readQueued = false;

  /// Reads the window back once whatever is under way has finished. Calls that
  /// arrive while one is already waiting share it - a drag reports dozens of
  /// sizes, and one read after them is all any of them needs.
  static void requestReadBack() {
    if (_readQueued) return;
    _readQueued = true;
    unawaited(_tail.then((_) async {
      _readQueued = false;
      await _readBack();
    }));
  }

  static Future<void> _readBack() async {
    try {
      final WindowMode value;
      if (await isFullScreen()) {
        value = WindowMode.fullScreen;
      } else if (await windowManager.isMinimized()) {
        value = WindowMode.minimized;
      } else if (await windowManager.isMaximized()) {
        value = WindowMode.maximized;
      } else {
        value = WindowMode.normal;
      }
      _mode.value = value;
    } catch (error) {
      // No window plugin - a widget test. What the window is doing then is
      // whatever it was last set to, which is the default.
      debugPrint('Could not read the window state: $error');
    }
  }

  static bool _watching = false;

  static void _watch() {
    if (_watching) return;
    _watching = true;
    windowManager.addListener(_WindowEvents());
    WidgetsBinding.instance.addObserver(_ViewSizeObserver());
    requestReadBack();
  }

  // -- Full screen -------------------------------------------------------------

  /// True whether it was us or the platform that made it full screen — the
  /// startup path for HTPC mode still uses the latter.
  static Future<bool> isFullScreen() async => _borderless || await windowManager.isFullScreen();

  static Future<void> _setFullScreen(bool value) async {
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
    // Something maximised the window while it covered the display - Win+Up
    // does not ask us. Windows ignores bounds set on a maximised window, so
    // the window would stay display-sized under a title bar it no longer has.
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    // Puts the resize border — and with it the edges the window is dragged by
    // — back on the window. Awaited, and before the bounds: the frame change
    // and the move are separate `SetWindowPos` calls, and letting them overlap
    // is one of the ways the window came back at its old size with the view
    // inside it still laid out for the whole display.
    if (_needsFramelessPass) {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    }
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    } else {
      await windowManager.setSize(const Size(1280, 720));
      await windowManager.center();
    }
  }

  /// HTPC mode re-covers the display when its resolution changes.
  static Future<void> refillDisplay() => _inTurn(() async {
        if (await isFullScreen()) await _setFullScreen(false);
        await _setFullScreen(true);
      });

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

  static bool _htpc(WidgetRef ref) => ref.read(argumentsStateProvider.select((value) => value.htpcMode));

  @override
  Future<bool> closeFullScreen(WidgetRef ref) {
    if (_htpc(ref)) return Future.value(false);
    return _inTurn(() async {
      if (!await isFullScreen()) return false;
      await _setFullScreen(false);
      return true;
    });
  }

  @override
  Future<void> toggleFullScreen(WidgetRef ref) {
    if (_htpc(ref)) return Future.value();
    return _inTurn(() async => _setFullScreen(!await isFullScreen()));
  }

  // -- Maximise and minimise ---------------------------------------------------

  @override
  Future<void> toggleMaximized() => _inTurn(() async {
        if (await isFullScreen()) {
          await _setFullScreen(false);
        } else if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      });

  @override
  Future<void> minimize() => _inTurn(() async {
        if (await isFullScreen()) await _setFullScreen(false);
        await windowManager.minimize();
      });
}

/// Any event at all is a reason to look at the window again; what it claims
/// happened is not used.
class _WindowEvents with WindowListener {
  @override
  void onWindowEvent(String eventName) => FullScreenHelper.requestReadBack();
}

/// The view changing size is the one signal every change of window state
/// gives, whoever made it.
class _ViewSizeObserver with WidgetsBindingObserver {
  @override
  void didChangeMetrics() => FullScreenHelper.requestReadBack();
}

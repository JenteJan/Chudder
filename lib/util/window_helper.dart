import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:window_manager/window_manager.dart';

import 'package:chudder/models/settings/arguments_model.dart';
import 'package:chudder/models/settings/client_settings_model.dart';
import 'package:chudder/perf_bench/perf_bench.dart';

extension WindowHelperSetup on WindowManager {
  Future<void> setupFladderWindowChrome(
    ArgumentsModel startupArguments,
    ClientSettingsModel clientSettings,
    String title,
  ) async {
    // A benchmark window is sized and placed by the benchmark, and never shown
    // in front of anything or focused.
    if (PerfBench.active) return PerfBench.setUpWindow(title);

    final isFullScreen = await windowManager.isFullScreen();
    final isMacDebug = defaultTargetPlatform == TargetPlatform.macOS && kDebugMode;
    final shouldResizeAndShow = !isMacDebug || !isFullScreen;

    final options = WindowOptions(
      // Windows gets no background colour at all. `window_manager` turns a
      // fully transparent one into ACCENT_ENABLE_TRANSPARENTGRADIENT through
      // the undocumented SetWindowCompositionAttribute, which behaves
      // differently per Windows build and lets the desktop through anywhere
      // the app does not paint an opaque pixel. Nothing here wants a
      // see-through window - the hidden title bar is drawn in Dart over an
      // opaque scaffold - and it cost a release: a mask that leaked out of its
      // layer showed the desktop through the detail backdrop on someone
      // else's PC. A null colour skips the call, so no composition attribute
      // is ever set and a painting bug can only ever look wrong, not
      // transparent. macOS and Linux keep it; their vibrancy relies on it.
      backgroundColor: defaultTargetPlatform == TargetPlatform.windows ? null : Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: title,
    );

    // Apply window chrome consistently; only skip waitUntilReadyToShow on macOS debug to avoid breaking full-screen during hot reloads.
    Future<void> applyWindowState() async {
      if (shouldResizeAndShow) {
        await windowManager.setSize(Size(clientSettings.size.x, clientSettings.size.y));
        await windowManager.center();
        await windowManager.show();
        await windowManager.focus();
      }

      if (startupArguments.htpcMode && !isFullScreen) {
        await windowManager.setFullScreen(true);
      }
    }

    if (isMacDebug) {
      await windowManager.setBackgroundColor(options.backgroundColor!);
      await windowManager.setSkipTaskbar(options.skipTaskbar ?? false);
      await windowManager.setTitleBarStyle(options.titleBarStyle!);
      await windowManager.setTitle(options.title ?? title);
      await applyWindowState();
    } else {
      await windowManager.waitUntilReadyToShow(options, applyWindowState);
    }
  }
}

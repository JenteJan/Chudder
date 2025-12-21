import 'package:flutter/material.dart';

// Stub for window_manager on Tizen (TV has no windowing system)

class WindowManager {
  WindowManager._();
  static final WindowManager instance = WindowManager._();

  Future<void> ensureInitialized() async {}

  void addListener(WindowListener listener) {}
  void removeListener(WindowListener listener) {}

  Future<void> waitUntilReadyToShow([WindowOptions? options, VoidCallback? callback]) async {
    callback?.call();
  }

  Future<void> setMinimumSize(Size size) async {}
  Future<void> show() async {}
  Future<void> focus() async {}
  Future<Size> getSize() async => const Size(1920, 1080);
  Future<void> setSize(Size size) async {}
  Future<Offset> getPosition() async => Offset.zero;
  Future<void> center() async {}
  Future<bool> isFullScreen() async => true; // TV is always fullscreen
  Future<void> setFullScreen(bool fullscreen) async {}
}

WindowManager get windowManager => WindowManager.instance;

mixin WindowListener {
  void onWindowClose() {}
  void onWindowResize() {}
  void onWindowResized() {}
  void onWindowMove() {}
  void onWindowMoved() {}
  void onWindowEnterFullScreen() {}
  void onWindowLeaveFullScreen() {}
  void onWindowFocus() {}
  void onWindowBlur() {}
  void onWindowMaximize() {}
  void onWindowUnmaximize() {}
  void onWindowMinimize() {}
  void onWindowRestore() {}
  void onWindowEvent(String eventName) {}
}

class WindowOptions {
  final Color? backgroundColor;
  final bool? skipTaskbar;
  final TitleBarStyle? titleBarStyle;
  final String? title;
  final Size? size;
  final Size? minimumSize;
  final Size? maximumSize;
  final bool? center;
  final bool? alwaysOnTop;
  final bool? fullScreen;

  const WindowOptions({
    this.backgroundColor,
    this.skipTaskbar,
    this.titleBarStyle,
    this.title,
    this.size,
    this.minimumSize,
    this.maximumSize,
    this.center,
    this.alwaysOnTop,
    this.fullScreen,
  });
}

enum TitleBarStyle {
  normal,
  hidden,
  hiddenInset,
}



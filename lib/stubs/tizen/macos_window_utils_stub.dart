// Stub for macos_window_utils on Tizen

class WindowManipulator {
  static Future<void> initialize({bool enableWindowDelegate = false}) async {}

  static Future<void> makeTitlebarTransparent() async {}
  static Future<void> enableFullSizeContentView() async {}
  static Future<void> hideTitle() async {}
  static Future<void> addToolbar() async {}
  static Future<void> setToolbarStyle({dynamic toolbarStyle}) async {}
  static Future<void> setWindowBackgroundColorToDefaultColor() async {}
  static Future<void> setWindowBackgroundColorToClear() async {}
  static Future<void> setMaterial(dynamic material) async {}
  static Future<void> setBlurViewState(dynamic state) async {}
  static Future<void> addEmptyMaskImage() async {}
  static Future<void> overrideStandardWindowButtonPosition({
    dynamic buttonType,
    double? x,
    double? y,
  }) async {}
}

class NSWindowToolbarStyle {
  static const unified = 0;
  static const unifiedCompact = 1;
  static const expanded = 2;
  static const preference = 3;
  static const automatic = 4;
}



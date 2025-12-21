// Stub for desktop_multi_window on Tizen
// TVs don't support multiple windows

class WindowController {
  final int windowId;
  final String arguments;

  WindowController._(this.windowId, this.arguments);

  static Future<WindowController> fromCurrentEngine() async {
    return WindowController._(0, '');
  }

  static Future<WindowController> fromWindowId(int windowId) async {
    return WindowController._(windowId, '');
  }

  Future<void> close() async {}
  Future<void> show() async {}
  Future<void> hide() async {}
  Future<void> center() async {}
  Future<void> setFrame(Rect frame) async {}
  Future<void> setTitle(String title) async {}
}

class Rect {
  final double left;
  final double top;
  final double width;
  final double height;

  const Rect.fromLTWH(this.left, this.top, this.width, this.height);
}



// This is a stub that mirrors the bits of `windows_taskbar` we use, so web
// builds compile without the plugin (it reaches for dart:io).
class ThumbnailToolbarAssetIcon {
  ThumbnailToolbarAssetIcon(this.asset);

  final String asset;

  String get path => asset;
}

class ThumbnailToolbarButton {
  ThumbnailToolbarButton(this.icon, this.tooltip, this.onClick, {this.mode = 0x0});

  final ThumbnailToolbarAssetIcon icon;
  final String tooltip;
  final int mode;
  final void Function() onClick;
}

class WindowsTaskbar {
  static Future<void> setThumbnailToolbar(List<ThumbnailToolbarButton> buttons) async {}

  static Future<void> resetThumbnailToolbar() async {}
}

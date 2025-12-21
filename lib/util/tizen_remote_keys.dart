import 'package:flutter/services.dart';

/// Samsung TV Remote Control Key Mappings
/// These keys are sent by Samsung TV remotes and need to be handled in the app.
///
/// Reference: https://developer.samsung.com/smarttv/develop/guides/user-interaction/remote-control.html
class TizenRemoteKeys {
  // Navigation keys (standard keyboard mappings on Tizen)
  static const LogicalKeyboardKey up = LogicalKeyboardKey.arrowUp;
  static const LogicalKeyboardKey down = LogicalKeyboardKey.arrowDown;
  static const LogicalKeyboardKey left = LogicalKeyboardKey.arrowLeft;
  static const LogicalKeyboardKey right = LogicalKeyboardKey.arrowRight;
  static const LogicalKeyboardKey select = LogicalKeyboardKey.enter;
  static const LogicalKeyboardKey back = LogicalKeyboardKey.escape;

  // Media control keys (mapped from remote control)
  static const LogicalKeyboardKey play = LogicalKeyboardKey.mediaPlay;
  static const LogicalKeyboardKey pause = LogicalKeyboardKey.mediaPause;
  static const LogicalKeyboardKey playPause = LogicalKeyboardKey.mediaPlayPause;
  static const LogicalKeyboardKey stop = LogicalKeyboardKey.mediaStop;
  static const LogicalKeyboardKey rewind = LogicalKeyboardKey.mediaRewind;
  static const LogicalKeyboardKey fastForward = LogicalKeyboardKey.mediaFastForward;

  // Channel/Volume keys
  static const LogicalKeyboardKey channelUp = LogicalKeyboardKey.channelUp;
  static const LogicalKeyboardKey channelDown = LogicalKeyboardKey.channelDown;
  static const LogicalKeyboardKey volumeUp = LogicalKeyboardKey.audioVolumeUp;
  static const LogicalKeyboardKey volumeDown = LogicalKeyboardKey.audioVolumeDown;
  static const LogicalKeyboardKey mute = LogicalKeyboardKey.audioVolumeMute;

  // Color keys (Samsung TV specific - mapped to F1-F4)
  static const LogicalKeyboardKey red = LogicalKeyboardKey.f1;
  static const LogicalKeyboardKey green = LogicalKeyboardKey.f2;
  static const LogicalKeyboardKey yellow = LogicalKeyboardKey.f3;
  static const LogicalKeyboardKey blue = LogicalKeyboardKey.f4;

  // Number keys
  static const LogicalKeyboardKey num0 = LogicalKeyboardKey.digit0;
  static const LogicalKeyboardKey num1 = LogicalKeyboardKey.digit1;
  static const LogicalKeyboardKey num2 = LogicalKeyboardKey.digit2;
  static const LogicalKeyboardKey num3 = LogicalKeyboardKey.digit3;
  static const LogicalKeyboardKey num4 = LogicalKeyboardKey.digit4;
  static const LogicalKeyboardKey num5 = LogicalKeyboardKey.digit5;
  static const LogicalKeyboardKey num6 = LogicalKeyboardKey.digit6;
  static const LogicalKeyboardKey num7 = LogicalKeyboardKey.digit7;
  static const LogicalKeyboardKey num8 = LogicalKeyboardKey.digit8;
  static const LogicalKeyboardKey num9 = LogicalKeyboardKey.digit9;

  // Additional keys
  static const LogicalKeyboardKey info = LogicalKeyboardKey.info;
  static const LogicalKeyboardKey menu = LogicalKeyboardKey.contextMenu;

  /// Check if a key event is a navigation key
  static bool isNavigationKey(LogicalKeyboardKey key) {
    return key == up || key == down || key == left || key == right;
  }

  /// Check if a key event is a media control key
  static bool isMediaKey(LogicalKeyboardKey key) {
    return key == play ||
        key == pause ||
        key == playPause ||
        key == stop ||
        key == rewind ||
        key == fastForward;
  }

  /// Check if a key event is a color key
  static bool isColorKey(LogicalKeyboardKey key) {
    return key == red || key == green || key == yellow || key == blue;
  }
}

/// Mixin for handling Samsung TV remote control events
mixin TizenRemoteHandler {
  /// Handle remote control key down event
  /// Override this in your widget to handle specific keys
  bool handleRemoteKeyDown(LogicalKeyboardKey key) {
    // Default implementation - handle common actions
    if (key == TizenRemoteKeys.back) {
      return handleBack();
    }
    if (key == TizenRemoteKeys.select) {
      return handleSelect();
    }
    if (TizenRemoteKeys.isNavigationKey(key)) {
      return handleNavigation(key);
    }
    if (TizenRemoteKeys.isMediaKey(key)) {
      return handleMediaControl(key);
    }
    return false;
  }

  /// Handle back button press
  bool handleBack() => false;

  /// Handle select/enter button press
  bool handleSelect() => false;

  /// Handle navigation key press
  bool handleNavigation(LogicalKeyboardKey key) => false;

  /// Handle media control key press
  bool handleMediaControl(LogicalKeyboardKey key) => false;
}



import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The window's HDR mode on Windows (see `windows/runner/hdr_channel.cpp`).
///
/// Flutter's stock Windows engine composites everything in 8-bit SDR. Chudder
/// can run on an engine built with HDR support, where the window can switch
/// to a 16-bit float (scRGB) swap chain while HDR video plays; Windows then
/// treats it as HDR content, the way it does a game. On a stock engine
/// [supported] is false and nothing changes.
class WindowsHdr {
  WindowsHdr._();

  static const _channel = MethodChannel('chudder/hdr');

  static Future<bool>? _supported;

  /// Whether the picture is in HDR right now: set by the player once both the
  /// window and the video output have switched. The player's HDR badge shows
  /// this.
  static final ValueNotifier<bool> active = ValueNotifier(false);

  /// Where an HDR film's paper white is drawn, in nits (the HDR brightness
  /// setting). 203 is as mastered.
  static final ValueNotifier<double> paperWhiteNits = ValueNotifier(203);

  /// Whether the window can switch to HDR at all.
  static Future<bool> supported() => _supported ??= _query();

  static Future<bool> _query() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Switches the window's swap chain before the next frame. Returns whether
  /// the engine took the request.
  static Future<bool> setHdr(bool enabled) async {
    if (!await supported()) return false;
    try {
      return await _channel.invokeMethod<bool>('setHdr', {'enabled': enabled}) ?? false;
    } on PlatformException {
      return false;
    }
  }
}

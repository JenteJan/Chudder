import 'package:media_kit/media_kit.dart' as mpv;

/// Reads an mpv property straight from the native player.
///
/// The web build swaps this file for `stubs/web/mpv_properties_web.dart`:
/// media_kit's web player has no mpv underneath and no property calls.
Future<String> getMpvProperty(mpv.NativePlayer platform, String name) => platform.getProperty(name);

/// Sets an mpv property straight on the native player.
Future<void> setMpvProperty(mpv.NativePlayer platform, String name, String value) => platform.setProperty(name, value);

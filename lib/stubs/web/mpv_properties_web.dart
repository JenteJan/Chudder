import 'package:media_kit/media_kit.dart' as mpv;

// The web player is the browser's own video element; there is no mpv to ask.
// Callers only reach these for a NativePlayer, which the web never has.

Future<String> getMpvProperty(mpv.NativePlayer platform, String name) async => '';

Future<void> setMpvProperty(mpv.NativePlayer platform, String name, String value) async {}

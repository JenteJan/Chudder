import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One of the rates the screen can run at.
@immutable
class DisplayRate {
  const DisplayRate({required this.id, required this.refreshRate, this.current = false});

  /// What the system calls this mode.
  final int id;
  final double refreshRate;

  /// Whether the screen is running at this rate now.
  final bool current;
}

/// Runs the screen at a rate a video divides into evenly, while it plays.
///
/// A film is 24 pictures a second and a phone's screen, left alone, draws 60.
/// 24 does not go into 60: each picture is held for two refreshes, then three,
/// then two, and a slow pan across a landscape moves in a limp. At 120 every
/// picture is held for exactly five. Most phones that can do 120 only do it
/// when asked, or when something is being scrolled, so this asks.
///
/// Android only, and only between rates the screen can change among without
/// going black - a television that has to renegotiate with its cable to
/// change rate has a system setting of its own for that, which is left to
/// decide.
class DisplayRefreshRate {
  DisplayRefreshRate._();

  static const _channel = MethodChannel('uk.jentejan.chudder/display');

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether a rate has been asked for and not yet given back.
  static bool _asked = false;

  /// Asks for a rate that suits a video of [fps] pictures a second, if the
  /// screen has a better one than it is at.
  static Future<void> matchVideo(double fps) async {
    if (!_supported) return;
    try {
      final modes = await _channel.invokeListMethod<Map<Object?, Object?>>('modes') ?? const [];
      final id = rateForVideo(fps, [
        for (final mode in modes)
          DisplayRate(
            id: mode['id'] as int,
            refreshRate: (mode['refreshRate'] as num).toDouble(),
            current: mode['current'] == true,
          ),
      ]);
      if (id == null) return;
      await _channel.invokeMethod<void>('prefer', {'id': id});
      _asked = true;
    } on PlatformException {
      // No say in the matter on this device; it plays as it always did.
    } on MissingPluginException {
      // The same, on a build without the channel.
    }
  }

  /// Hands the choice of rate back to the system.
  static Future<void> release() async {
    if (!_supported || !_asked) return;
    _asked = false;
    try {
      await _channel.invokeMethod<void>('prefer', {'id': 0});
    } on PlatformException {
      // Nothing was held.
    } on MissingPluginException {
      // Nothing was held.
    }
  }
}

/// How far off a whole number of refreshes per picture still counts as even.
/// Wide enough for 23.976 on a screen that says 120.00001, and nowhere near
/// 25 on 60.
const double _evenCadence = 0.02;

/// The rate out of [rates] to switch to for a video of [fps] pictures a
/// second, or null to stay as it is.
///
/// Stays put when every picture already gets the same number of refreshes.
/// Otherwise the lowest rate that manages that without going below where the
/// screen is now, so the rest of the app does not get slower for it; and when
/// no rate divides evenly - 25 pictures a second on a 60 and 120 screen - the
/// fastest there is, where the uneven step is at least a shorter one.
int? rateForVideo(double fps, List<DisplayRate> rates) {
  if (!fps.isFinite || fps <= 0 || rates.isEmpty) return null;
  final current = rates.where((rate) => rate.current).firstOrNull;
  if (current == null) return null;

  bool even(DisplayRate rate) {
    final refreshes = rate.refreshRate / fps;
    final whole = refreshes.round();
    return whole >= 1 && (refreshes - whole).abs() <= _evenCadence * whole;
  }

  if (even(current)) return null;

  final evens = rates.where(even).toList()..sort((a, b) => a.refreshRate.compareTo(b.refreshRate));
  if (evens.isNotEmpty) {
    final atLeastAsFast = evens.where((rate) => rate.refreshRate >= current.refreshRate).firstOrNull;
    return (atLeastAsFast ?? evens.last).id;
  }

  final fastest = rates.reduce((a, b) => a.refreshRate >= b.refreshRate ? a : b);
  return fastest.refreshRate > current.refreshRate ? fastest.id : null;
}

import 'dart:math' as math;

/// How far a remote's press moves the scrubber.
///
/// A tap is a nudge of a fixed few seconds, for placing a moment exactly. A
/// held direction travels: every repeat moves by the time since the last one
/// times a speed that climbs the longer the hold has lasted, so how fast the
/// remote repeats its key makes no difference - a stick repeating thirty
/// times a second and a box repeating ten cover the same ground in the same
/// second. Counting presses, as this used to, made the same hold twice as
/// fast on one remote as on another.
///
/// The speed is a share of the runtime, so a two-hour film and a twenty-minute
/// episode both cross in a hold of a few seconds, floored in seconds a second
/// so a short thing does not crawl. Pure: fed the clock, it hands back steps.
class ScrubRamp {
  /// One tap, and the first press of a hold.
  static const Duration tap = Duration(seconds: 5);

  /// How long a hold takes to reach full speed.
  static const Duration rampTime = Duration(seconds: 3);

  /// The share of the runtime crossed per second of holding, at the start of
  /// a hold and once it has run [rampTime].
  static const double slowFraction = 0.006;
  static const double fastFraction = 0.15;

  /// The least a hold moves per second, at the start and at full speed:
  /// shares of a short runtime are too little to feel.
  static const double slowFloorSeconds = 15;
  static const double fastFloorSeconds = 120;

  /// A repeat that arrives longer after the last than this is a new hold,
  /// whatever the event says: the remote lost a key-up.
  static const Duration holdGap = Duration(milliseconds: 400);

  /// What a repeat is charged for when the clock did not move between two of
  /// them - a platform whose key events carry no time.
  static const Duration assumedRepeatGap = Duration(milliseconds: 50);

  Duration? _holdStart;
  Duration? _lastPress;
  bool? _forward;

  /// Whether a hold is under way.
  bool get holding => _holdStart != null;

  /// How far the press at [now] moves, forward or back; [repeat] is whether
  /// the key reported itself as held rather than pressed afresh.
  Duration step({
    required bool forward,
    required bool repeat,
    required Duration now,
    required Duration total,
  }) {
    final last = _lastPress;
    final continues = repeat &&
        _holdStart != null &&
        _forward == forward &&
        last != null &&
        (now - last).abs() <= holdGap;

    if (!continues) {
      _holdStart = now;
      _lastPress = now;
      _forward = forward;
      return forward ? tap : -tap;
    }

    var gap = now - last;
    if (gap <= Duration.zero) gap = assumedRepeatGap;
    if (gap > holdGap) gap = holdGap;
    _lastPress = now;

    final held = now - _holdStart!;
    final progress = (held.inMicroseconds / rampTime.inMicroseconds).clamp(0.0, 1.0);
    // Eased in: the first second of a hold is close to the tap's pace, the
    // speed is found in the seconds after, and nothing lurches.
    final eased = progress * progress;
    final fraction = slowFraction + (fastFraction - slowFraction) * eased;
    final floor = slowFloorSeconds + (fastFloorSeconds - slowFloorSeconds) * eased;
    final secondsPerSecond = math.max(floor, total.inMilliseconds / 1000 * fraction);
    final seconds = secondsPerSecond * gap.inMicroseconds / Duration.microsecondsPerSecond;
    final moved = Duration(milliseconds: (seconds * 1000).round());
    return forward ? moved : -moved;
  }

  /// The hold is over: the next press is a tap again.
  void reset() {
    _holdStart = null;
    _lastPress = null;
    _forward = null;
  }
}

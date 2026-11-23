import 'package:chudder/util/background_priority_stub.dart'
    if (dart.library.ffi) 'package:chudder/util/background_priority_windows.dart' as impl;

/// How much of the machine Chudder asks Windows for.
enum ProcessStanding {
  /// In use: normal priority, the CPU at whatever speed Windows likes.
  normal,

  /// Not in use, but a film plays: below normal priority, so a game in front
  /// gets a core first, at full speed so the picture stays smooth.
  yielding,

  /// Not in use and nothing playing: below normal priority and efficiency
  /// mode (EcoQoS) - slow clocks and, where the CPU has them, efficient cores.
  resting,
}

ProcessStanding standingFor({required bool inUse, required bool playing}) {
  if (inUse) return ProcessStanding.normal;
  return playing ? ProcessStanding.yielding : ProcessStanding.resting;
}

ProcessStanding? _applied;

/// Tells Windows; does nothing elsewhere, or when nothing changed.
void applyProcessStanding(ProcessStanding standing) {
  if (_applied == standing) return;
  _applied = standing;
  impl.applyProcessStanding(standing.index);
}

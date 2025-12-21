// Stub for flutter_tizen package on non-Tizen platforms

/// Always returns false on non-Tizen platforms
bool get isTizen => false;

/// Tizen device profile
enum TizenProfile {
  common,
  mobile,
  wearable,
  tv,
  iot,
}

/// Returns common profile on non-Tizen platforms
TizenProfile get tizenProfile => TizenProfile.common;

/// Platform version (stub)
String get tizenVersion => '';

/// Device model name (stub)
String get deviceModelName => '';

/// Manufacturer (stub)
String get manufacturer => '';



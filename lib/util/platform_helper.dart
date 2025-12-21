import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tizen/flutter_tizen.dart' as tizen
    if (dart.library.html) 'package:fladder/stubs/tizen/flutter_tizen_stub.dart';

/// Platform detection helper for Tizen and other platforms
class PlatformHelper {
  static bool? _isTizenCached;

  static bool get isTizen {
    if (kIsWeb) return false;
    // Cache the result since it won't change during runtime
    _isTizenCached ??= _detectTizen();
    return _isTizenCached!;
  }

  static bool _detectTizen() {
    try {
      // Use flutter_tizen package for proper detection
      return tizen.isTizen;
    } catch (_) {
      // Fallback detection methods
      try {
        return Platform.environment.containsKey('TIZEN_SDK_VERSION') ||
            _isTizenOS();
      } catch (_) {
        return false;
      }
    }
  }

  static bool _isTizenOS() {
    if (kIsWeb) return false;
    try {
      // On Tizen, there's usually a /etc/tizen-release file
      final tizenRelease = File('/etc/tizen-release');
      return tizenRelease.existsSync();
    } catch (_) {
      return false;
    }
  }

  static bool get isTizenTV {
    if (!isTizen) return false;
    // Assume TV for Samsung TV target
    return true;
  }

  static bool get isDesktop {
    if (kIsWeb) return false;
    return [
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    ].contains(defaultTargetPlatform) && !isTizen;
  }

  static bool get isMobile {
    if (kIsWeb) return false;
    return [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ].contains(defaultTargetPlatform);
  }

  static bool get isTV {
    return isTizenTV; // Can be extended for Android TV later
  }

  static bool get supportsWindowManager {
    return isDesktop && !isTizen;
  }

  static bool get supportsLocalAuth {
    return isMobile;
  }

  static bool get supportsAudioService {
    return !isTizen && !kIsWeb;
  }

  static bool get supportsWakelock {
    return true; // Supported on Tizen via wakelock_plus_tizen
  }
}


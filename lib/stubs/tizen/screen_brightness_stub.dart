// Stub for screen_brightness on Tizen
// TV brightness is controlled by the TV itself

class ScreenBrightness {
  static ScreenBrightness get instance => ScreenBrightness._();
  ScreenBrightness._();

  Future<double> get current async => 1.0;
  Future<double> get system async => 1.0;
  Future<bool> get hasChanged async => false;

  Future<void> setScreenBrightness(double brightness) async {
    // No-op on Tizen TV
  }

  Future<void> resetScreenBrightness() async {
    // No-op on Tizen TV
  }

  Stream<double> get onCurrentBrightnessChanged => Stream.value(1.0);
}



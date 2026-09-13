import 'package:flutter/widgets.dart';

/// The web build has no benchmark mode.
class PerfBench {
  PerfBench._();

  static bool get active => false;

  static void startIfRequested(List<String> args) {}

  static Widget wrap(Widget child) => child;

  static Future<void> setUpWindow(String title) async {}
}

import 'dart:convert';
import 'dart:io';

/// The file the driver (tool/perf/perfbench.py) hands the app with
/// `--perf-bench=<path>`. Everything a run needs is in here: where its profile
/// lives, what to do, and where to write what happened.
class BenchConfig {
  BenchConfig(this.raw);

  factory BenchConfig.load(String path) =>
      BenchConfig(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);

  final Map<String, dynamic> raw;

  /// Every directory the app would otherwise ask Windows for lives under here.
  String get profileDir => raw['profile_dir'] as String;

  String get outputPath => raw['output'] as String;

  String get scenario => raw['scenario'] as String? ?? 'unnamed';

  /// Unix milliseconds the driver read just before starting the process
  /// (informational; the precise clock is [launchQpcMicros]).
  int? get launchUnixMs => (raw['launch_unix_ms'] as num?)?.toInt();

  /// QueryPerformanceCounter microseconds the driver read just before starting
  /// the process. Dart's monotonic clock on Windows reads the same counter.
  int? launchQpcMicros;

  /// The window in physical pixels: where it goes, and the size of its client
  /// area in logical pixels.
  int get windowX => (raw['window']?['x'] as num?)?.toInt() ?? 3000;
  int get windowY => (raw['window']?['y'] as num?)?.toInt() ?? 100;
  double get windowWidth => (raw['window']?['width'] as num?)?.toDouble() ?? 1400;
  double get windowHeight => (raw['window']?['height'] as num?)?.toDouble() ?? 900;

  Duration get quiet => Duration(milliseconds: (raw['quiet_ms'] as num?)?.toInt() ?? 450);

  Duration get stepTimeout => Duration(milliseconds: (raw['step_timeout_ms'] as num?)?.toInt() ?? 30000);

  /// Widget type names that mean "something is still on its way", on top of
  /// every indeterminate [ProgressIndicator].
  Set<String> get loadingWidgets =>
      ((raw['loading_widgets'] as List?) ?? const ['Shimmer', 'ShimmerPosterRow']).cast<String>().toSet();

  /// Requests sent somewhere harmless instead: `{method, path_regex, to}`.
  /// Playback reports would otherwise move the demo account's resume points.
  List<Map<String, dynamic>> get rewrites => ((raw['rewrite_requests'] as List?) ?? const []).cast();

  /// Saves an image of the window at the detected ready moment and 1500 ms
  /// later, to check the detector by eye.
  String? get screenshotDir => raw['screenshot_dir'] as String?;

  double get screenshotScale => (raw['screenshot_scale'] as num?)?.toDouble() ?? 0.5;

  int get exitDelayMs => (raw['exit_delay_ms'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get steps => ((raw['steps'] as List?) ?? const []).cast();

  /// Values the template run signs in with. Never written to the output.
  Map<String, dynamic>? get login => raw['login'] as Map<String, dynamic>?;
}

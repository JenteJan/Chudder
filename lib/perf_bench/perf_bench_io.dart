import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:chudder/perf_bench/bench_binding.dart';
import 'package:chudder/perf_bench/bench_config.dart';
import 'package:chudder/perf_bench/bench_http.dart';
import 'package:chudder/perf_bench/bench_paths.dart';
import 'package:chudder/perf_bench/bench_steps.dart';
import 'package:chudder/perf_bench/capture.dart';
import 'package:chudder/perf_bench/readiness.dart';

/// Benchmark mode: a run of scripted steps inside the app, timed from the
/// inside, written to a JSON file, and then the process exits.
///
/// Started only by `--perf-bench=<config.json>`. Without it none of this is
/// constructed: the stock binding, no overrides, no timers, no listeners.
class PerfBench {
  PerfBench._(this.config, this.mainUs, this.mainWallMs);

  static PerfBench? _instance;
  static PerfBench? get instance => _instance;
  static bool get active => _instance != null;

  final BenchConfig config;
  final int mainUs;
  final int mainWallMs;
  late final BenchBinding binding;
  final BenchHttpTracker http = BenchHttpTracker();
  late final BenchCapture? capture =
      config.screenshotDir == null ? null : BenchCapture(config.screenshotScale);

  static void startIfRequested(List<String> args) {
    final arg = args.where((a) => a.startsWith('--perf-bench=')).firstOrNull;
    if (arg == null) return;
    final mainUs = Timeline.now;
    final mainWallMs = DateTime.now().millisecondsSinceEpoch;
    final config = BenchConfig.load(arg.substring('--perf-bench='.length));
    final launch = args.where((a) => a.startsWith('--perf-launch-us=')).firstOrNull;
    config.launchQpcMicros = launch == null ? null : int.tryParse(launch.substring('--perf-launch-us='.length));
    final bench = PerfBench._(config, mainUs, mainWallMs);
    _instance = bench;
    bench.binding = BenchBinding.ensureInitialized();
    // A focused field's cursor blinks on a timer, and every blink is a repaint
    // nothing else asked for: it would keep a step on the search page from
    // ever being still. It stays lit instead.
    EditableText.debugDeterministicCursor = true;
    installBenchPaths(config.profileDir);
    HttpOverrides.global = BenchHttpOverrides(bench.http, config.rewrites);
  }

  static Widget wrap(Widget child) {
    final bench = _instance;
    if (bench == null) return child;
    return _BenchHost(bench: bench, child: child);
  }

  /// In place of showing, centring and focusing the window: size its client
  /// area to the configured logical size and leave it where the runner put
  /// it, off the screens and never activated (windows/runner/main.cpp).
  static Future<void> setUpWindow(String title) async {
    final bench = _instance!;
    final config = bench.config;
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
        skipTaskbar: true,
        title: '$title (benchmark)',
      ),
      () async {
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        var dpr = view.devicePixelRatio;
        // The hidden title bar leaves 8 physical pixels of frame at each side
        // and the bottom (window_manager's WM_NCCALCSIZE handling).
        var width = config.windowWidth + 16 / dpr;
        var height = config.windowHeight + 8 / dpr;
        await windowManager.setBounds(Rect.fromLTWH(config.windowX / dpr, config.windowY / dpr, width, height));
        for (var attempt = 0; attempt < 3; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          dpr = view.devicePixelRatio;
          final size = view.physicalSize / dpr;
          final dw = config.windowWidth - size.width;
          final dh = config.windowHeight - size.height;
          if (dw.abs() < 0.5 && dh.abs() < 0.5) break;
          width += dw;
          height += dh;
          await windowManager.setBounds(Rect.fromLTWH(config.windowX / dpr, config.windowY / dpr, width, height));
        }
      },
    );
  }

  int get launchUs => config.launchQpcMicros ?? mainUs;

  double ms(int us, int fromUs) => ((us - fromUs) / 100).round() / 10;

  Map<String, dynamic> requestsBetween(int startUs, int endUs, {bool list = true}) {
    final inWindow = http.requests.where((r) => r.startUs >= startUs && r.startUs <= endUs).toList();
    return {
      'requests': inWindow.length,
      'response_bytes': inWindow.fold<int>(0, (sum, r) => sum + r.bytes),
      if (list)
        'request_list': [
          for (final r in inWindow)
            {
              'method': r.method,
              'path': r.path,
              'status': r.status,
              'start_ms': ms(r.startUs, startUs),
              'end_ms': r.endUs == null ? null : ms(r.endUs!, startUs),
              'bytes': r.bytes,
              if (r.rewrittenFrom != null) 'rewritten_from': r.rewrittenFrom,
              if (r.websocket) 'websocket': true,
              if (r.error != null) 'error': r.error,
            },
        ],
    };
  }

  ReadinessDetector detector({Duration? timeout}) => ReadinessDetector(
        binding: binding,
        http: http,
        quiet: config.quiet,
        timeout: timeout ?? config.stepTimeout,
        loadingWidgets: config.loadingWidgets,
      );
}

class _BenchHost extends ConsumerStatefulWidget {
  const _BenchHost({required this.bench, required this.child});

  final PerfBench bench;
  final Widget child;

  @override
  ConsumerState<_BenchHost> createState() => _BenchHostState();
}

class _BenchHostState extends ConsumerState<_BenchHost> {
  PerfBench get bench => widget.bench;
  final List<Map<String, dynamic>> _results = [];
  final Map<String, dynamic> _output = {};

  /// While screenshots are on: the picture of the latest content frame, which
  /// is the picture at the ready moment once the step is done.
  ui.Image? _lastContentImage;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    if (bench.capture != null) bench.binding.frameListeners.add(_onFrame);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  bool _captureAgain = false;

  void _onFrame(BenchFrame frame) {
    if (!frame.content) return;
    if (_capturing) {
      // Still reading the last one back: take another when it is done, so the
      // newest content frame is never the one missed.
      _captureAgain = true;
      return;
    }
    _capturing = true;
    bench.capture!.capture().then((image) {
      _capturing = false;
      if (image != null) {
        _lastContentImage?.dispose();
        _lastContentImage = image;
      }
      if (_captureAgain) {
        _captureAgain = false;
        _onFrame(frame);
      }
    });
  }

  Future<void> _run() async {
    final runner = BenchStepRunner(bench: bench, ref: ref, context: context);
    _output['scenario'] = bench.config.scenario;
    _output['launch_unix_ms'] = bench.config.launchUnixMs;
    _output['main_wall_ms'] = bench.mainWallMs;
    _output['startup'] = {
      'main_ms': bench.config.launchQpcMicros == null ? null : bench.ms(bench.mainUs, bench.launchUs),
    };
    var failed = false;
    try {
      for (final (index, step) in bench.config.steps.indexed) {
        final result = await _runStep(runner, index, step);
        if (result != null) _results.add(result);
        if (result?['fatal'] == true) {
          failed = true;
          break;
        }
      }
    } catch (e, stack) {
      failed = true;
      _output['error'] = '$e\n$stack';
    }
    _finish(failed);
  }

  Future<Map<String, dynamic>?> _runStep(BenchStepRunner runner, int index, Map<String, dynamic> step) async {
    final action = step['action'] as String;
    final name = step['name'] as String? ?? '$index-$action';
    final measure = step['measure'] as bool? ?? true;

    // Every step after the launch starts from a quiet app, so nothing the
    // previous one left running is counted against this one.
    if (action != 'launch' && action != 'sleep') {
      await bench.detector(timeout: const Duration(seconds: 20)).waitUntilReady(Timeline.now);
    }

    final prepared = await runner.prepare(step);
    if (prepared.error != null) {
      return {'name': name, 'action': action, 'error': prepared.error, 'fatal': true};
    }

    final int startUs;
    if (action == 'launch') {
      startUs = bench.launchUs;
    } else {
      startUs = Timeline.now;
    }
    final performed = await prepared.perform();
    if (performed.error != null) {
      return {'name': name, 'action': action, 'error': performed.error, 'fatal': true};
    }
    if (performed.readyUs != null || performed.detectedUs != null) {
      // A step with a readiness signal of its own (the player).
      final end = performed.detectedUs ?? Timeline.now;
      return {
        'name': name,
        'action': action,
        'measured': measure,
        'ready_ms': performed.readyUs == null ? null : bench.ms(performed.readyUs!, startUs),
        'timed_out': performed.readyUs == null,
        ...performed.extra.map((k, v) => MapEntry(k, v is int ? bench.ms(v, startUs) : v)),
        ...bench.requestsBetween(startUs, end),
      };
    }
    if (!measure && step['wait'] == false) return null;

    final result = await bench.detector().waitUntilReady(
          performed.measureFromUs ?? startUs,
          condition: performed.condition,
        );
    final from = performed.measureFromUs ?? startUs;
    final out = <String, dynamic>{
      'name': name,
      'action': action,
      'measured': measure,
      'ready_ms': bench.ms(result.readyUs, from),
      'first_frame_ms': result.firstFrameUs == null ? null : bench.ms(result.firstFrameUs!, from),
      'detected_ms': bench.ms(result.detectedUs, from),
      'ready_source': result.readySource,
      'timed_out': result.timedOut,
      if (result.timedOut) 'waiting_on': result.waitingOn,
      'route': runner.topRouteName,
      'frames': result.frames,
      'content_frames': result.contentFrames,
      'images_loaded': result.imagesLoaded,
      if (result.imagesFailed > 0) 'images_failed': result.imagesFailed,
      ...performed.extra.map((k, v) => MapEntry(k, v is int ? bench.ms(v, from) : v)),
      ...bench.requestsBetween(from, result.detectedUs, list: step['list_requests'] as bool? ?? true),
    };
    if (bench.capture != null && measure) {
      await _screenshots(name, index, result, out);
    }
    return out;
  }

  Future<void> _screenshots(String name, int index, ReadinessResult result, Map<String, dynamic> out) async {
    final dir = Directory(bench.config.screenshotDir!)..createSync(recursive: true);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final atReady = _lastContentImage;
    _lastContentImage = null;
    // 1500 ms after the ready moment, however long detection took.
    final laterUs = result.readyUs + 1500000;
    final waitUs = laterUs - Timeline.now;
    if (waitUs > 0) await Future<void>.delayed(Duration(microseconds: waitUs));
    final later = await bench.capture!.capture();
    final base = '${dir.path}${Platform.pathSeparator}${bench.config.scenario}-$index-$safe';
    if (atReady != null) {
      await BenchCapture.savePng(atReady, '$base-ready.png');
      out['screenshot_ready'] = '$base-ready.png';
    }
    if (later != null) {
      await BenchCapture.savePng(later, '$base-later.png');
      out['screenshot_later'] = '$base-later.png';
    }
    if (atReady != null && later != null) {
      out['screenshot_difference'] = await BenchCapture.difference(atReady, later);
    }
    atReady?.dispose();
    later?.dispose();
  }

  void _finish(bool failed) {
    final frames = bench.binding.frames;
    final firstRaster = frames.where((f) => f.rasterFinishUs != null).firstOrNull;
    (_output['startup'] as Map<String, dynamic>)['first_frame_ms'] =
        firstRaster == null || bench.config.launchQpcMicros == null ? null : bench.ms(firstRaster.rasterFinishUs!, bench.launchUs);
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    _output['view'] = {
      'width': view.physicalSize.width / view.devicePixelRatio,
      'height': view.physicalSize.height / view.devicePixelRatio,
      'device_pixel_ratio': view.devicePixelRatio,
    };
    _output['frame_pacing'] = _framePacing(frames);
    _output['steps'] = _results;
    _output['outside_profile_paths'] = outsideProfilePaths.toList();
    _output['server_socket_binds'] = serverSocketBinds;
    _output['ok'] = !failed && _results.every((r) => r['timed_out'] != true && r['error'] == null);
    final file = File(bench.config.outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(_output), flush: true);
    Future<void>.delayed(Duration(milliseconds: bench.config.exitDelayMs), () => exit(failed ? 3 : 0));
  }

  /// How evenly frames came while something was animating: the gaps between
  /// consecutive frames closer than 100 ms, and the raster time. A window the
  /// system throttles shows up here as long gaps.
  Map<String, dynamic> _framePacing(List<BenchFrame> frames) {
    final gaps = <int>[];
    final raster = <int>[];
    for (var i = 1; i < frames.length; i++) {
      final a = frames[i - 1].buildStartUs;
      final b = frames[i].buildStartUs;
      if (a != null && b != null && b - a < 100000) gaps.add(b - a);
      if (frames[i].rasterFinishUs != null && b != null) raster.add(frames[i].rasterFinishUs! - b);
    }
    double? p(List<int> values, double q) {
      if (values.isEmpty) return null;
      final sorted = [...values]..sort();
      return sorted[((sorted.length - 1) * q).round()] / 1000;
    }

    return {
      'frames': frames.length,
      'content_frames': frames.where((f) => f.content).length,
      'gap_ms_p50': p(gaps, 0.5),
      'gap_ms_p90': p(gaps, 0.9),
      'build_to_raster_ms_p50': p(raster, 0.5),
      'build_to_raster_ms_p90': p(raster, 0.9),
      'frames_without_timing': frames.where((f) => f.rasterFinishUs == null).length,
      'unmatched_timings': bench.binding.unmatchedTimings,
      'unmatched_deltas_us': bench.binding.unmatchedDeltas,
    };
  }

  @override
  Widget build(BuildContext context) {
    final capture = bench.capture;
    if (capture == null) return widget.child;
    return RepaintBoundary(key: capture.boundaryKey, child: widget.child);
  }
}

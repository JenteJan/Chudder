import 'dart:developer';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// One frame the framework began, as the readiness detector sees it.
class BenchFrame {
  BenchFrame(this.beginUs, this.content, this.animations, this.animationsChanged);

  /// [Timeline.now] as the frame began - the same clock, and within a few
  /// hundred microseconds of the moment, the engine stamps as its build start.
  final int beginUs;
  int? endUs;

  /// Whether something other than a running animation asked for this frame: a
  /// setState from a response, an image arriving, a scroll, a navigation - or
  /// an animation finishing on it. Frames that only move an animation along
  /// (a spinner turning, a shimmer sweeping) are not content.
  final bool content;

  /// Running animations (transient frame callbacks) after this frame, and
  /// whether that number differs from the frame before: an animation started
  /// or stopped here.
  final int animations;
  final bool animationsChanged;

  /// From the engine's [FrameTiming], once it has been reported.
  int? rasterFinishUs;
  int? buildStartUs;
}

/// The app's binding with the few hooks the benchmark needs. Only ever
/// installed with `--perf-bench`; a normal launch gets the stock binding.
class BenchBinding extends WidgetsFlutterBinding {
  static BenchBinding? _instance;

  static BenchBinding ensureInitialized() {
    if (_instance == null) BenchBinding();
    return _instance!;
  }

  @override
  void initInstances() {
    super.initInstances();
    _instance = this;
    addTimingsCallback(_onTimings);
  }

  final List<BenchFrame> frames = [];
  final BenchImageTracker images = BenchImageTracker();
  bool _contentRequested = false;
  final List<void Function(BenchFrame frame)> frameListeners = [];

  /// Timings that arrived before their frame could be matched (they never do,
  /// but the engine batches them, so matching is by time rather than order).
  int _nextUnmatched = 0;

  void _noteRequest() {
    final phase = schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      _contentRequested = true;
    }
  }

  @override
  void scheduleFrame() {
    _noteRequest();
    super.scheduleFrame();
  }

  @override
  void scheduleForcedFrame() {
    _noteRequest();
    super.scheduleForcedFrame();
  }

  @override
  void scheduleWarmUpFrame() {
    _contentRequested = true;
    super.scheduleWarmUpFrame();
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    final beginUs = Timeline.now;
    final before = transientCallbackCount;
    final requested = _contentRequested;
    _contentRequested = false;
    super.handleBeginFrame(rawTimeStamp);
    // An animation that did not ask for another tick has just drawn its last
    // value: the frame that finishes a fade or a page transition is content.
    final after = transientCallbackCount;
    final finished = after < before;
    final previous = frames.isEmpty ? 0 : frames.last.animations;
    frames.add(BenchFrame(beginUs, requested || finished, after, after != previous));
  }

  @override
  void handleDrawFrame() {
    super.handleDrawFrame();
    if (frames.isEmpty) return;
    final frame = frames.last;
    frame.endUs = Timeline.now;
    for (final listener in List.of(frameListeners)) {
      listener(frame);
    }
  }

  /// Engine timings that matched no frame, for the output's diagnostics.
  int unmatchedTimings = 0;
  final List<int> unmatchedDeltas = [];

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildStart = timing.timestampInMicroseconds(FramePhase.buildStart);
      var matched = false;
      // The frame whose Dart-side begin is closest after the engine's build
      // start; frames are few enough that a short scan from the last match is
      // cheap.
      for (var i = _nextUnmatched; i < frames.length; i++) {
        final delta = frames[i].beginUs - buildStart;
        if (delta < -2000) continue;
        if (delta > 20000) break;
        frames[i].rasterFinishUs = timing.timestampInMicroseconds(FramePhase.rasterFinish);
        frames[i].buildStartUs = buildStart;
        _nextUnmatched = i + 1;
        matched = true;
        break;
      }
      if (!matched) {
        unmatchedTimings++;
        if (unmatchedDeltas.length < 20 && _nextUnmatched < frames.length) {
          unmatchedDeltas.add(frames[_nextUnmatched].beginUs - buildStart);
        }
      }
    }
  }

  @override
  ImageCache createImageCache() => _BenchImageCache(images);
}

/// Images the image cache was asked to load and has not produced yet.
class BenchImageTracker {
  int started = 0;
  int completed = 0;
  int failed = 0;
  int lastEventUs = 0;

  int get pending => started - completed - failed;
}

class _BenchImageCache extends ImageCache {
  _BenchImageCache(this.tracker);

  final BenchImageTracker tracker;

  @override
  ImageStreamCompleter? putIfAbsent(Object key, ImageStreamCompleter Function() loader,
      {ImageErrorListener? onError}) {
    var created = false;
    final completer = super.putIfAbsent(key, () {
      created = true;
      return loader();
    }, onError: onError);
    if (created && completer != null) {
      tracker.started++;
      tracker.lastEventUs = Timeline.now;
      late final ImageStreamListener listener;
      var done = false;
      void finish(bool ok) {
        if (done) return;
        done = true;
        if (ok) {
          tracker.completed++;
        } else {
          tracker.failed++;
        }
        tracker.lastEventUs = Timeline.now;
        // After this frame of the listener list has been walked.
        Future.microtask(() => completer.removeListener(listener));
      }

      listener = ImageStreamListener(
        (_, __) => finish(true),
        onError: (_, __) => finish(false),
      );
      completer.addListener(listener);
    }
    return completer;
  }
}

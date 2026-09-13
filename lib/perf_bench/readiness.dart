import 'dart:async';
import 'dart:developer';

import 'package:chudder/perf_bench/bench_binding.dart';
import 'package:chudder/perf_bench/bench_http.dart';
import 'package:chudder/perf_bench/loading_indicators.dart';

/// What a step is waiting for beyond "nothing is changing any more".
typedef ReadyCondition = String? Function();

class ReadinessResult {
  ReadinessResult({
    required this.startUs,
    required this.detectedUs,
    required this.readyUs,
    required this.firstFrameUs,
    required this.lastContentFrame,
    required this.timedOut,
    required this.waitingOn,
    required this.contentFrames,
    required this.frames,
    required this.imagesLoaded,
    required this.imagesFailed,
    required this.readySource,
  });

  final int startUs;
  final int detectedUs;
  final int readyUs;
  final int? firstFrameUs;
  final BenchFrame? lastContentFrame;
  final bool timedOut;
  final List<String> waitingOn;
  final int contentFrames;
  final int frames;
  final int imagesLoaded;
  final int imagesFailed;
  final String readySource;
}

/// Decides when a step is visually complete.
///
/// A step is complete at the raster finish of the last content frame (see
/// [BenchFrame.content]) once all of this has held for [quiet]:
///  * no content frame,
///  * no request in flight and none finishing,
///  * no image the image cache is still loading or decoding,
///  * any condition of the step's own (the route it should be on, a player
///    that should be playing),
/// and, at the end of that window, no indeterminate progress indicator or
/// placeholder is visible. Animations that never end (a spinner turning, a
/// shimmer) do not keep a step open, but a visible one keeps it from being
/// done; it is reported if the step times out on it.
class ReadinessDetector {
  ReadinessDetector({
    required this.binding,
    required this.http,
    required this.quiet,
    required this.timeout,
    required this.loadingWidgets,
  });

  final BenchBinding binding;
  final BenchHttpTracker http;
  final Duration quiet;
  final Duration timeout;
  final Set<String> loadingWidgets;

  /// Frames are raster-stamped by the engine in batches (about once a second
  /// in release); a result waits this long at most for its frame's stamp.
  static const _timingWait = Duration(milliseconds: 2500);

  /// Animations that have run this long without one starting or stopping are
  /// taken to be endless (and left to the loading-indicator check).
  static const endlessAnimation = Duration(milliseconds: 2000);

  Future<ReadinessResult> waitUntilReady(int startUs, {ReadyCondition? condition, int? imagesAtStart}) async {
    final images = binding.images;
    final imagesStarted = imagesAtStart ?? images.completed + images.failed;
    final imagesFailedAtStart = images.failed;
    // Frames are only ever appended: everything from here on is this step's
    // (the launch step starts before the first frame, so it gets them all).
    final initialIndex = binding.frames.indexWhere((f) => f.beginUs >= startUs);
    final frameBase = initialIndex < 0 ? binding.frames.length : initialIndex;
    final quietUs = quiet.inMicroseconds;
    final deadlineUs = startUs + timeout.inMicroseconds;

    var waitingOn = <String>[];
    var lastIndicatorCheckUs = 0;
    var lastIndicatorFrames = -1;
    var timedOut = false;
    int detectedUs;

    BenchFrame? lastAnimationChange() {
      for (var i = binding.frames.length - 1; i >= frameBase; i--) {
        final frame = binding.frames[i];
        if (frame.animationsChanged && frame.beginUs >= startUs) return frame;
      }
      return null;
    }

    BenchFrame? lastContent() {
      for (var i = binding.frames.length - 1; i >= frameBase; i--) {
        final frame = binding.frames[i];
        if (frame.content && frame.beginUs >= startUs) return frame;
      }
      return null;
    }

    while (true) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final now = Timeline.now;
      if (now > deadlineUs) {
        timedOut = true;
        detectedUs = now;
        break;
      }
      waitingOn = [];
      final inFlight = http.requests.where((r) => r.inFlight).toList();
      if (inFlight.isNotEmpty) {
        waitingOn.addAll(inFlight.take(5).map((r) => 'request ${r.method} ${r.path}'));
      }
      if (images.pending > 0) waitingOn.add('images ${images.pending}');
      final conditionReason = condition?.call();
      if (conditionReason != null) waitingOn.add(conditionReason);
      if (waitingOn.isNotEmpty) continue;

      final content = lastContent();
      final changed = lastAnimationChange();
      final lastActivity = [
        startUs,
        content?.endUs ?? content?.beginUs ?? 0,
        changed?.endUs ?? changed?.beginUs ?? 0,
        http.lastEventUs,
        images.lastEventUs,
      ].reduce((a, b) => a > b ? a : b);
      if (now - lastActivity < quietUs) {
        waitingOn.add('quiet');
        continue;
      }
      // Animations still running: a fade or a page transition that will end
      // (and whose last frame is content), unless they have run unchanged for
      // so long that they are the kind that never ends - a spinner, a shimmer.
      final animations = binding.frames.isEmpty ? 0 : binding.frames.last.animations;
      if (animations > 0 && now - lastActivity < endlessAnimation.inMicroseconds) {
        waitingOn.add('animations $animations');
        continue;
      }

      // The element walk is the only expensive check: only when something
      // changed since the last one, or every half second while a spinner is
      // the one thing left.
      final frameCount = binding.frames.length;
      if (frameCount != lastIndicatorFrames || now - lastIndicatorCheckUs > 500000) {
        lastIndicatorCheckUs = now;
        lastIndicatorFrames = frameCount;
        final indicators = visibleLoadingIndicators(loadingWidgets);
        if (indicators.isNotEmpty) {
          waitingOn.addAll(indicators.map((name) => 'visible $name'));
          // Keep the last reason for a timeout report.
          _lastIndicators = indicators;
          continue;
        }
        _lastIndicators = const [];
      } else if (_lastIndicators.isNotEmpty) {
        waitingOn.addAll(_lastIndicators.map((name) => 'visible $name'));
        continue;
      }
      detectedUs = now;
      break;
    }

    final content = lastContent();
    final firstFrameIndex = binding.frames.indexWhere((f) => f.beginUs >= startUs, frameBase);
    final firstFrame = firstFrameIndex < 0 ? null : binding.frames[firstFrameIndex];
    // Wait for the engine to report the raster times of the frames we use.
    final waitUntil = Timeline.now + _timingWait.inMicroseconds;
    while ((content != null && content.rasterFinishUs == null) || (firstFrame != null && firstFrame.rasterFinishUs == null)) {
      if (Timeline.now > waitUntil) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final framesInStep = binding.frames.sublist(frameBase);
    return ReadinessResult(
      startUs: startUs,
      detectedUs: detectedUs,
      readyUs: content == null ? startUs : (content.rasterFinishUs ?? content.endUs ?? content.beginUs),
      readySource: content == null ? 'no-content-frame' : (content.rasterFinishUs != null ? 'raster' : 'dart-frame-end'),
      firstFrameUs: firstFrame?.rasterFinishUs ?? firstFrame?.endUs,
      lastContentFrame: content,
      timedOut: timedOut,
      waitingOn: timedOut ? waitingOn : const [],
      contentFrames: framesInStep.where((f) => f.content && f.beginUs <= detectedUs).length,
      frames: framesInStep.where((f) => f.beginUs <= detectedUs).length,
      imagesLoaded: images.completed + images.failed - imagesStarted,
      imagesFailed: images.failed - imagesFailedAtStart,
    );
  }

  List<String> _lastIndicators = const [];
}

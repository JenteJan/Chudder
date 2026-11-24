import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:chudder/models/settings/client_settings_model.dart';
import 'package:chudder/perf_bench/perf_bench.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/util/system_memory.dart';

final _log = Logger('LowMemory');

/// What the app gives up while memory is short.
enum LowMemoryPart {
  /// The artwork cache emptied when the player opens and when the app goes
  /// to the background: nothing of it is on screen then.
  releaseImages,

  /// The banner's words over the picture with their shadow only, without the
  /// blurred copy of the picture behind them.
  bannerBlur,
}

class LowMemoryState {
  const LowMemoryState({this.active = false, this.parts = const {...LowMemoryPart.values}});

  /// Whether the app is saving memory now.
  final bool active;

  /// What it gives up when it is.
  final Set<LowMemoryPart> parts;

  bool uses(LowMemoryPart part) => active && parts.contains(part);

  @override
  bool operator ==(Object other) =>
      other is LowMemoryState &&
      other.active == active &&
      other.parts.length == parts.length &&
      other.parts.containsAll(parts);

  @override
  int get hashCode => Object.hash(active, Object.hashAllUnordered(parts));
}

final lowMemoryProvider = NotifierProvider<LowMemoryNotifier, LowMemoryState>(LowMemoryNotifier.new);

/// Whether memory is short, by the setting: always, never, or - on auto -
/// when the machine says so.
///
/// "Says so" is the system's own warning where there is one (Android, iOS
/// and macOS send didHaveMemoryPressure) and, where memory can be read
/// (Windows, Android, Linux), free memory below an eighth of it or below a
/// gigabyte. It ends once a fifth and a gigabyte and a half are free again,
/// and not before five minutes after the last warning: a mode that came and
/// went with every reading would throw away what it had just loaded back.
class LowMemoryNotifier extends Notifier<LowMemoryState> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 10);
  static const _warningHolds = Duration(minutes: 5);

  static const _enterShare = 0.125;
  static const _enterBytes = 1 << 30;
  static const _leaveShare = 0.20;
  static const _leaveBytes = 3 << 29;

  Timer? _poll;
  DateTime? _warnedAt;
  bool _short = false;

  @override
  LowMemoryState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _poll?.cancel();
    });

    ref.listen(isVideoPlayerRouteOpenProvider, (_, open) {
      if (open) _releaseImages('player opened');
    });
    listenSelf((previous, next) {
      if (previous?.active != next.active) _log.info('Low memory mode ${next.active ? 'on' : 'off'}');
    });

    return _decide();
  }

  LowMemoryState _decide() {
    // A benchmark run names what it wants on, so each part can be measured
    // by itself; an empty list is the mode off.
    final benchParts = PerfBench.lowMemoryParts;
    if (benchParts != null) {
      return LowMemoryState(
        active: benchParts.isNotEmpty,
        parts: {for (final name in benchParts) LowMemoryPart.values.byName(name)},
      );
    }

    final mode = ref.watch(clientSettingsProvider.select((value) => value.lowMemoryMode));
    _poll?.cancel();
    _poll = null;
    switch (mode) {
      case LowMemoryMode.on:
        return const LowMemoryState(active: true);
      case LowMemoryMode.off:
        return const LowMemoryState();
      case LowMemoryMode.auto:
        if (SystemMemory.supported) {
          _poll = Timer.periodic(_pollEvery, (_) => _check());
          _short = _isShort(SystemMemory.read());
        }
        return LowMemoryState(active: _short || _warningHolding);
    }
  }

  bool get _warningHolding => _warnedAt != null && DateTime.now().difference(_warnedAt!) < _warningHolds;

  bool _isShort(SystemMemory? memory) {
    if (memory == null) return false;
    final free = memory.availableBytes;
    if (_short) return !(free > _leaveBytes && memory.availableShare > _leaveShare);
    return free < _enterBytes || memory.availableShare < _enterShare;
  }

  void _check() {
    _short = _isShort(SystemMemory.read());
    _update();
  }

  void _update() {
    final mode = ref.read(clientSettingsProvider).lowMemoryMode;
    if (mode != LowMemoryMode.auto || PerfBench.lowMemoryParts != null) return;
    final active = _short || _warningHolding;
    if (active != state.active) state = LowMemoryState(active: active, parts: state.parts);
  }

  @override
  void didHaveMemoryPressure() {
    _warnedAt = DateTime.now();
    _update();
    _releaseImages('system warning');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _releaseImages('app in the background');
    }
  }

  /// Empties the decoded artwork no picture on screen holds: what the user
  /// sees stays, scrolling back decodes again from disk.
  void _releaseImages(String why) {
    if (!state.uses(LowMemoryPart.releaseImages)) return;
    final cache = PaintingBinding.instance.imageCache;
    _log.info('Letting go of ${cache.currentSizeBytes >> 20} MB of artwork: $why');
    cache.clear();
  }
}

import 'dart:async';
import 'dart:developer';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';

/// Service for synchronizing client clock with Jellyfin server using NTP-like algorithm
class TimeSyncService {
  TimeSyncService(this._api);

  final JellyfinOpenApi _api;

  final List<TimeSyncMeasurement> _measurements = [];
  static const int _maxMeasurements = 8;

  /// Invoked after each successful measurement (offset/ping refreshed). Used by
  /// the controller to forward the freshly measured ping to the server, which
  /// pads the group's scheduled start time by the highest reported ping.
  void Function()? onMeasurement;

  Timer? _pollingTimer;
  int _pingCount = 0;
  bool _isActive = false;

  // Polling intervals
  static const Duration _greedyInterval = Duration(seconds: 1);
  // Steady-state poll cadence. Kept well below the 60 s the official client
  // uses: on a jittery WAN link the clock offset wanders, and a stale offset
  // makes SyncPlay perceive drift that isn't there and over-correct. Re-probing
  // every 20 s is still negligible traffic (one small GET) but tracks the link.
  static const Duration _lowProfileInterval = Duration(seconds: 20);
  static const int _greedyPingCount = 3;

  // Staleness threshold
  static const Duration _staleThreshold = Duration(seconds: 30);
  DateTime? _lastMeasurementTime;

  /// Current best offset estimate
  Duration get offset {
    if (_measurements.isEmpty) {
      return Duration.zero;
    }
    // Use measurement with minimum delay (least network jitter)
    final best = _measurements.reduce(
      (a, b) => a.delay < b.delay ? a : b,
    );
    return best.offset;
  }

  /// Current ping estimate (from best measurement)
  Duration get ping {
    if (_measurements.isEmpty) {
      return Duration.zero;
    }
    final best = _measurements.reduce(
      (a, b) => a.delay < b.delay ? a : b,
    );
    return best.ping;
  }

  /// Estimated uncertainty of the current [offset], expressed as half the
  /// peak-to-peak spread of the offsets we've measured recently. On a stable
  /// link the measured offsets cluster tightly (low jitter); on a jittery WAN
  /// they scatter, and that scatter is exactly how far our single best-offset
  /// estimate might be wrong. SyncPlay uses `ping + jitter` as the band within
  /// which reported drift is untrustworthy and should not be corrected.
  Duration get jitter {
    if (_measurements.length < 2) {
      return Duration.zero;
    }
    var minOffsetMs = _measurements.first.offset.inMilliseconds;
    var maxOffsetMs = minOffsetMs;
    for (final m in _measurements) {
      final offsetMs = m.offset.inMilliseconds;
      if (offsetMs < minOffsetMs) minOffsetMs = offsetMs;
      if (offsetMs > maxOffsetMs) maxOffsetMs = offsetMs;
    }
    return Duration(milliseconds: (maxOffsetMs - minOffsetMs) ~/ 2);
  }

  /// Whether time sync is stale and needs refresh
  bool get isStale {
    if (_lastMeasurementTime == null) {
      return true;
    }
    return DateTime.now().difference(_lastMeasurementTime!) > _staleThreshold;
  }

  /// Manual clock trim added on top of the measured [offset], set from the
  /// user's SyncPlay settings. Lets a viewer whose playback consistently sits
  /// ahead of / behind the group nudge themselves back into alignment.
  Duration extraOffset = Duration.zero;

  /// Measured offset plus the user's manual trim.
  Duration get _effectiveOffset => offset + extraOffset;

  /// Convert server time to local time
  DateTime remoteDateToLocal(DateTime serverTime) {
    return serverTime.subtract(_effectiveOffset);
  }

  /// Convert local time to server time
  DateTime localDateToRemote(DateTime localTime) {
    return localTime.add(_effectiveOffset);
  }

  /// Start time synchronization
  void start() {
    if (_isActive) {
      return;
    }
    _isActive = true;
    _pingCount = 0;
    _poll();
  }

  /// Stop time synchronization
  void stop() {
    _isActive = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Force an immediate sync update
  Future<void> forceUpdate() async {
    await _requestPing();
  }

  /// Force update and wait for completion
  Future<void> forceUpdateAndWait() async {
    await _requestPing();
  }

  void _poll() {
    if (!_isActive) {
      return;
    }

    _requestPing().then((_) {
      if (!_isActive) {
        return;
      }

      _pingCount++;
      final interval = _pingCount <= _greedyPingCount ? _greedyInterval : _lowProfileInterval;

      _pollingTimer?.cancel();
      _pollingTimer = Timer(interval, _poll);
    });
  }

  Future<void> _requestPing() async {
    try {
      // T1: Record local time before request
      final requestSent = DateTime.now().toUtc();

      // Make request to Jellyfin TimeSync API
      final response = await _api.getUtcTimeGet();

      // T4: Record local time after response
      final responseReceived = DateTime.now().toUtc();

      final data = response.body;
      if (data == null) {
        log('Time sync: No response body');
        return;
      }

      // T2 and T3 from server
      final requestReceived = data.requestReceptionTime;
      final responseSent = data.responseTransmissionTime;

      if (requestReceived == null || responseSent == null) {
        log('Time sync: Missing server timestamps');
        return;
      }

      final measurement = TimeSyncMeasurement(
        requestSent: requestSent,
        requestReceived: requestReceived,
        responseSent: responseSent,
        responseReceived: responseReceived,
      );

      _addMeasurement(measurement);
      _lastMeasurementTime = DateTime.now();

      log('Time sync: offset=${offset.inMilliseconds}ms, ping=${ping.inMilliseconds}ms');
      onMeasurement?.call();
    } catch (e) {
      log('Time sync failed: $e');
    }
  }

  void _addMeasurement(TimeSyncMeasurement measurement) {
    _measurements.add(measurement);
    // Keep only the last N measurements
    while (_measurements.length > _maxMeasurements) {
      _measurements.removeAt(0);
    }
  }

  /// Clear all measurements
  void clear() {
    _measurements.clear();
    _lastMeasurementTime = null;
    _pingCount = 0;
  }

  /// Dispose resources
  void dispose() {
    stop();
    clear();
  }
}

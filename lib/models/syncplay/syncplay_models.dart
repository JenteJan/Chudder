import 'package:freezed_annotation/freezed_annotation.dart';

part 'syncplay_models.freezed.dart';

/// Time sync measurement for NTP-like clock synchronization
@Freezed(copyWith: true)
abstract class TimeSyncMeasurement with _$TimeSyncMeasurement {
  const TimeSyncMeasurement._();

  factory TimeSyncMeasurement({
    required DateTime requestSent,
    required DateTime requestReceived,
    required DateTime responseSent,
    required DateTime responseReceived,
  }) = _TimeSyncMeasurement;

  /// Clock offset between client and server
  /// Positive = server is ahead of client
  Duration get offset {
    final t1 = requestSent.millisecondsSinceEpoch;
    final t2 = requestReceived.millisecondsSinceEpoch;
    final t3 = responseSent.millisecondsSinceEpoch;
    final t4 = responseReceived.millisecondsSinceEpoch;
    final offsetMs = ((t2 - t1) + (t3 - t4)) / 2;
    return Duration(milliseconds: offsetMs.round());
  }

  /// Round-trip delay
  Duration get delay {
    final t1 = requestSent.millisecondsSinceEpoch;
    final t2 = requestReceived.millisecondsSinceEpoch;
    final t3 = responseSent.millisecondsSinceEpoch;
    final t4 = responseReceived.millisecondsSinceEpoch;
    final delayMs = (t4 - t1) - (t3 - t2);
    return Duration(milliseconds: delayMs);
  }

  /// One-way ping (half of round-trip)
  Duration get ping => Duration(milliseconds: delay.inMilliseconds ~/ 2);
}

/// SyncPlay group state
enum SyncPlayGroupState {
  idle,
  waiting,
  paused,
  playing,
}

/// Playback correction strategy used to resync local playback with group time.
enum SyncCorrectionStrategy {
  none,
  speedToSync,
  skipToSync,
}

/// Config values for playback drift correction.
///
/// Defaults match official Jellyfin SyncPlay thresholds.
class SyncCorrectionConfig {
  const SyncCorrectionConfig({
    this.minDelaySpeedToSyncMs = 60,
    this.maxDelaySpeedToSyncMs = 3000,
    this.speedToSyncDurationMs = 1000,
    this.minDelaySkipToSyncMs = 400,
    this.useSpeedToSync = true,
    this.useSkipToSync = true,
    this.enableSyncCorrection = true,
  });

  final double minDelaySpeedToSyncMs;
  final double maxDelaySpeedToSyncMs;
  final double speedToSyncDurationMs;
  final double minDelaySkipToSyncMs;
  final bool useSpeedToSync;
  final bool useSkipToSync;
  final bool enableSyncCorrection;

  SyncCorrectionConfig copyWith({
    double? minDelaySpeedToSyncMs,
    double? maxDelaySpeedToSyncMs,
    double? speedToSyncDurationMs,
    double? minDelaySkipToSyncMs,
    bool? useSpeedToSync,
    bool? useSkipToSync,
    bool? enableSyncCorrection,
  }) {
    return SyncCorrectionConfig(
      minDelaySpeedToSyncMs: minDelaySpeedToSyncMs ?? this.minDelaySpeedToSyncMs,
      maxDelaySpeedToSyncMs: maxDelaySpeedToSyncMs ?? this.maxDelaySpeedToSyncMs,
      speedToSyncDurationMs: speedToSyncDurationMs ?? this.speedToSyncDurationMs,
      minDelaySkipToSyncMs: minDelaySkipToSyncMs ?? this.minDelaySkipToSyncMs,
      useSpeedToSync: useSpeedToSync ?? this.useSpeedToSync,
      useSkipToSync: useSkipToSync ?? this.useSkipToSync,
      enableSyncCorrection: enableSyncCorrection ?? this.enableSyncCorrection,
    );
  }
}

/// Runtime state of playback correction logic.
class SyncCorrectionState {
  const SyncCorrectionState({
    this.syncEnabled = true,
    this.playerIsBuffering = false,
    this.playbackDiffMillis = 0,
    this.syncAttempts = 0,
    this.lastSyncAt,
    this.activeStrategy = SyncCorrectionStrategy.none,
  });

  final bool syncEnabled;
  final bool playerIsBuffering;
  final double playbackDiffMillis;
  final int syncAttempts;
  final DateTime? lastSyncAt;
  final SyncCorrectionStrategy activeStrategy;

  SyncCorrectionState copyWith({
    bool? syncEnabled,
    bool? playerIsBuffering,
    double? playbackDiffMillis,
    int? syncAttempts,
    DateTime? lastSyncAt,
    SyncCorrectionStrategy? activeStrategy,
  }) {
    return SyncCorrectionState(
      syncEnabled: syncEnabled ?? this.syncEnabled,
      playerIsBuffering: playerIsBuffering ?? this.playerIsBuffering,
      playbackDiffMillis: playbackDiffMillis ?? this.playbackDiffMillis,
      syncAttempts: syncAttempts ?? this.syncAttempts,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      activeStrategy: activeStrategy ?? this.activeStrategy,
    );
  }
}

/// Select correction strategy based on current diff and runtime/config state.
///
/// Precedence intentionally mirrors official behavior:
/// SpeedToSync first, then SkipToSync fallback.
SyncCorrectionStrategy selectSyncCorrectionStrategy({
  required SyncCorrectionConfig config,
  required SyncCorrectionState state,
  required double diffMillis,
  required bool hasPlaybackRate,
}) {
  if (!config.enableSyncCorrection || !state.syncEnabled) {
    return SyncCorrectionStrategy.none;
  }

  if (state.activeStrategy != SyncCorrectionStrategy.none) {
    return SyncCorrectionStrategy.none;
  }

  final absDiffMillis = diffMillis.abs();

  final canUseSpeedToSync = (config.useSpeedToSync &&
      hasPlaybackRate &&
      absDiffMillis >= config.minDelaySpeedToSyncMs &&
      absDiffMillis < config.maxDelaySpeedToSyncMs);
  if (canUseSpeedToSync) {
    return SyncCorrectionStrategy.speedToSync;
  }

  final canUseSkipToSync = (config.useSkipToSync && absDiffMillis >= config.minDelaySkipToSyncMs);
  if (canUseSkipToSync) {
    return SyncCorrectionStrategy.skipToSync;
  }

  return SyncCorrectionStrategy.none;
}

/// Current SyncPlay session state
@Freezed(copyWith: true)
abstract class SyncPlayState with _$SyncPlayState {
  const SyncPlayState._();

  factory SyncPlayState({
    @Default(false) bool isConnected,
    @Default(false) bool isInGroup,
    String? groupId,
    String? groupName,
    @Default(SyncPlayGroupState.idle) SyncPlayGroupState groupState,
    String? stateReason,
    @Default([]) List<String> participants,
    String? playingItemId,
    String? playlistItemId,
    @Default(0) int positionTicks,
    DateTime? lastCommandTime,

    /// Whether a SyncPlay command is currently being processed
    @Default(false) bool isProcessingCommand,

    /// The type of command being processed (for UI feedback)
    String? processingCommandType,

    /// Internal correction configuration and thresholds.
    @Default(SyncCorrectionConfig()) SyncCorrectionConfig correctionConfig,

    /// Runtime correction status for UI and command logic.
    @Default(SyncCorrectionState()) SyncCorrectionState correctionState,
  }) = _SyncPlayState;

  bool get isActive => isConnected && isInGroup;
}

/// Last executed command for duplicate detection
@Freezed(copyWith: true)
abstract class LastSyncPlayCommand with _$LastSyncPlayCommand {
  factory LastSyncPlayCommand({
    required String when,
    required int positionTicks,
    required String command,
    required String playlistItemId,
  }) = _LastSyncPlayCommand;
}

/// WebSocket connection state
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Ticks conversion constants
const int ticksPerMillisecond = 10000;
const int ticksPerSecond = 10000000;

/// Convert seconds to ticks
int secondsToTicks(double seconds) => (seconds * ticksPerSecond).round();

/// Convert ticks to seconds
double ticksToSeconds(int ticks) => ticks / ticksPerSecond;

/// Convert milliseconds to ticks
int millisecondsToTicks(int ms) => ms * ticksPerMillisecond;

/// Convert ticks to milliseconds
int ticksToMilliseconds(int ticks) => ticks ~/ ticksPerMillisecond;

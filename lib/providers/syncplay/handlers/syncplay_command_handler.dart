import 'dart:async';
import 'dart:developer';

import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/providers/syncplay/time_sync_service.dart';

/// Callback types for player control commands from SyncPlay
typedef SyncPlayPlayerCallback = Future<void> Function();
typedef SyncPlaySeekCallback = Future<void> Function(int positionTicks);
typedef SyncPlayPositionCallback = int Function();
typedef SyncPlayReportReadyCallback = Future<void> Function();
typedef SyncPlaySetSpeedCallback = Future<void> Function(double speed);

/// Handles scheduling and execution of SyncPlay commands
class SyncPlayCommandHandler {
  SyncPlayCommandHandler({
    required this.timeSync,
    required this.onStateUpdate,
  });

  final TimeSyncService? Function() timeSync;
  final void Function(SyncPlayState Function(SyncPlayState)) onStateUpdate;

  // Last command for duplicate detection
  LastSyncPlayCommand? _lastCommand;

  // Pending command timer
  Timer? _commandTimer;

  // Player callbacks
  SyncPlayPlayerCallback? onPlay;
  SyncPlayPlayerCallback? onPause;
  SyncPlaySeekCallback? onSeek;
  SyncPlayPlayerCallback? onStop;
  SyncPlayPositionCallback? getPositionTicks;
  bool Function()? isPlaying;
  bool Function()? isBuffering;

  // New callback to signal that a seek has been requested by someone else
  SyncPlaySeekCallback? onSeekRequested;

  // Report ready callback (to tell server we're ready after seek)
  SyncPlayReportReadyCallback? onReportReady;

  // Playback rate callbacks for SpeedToSync
  SyncPlaySetSpeedCallback? onSetSpeed;
  bool Function()? hasPlaybackRate;

  /// Last accepted command (non-duplicate), exposed for correction logic.
  LastSyncPlayCommand? get lastCommand => _lastCommand;

  /// Handle incoming SyncPlay command from WebSocket
  void handleCommand(Map<String, dynamic> data, SyncPlayState currentState) {
    final commandWire = data['Command'] as String?;
    final whenStr = data['When'] as String?;
    final positionTicks = data['PositionTicks'] as int? ?? 0;
    final playlistItemId = data['PlaylistItemId'] as String? ?? '';

    final command = SyncPlayCommand.fromWire(commandWire);
    if (command == null || whenStr == null) {
      log('SyncPlay: Ignoring unknown command "$commandWire"');
      return;
    }

    // Check for duplicate command
    if (_isDuplicateCommand(whenStr, positionTicks, command, playlistItemId)) {
      log('SyncPlay: Ignoring duplicate command: ${command.wire}');
      return;
    }

    _lastCommand = LastSyncPlayCommand(
      when: whenStr,
      positionTicks: positionTicks,
      command: command,
      playlistItemId: playlistItemId,
    );

    onStateUpdate((state) => state.copyWith(
          positionTicks: positionTicks,
          playlistItemId: playlistItemId,
        ));

    // If it's a Seek command, notify the player immediately so it can
    // report buffering.
    if (command == SyncPlayCommand.seek) {
      onSeekRequested?.call(positionTicks);
    }

    final when = DateTime.parse(whenStr);
    _scheduleCommand(command, when, positionTicks);
  }

  bool _isDuplicateCommand(
    String when,
    int positionTicks,
    SyncPlayCommand command,
    String playlistItemId,
  ) {
    if (_lastCommand == null) {
      return false;
    }

    // For Unpause commands, if we are not currently playing, we should
    // NEVER treat it as a duplicate to ensure the player actually
    // resumes.
    if (command == SyncPlayCommand.unpause && isPlaying?.call() == false) {
      return false;
    }

    return _lastCommand!.when == when &&
        _lastCommand!.positionTicks == positionTicks &&
        _lastCommand!.command == command &&
        _lastCommand!.playlistItemId == playlistItemId;
  }

  /// Guard rules before any playback correction attempt.
  ///
  /// Rules:
  /// - only after `Unpause` command context
  /// - skip while player is buffering/reloading
  /// - skip when command playlist item does not match current item
  bool canAttemptSyncCorrection(SyncPlayState currentState) {
    final command = _lastCommand;
    if (command == null) {
      return false;
    }
    if (command.command != SyncPlayCommand.unpause) {
      return false;
    }
    if (isBuffering?.call() == true) {
      return false;
    }

    final commandItemId = command.playlistItemId;
    final currentItemId = currentState.playlistItemId;
    if (commandItemId.isNotEmpty && currentItemId != null && commandItemId != currentItemId) {
      return false;
    }

    return true;
  }

  void _scheduleCommand(
    SyncPlayCommand command,
    DateTime serverTime,
    int positionTicks,
  ) {
    final timeSyncService = timeSync();
    if (timeSyncService == null) {
      log('SyncPlay: Cannot schedule command without time sync');
      _executeCommand(command, positionTicks);
      return;
    }

    final localTime = timeSyncService.remoteDateToLocal(serverTime);
    final now = DateTime.now().toUtc();
    final delay = localTime.difference(now);

    _commandTimer?.cancel();

    // Show processing indicator
    onStateUpdate((state) => state.copyWith(
          isProcessingCommand: true,
          processingCommandType: command,
        ));

    if (delay.isNegative) {
      // Command is in the past - execute immediately. Estimate where
      // playback should be now.
      final estimatedTicks = _estimateCurrentTicks(positionTicks, serverTime);
      log('SyncPlay: Executing late command: ${command.wire} '
          '(${delay.inMilliseconds}ms late)');
      _executeCommand(command, estimatedTicks);
    } else if (delay.inMilliseconds > 5000) {
      log('SyncPlay: Warning - large delay: ${delay.inMilliseconds}ms');
      _commandTimer = Timer(delay, () => _executeCommand(command, positionTicks));
    } else {
      log('SyncPlay: Scheduling command: ${command.wire} '
          'in ${delay.inMilliseconds}ms');
      _commandTimer = Timer(delay, () => _executeCommand(command, positionTicks));
    }
  }

  int _estimateCurrentTicks(int ticks, DateTime when) {
    final timeSyncService = timeSync();
    if (timeSyncService == null) {
      return ticks;
    }
    final remoteNow = timeSyncService.localDateToRemote(DateTime.now().toUtc());
    final elapsedMs = remoteNow.difference(when).inMilliseconds;
    return ticks + millisecondsToTicks(elapsedMs);
  }

  Future<void> _executeCommand(
    SyncPlayCommand command,
    int positionTicks,
  ) async {
    log('SyncPlay: Executing command: ${command.wire} at $positionTicks ticks');

    try {
      switch (command) {
        case SyncPlayCommand.pause:
          await onPause?.call();
          // Only seek if position is significantly different (>1 sec).
          final currentTicks = getPositionTicks?.call() ?? 0;
          if ((positionTicks - currentTicks).abs() > ticksPerSecond) {
            await onSeek?.call(positionTicks);
          }
          break;

        case SyncPlayCommand.unpause:
          // Only seek if position is significantly different (>1 sec).
          // Seek first, then play for smoother unpause alignment.
          final currentTicks = getPositionTicks?.call() ?? 0;
          if ((positionTicks - currentTicks).abs() > ticksPerSecond) {
            await onSeek?.call(positionTicks);
          }
          await onPlay?.call();
          break;

        case SyncPlayCommand.seek:
          await onPause?.call();
          await onSeek?.call(positionTicks);
          // Report ready after seek so server knows to send unpause. If
          // we're buffering, the buffering state handler will report
          // ready when done; otherwise report immediately.
          if (isBuffering?.call() != true) {
            await onReportReady?.call();
          }
          break;

        case SyncPlayCommand.stop:
          await onPause?.call();
          await onSeek?.call(0);
          break;
      }
    } finally {
      // Clear processing state after command completes
      onStateUpdate((state) => state.copyWith(
            isProcessingCommand: false,
            processingCommandType: null,
          ));
    }
  }

  /// Cancel any pending commands
  void cancelPendingCommands() {
    _commandTimer?.cancel();
  }

  /// Clear last command context used for duplicate detection and correction.
  void clearLastCommand() {
    _lastCommand = null;
  }

  /// Dispose resources
  void dispose() {
    _commandTimer?.cancel();
  }
}

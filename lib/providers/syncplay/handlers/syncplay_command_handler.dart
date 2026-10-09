import 'dart:async';
import 'package:chudder/providers/syncplay/syncplay_log.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/syncplay/time_sync_service.dart';

/// Callback types for player control commands from SyncPlay
typedef SyncPlayPlayerCallback = Future<void> Function();
typedef SyncPlaySeekCallback = Future<void> Function(int positionTicks);
typedef SyncPlayPositionCallback = int Function();
/// [positionTicks] is where the command put the player.
typedef SyncPlayReportReadyCallback = Future<void> Function(int positionTicks);
typedef SyncPlaySetSpeedCallback = Future<void> Function(double speed);

/// Handles scheduling and execution of SyncPlay commands
class SyncPlayCommandHandler {
  SyncPlayCommandHandler({
    required this.timeSync,
    required this.onStateUpdate,
  });

  /// Commands more than this late are dropped on the floor — typical
  /// trigger is the server replaying its queued backlog after a long
  /// client disconnect (phone locked, app backgrounded). The current
  /// `StateUpdate` messages from the server then resync us.

  final TimeSyncService? Function() timeSync;
  final void Function(SyncPlayState Function(SyncPlayState)) onStateUpdate;

  // Last command for duplicate detection
  LastSyncPlayCommand? _lastCommand;

  // Pending command timer
  Timer? _commandTimer;

  /// Bumped whenever what is scheduled is replaced or dropped, so a resume
  /// that is still waiting for its moment knows it has been overtaken.
  int _schedule = 0;
  bool _resuming = false;

  /// How long a seek keeps this player from playing, in milliseconds, as
  /// last measured; zero until one has been. A phone on a remote stream
  /// takes a second or more, a desktop on the same network a fraction.
  int _seekLeadMs = 0;
  int get seekLeadMs => _seekLeadMs;

  /// What the measured start latency turns out to be off by on this
  /// device, in milliseconds. The measurement is of the position being seen
  /// to move, which is not quite the picture moving: a phone came out of
  /// every resume some 150 ms ahead of its group and was slowed down for a
  /// second to lose it. The first drift reading after a resume says how far
  /// out the start was, and the next one is timed that much differently.
  int _leadTrimMs = 0;
  final List<int> _trimsAsked = [];
  DateTime? _resumedAt;

  /// The drift measured just now, [diffMillis] behind the group (ahead of
  /// it when negative). Counts only as the first reading after a resume.
  void noteDriftAfterResume(double diffMillis) {
    final at = _resumedAt;
    if (at == null) return;
    _resumedAt = null;
    if (DateTime.now().difference(at) > const Duration(seconds: 6) || diffMillis.abs() > 500) return;
    // One reading is mostly noise - a desktop came out 285 ms ahead and,
    // corrected for that, 230 ms behind - so the trim is the middle of what
    // the last few starts each asked for, and none at all before three.
    _trimsAsked.add(_leadTrimMs + diffMillis.round());
    if (_trimsAsked.length > 5) _trimsAsked.removeAt(0);
    if (_trimsAsked.length >= 3) {
      final sorted = [..._trimsAsked]..sort();
      _leadTrimMs = sorted[sorted.length ~/ 2].clamp(-300, 300);
    }
    log('SyncPlay: Resume: came out ${diffMillis.round()}ms behind; start timing trimmed to ${_leadTrimMs}ms');
  }

  /// A resume that arrived while the item was loading and is still owed.
  bool _unpauseHeld = false;
  bool get hasHeldUnpause => _unpauseHeld;

  // Player callbacks
  SyncPlayPlayerCallback? onPlay;
  SyncPlayPlayerCallback? onPause;
  SyncPlaySeekCallback? onSeek;
  SyncPlayPlayerCallback? onStop;
  SyncPlayPositionCallback? getPositionTicks;

  /// The item's length, so an old Unpause can tell whether the group has
  /// run past the end of it.
  SyncPlayPositionCallback? getDurationTicks;

  /// How long this player takes to actually advance after it is told to
  /// play, in milliseconds, as last measured. An Unpause on a player that is
  /// not yet running is issued that much ahead of its time, so the picture
  /// is moving when the group's clock says it should be.
  int Function()? getStartLatencyMs;
  bool Function()? isPlaying;
  bool Function()? isBuffering;

  /// Completes when the player, paused, can start the moment it is told to,
  /// for players that can say so. The buffering flag is a poor stand-in: it
  /// is often not up yet when it is first asked after a seek, and a paused
  /// player leaves it up long after it has enough.
  Future<void> Function()? waitUntilPlayable;

  /// The player settling after a seek, for no longer than [limit].
  Future<void> _settleAfterSeek(Duration limit) async {
    final playable = waitUntilPlayable;
    if (playable != null) {
      await playable().timeout(limit, onTimeout: () {});
      return;
    }
    await _waitUntilBuffering(timeout: const Duration(milliseconds: 150));
    if (isBuffering?.call() == true) {
      await _waitUntilNotBuffering(timeout: limit);
    }
  }

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
      // The same Seek again is not an echo. It is how the server refuses a
      // Ready: one that named a position more than half a second from the
      // group's is answered with the group's Seek once more, and the group
      // is kept waiting until a Ready names the right place. Dropped as a
      // duplicate, that left everyone on "waiting" until somebody pressed
      // play. While the first is still being carried out, its own Ready is
      // on the way and this one can be let go.
      if (command == SyncPlayCommand.seek && !currentState.isProcessingCommand) {
        log('SyncPlay: the Seek again - the last Ready was refused; answering at its position');
        unawaited(_answerRepeatedSeek(positionTicks));
      } else {
        log('SyncPlay: Ignoring duplicate command: ${command.wire}');
      }
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

    // A resume that lands while the item is still being loaded has nothing
    // to act on: the play is swallowed by the load, which opens the file
    // paused, and the answer the server gives to the Ready that follows is
    // this same command over again - dropped as a duplicate whenever the
    // player still read as playing. That left a member who joined a running
    // group sitting on a paused picture. It is kept, and carried out by
    // [resumeFromLastCommand] once the load is done.
    _unpauseHeld = false;
    if (command == SyncPlayCommand.unpause && currentState.startPlaybackInProgress) {
      log('SyncPlay: Unpause arrived mid-load; holding it until the item is ready');
      _commandTimer?.cancel();
      _schedule++;
      _unpauseHeld = true;
      return;
    }

    final when = DateTime.parse(whenStr);
    _scheduleCommand(command, when, positionTicks);
  }

  /// Carry out the group's last command again if it was a resume, placing
  /// the player where the group has got to since. For a player that has
  /// only now become able to follow it - its item just finished loading -
  /// or that turns out not to be playing while the group is.
  ///
  /// Returns whether there was a resume to carry out.
  bool resumeFromLastCommand() {
    _unpauseHeld = false;
    final command = _lastCommand;
    if (command == null || command.command != SyncPlayCommand.unpause) return false;
    final when = DateTime.tryParse(command.when);
    if (when == null) return false;
    // Whatever the player's state reads: this is only ever asked of one
    // that has just loaded its item paused, or was found standing still.
    _scheduleCommand(command.command, when, command.positionTicks, playerStopped: true);
    return true;
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

  Future<void> _answerRepeatedSeek(int positionTicks) async {
    try {
      final current = getPositionTicks?.call() ?? positionTicks;
      if ((current - positionTicks).abs() > ticksPerSecond ~/ 2) {
        await onSeek?.call(positionTicks);
        await _waitUntilBuffering(timeout: const Duration(milliseconds: 150));
        if (isBuffering?.call() == true) {
          await _waitUntilNotBuffering(timeout: const Duration(seconds: 2));
        }
      }
      await onReportReady?.call(positionTicks);
    } catch (e) {
      log('SyncPlay: Failed to answer the repeated Seek: $e');
    }
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
    int positionTicks, {
    bool playerStopped = false,
  }) {
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
    final schedule = ++_schedule;

    // A player that is standing still is not moved to the group's position:
    // it is started at the moment the group's position reaches where it
    // stands. See [_resumePaused].
    if (command == SyncPlayCommand.unpause && (playerStopped || isPlaying?.call() != true)) {
      final duration = getDurationTicks?.call() ?? 0;
      if (delay.isNegative && duration > 0 && _estimateCurrentTicks(positionTicks, serverTime) >= duration) {
        log('SyncPlay: Ignoring Unpause from ${(-delay).inSeconds}s ago; '
            'the group has run past the end of the item');
        return;
      }
      onStateUpdate((state) => state.copyWith(
            isProcessingCommand: true,
            processingCommandType: command,
          ));
      unawaited(_resumePaused(serverTime, positionTicks, schedule));
      return;
    }

    if (delay.isNegative) {
      // Late, however late. A member that reports ready in a group that is
      // already playing is answered with the group's last command, issued
      // whenever it was; resuming into a group that had played on for a
      // minute used to have that Unpause thrown away as stale, and the
      // player sat paused. Only Unpause extrapolates the position by the
      // time elapsed - the group has been playing through it - and an
      // extrapolation past the end means the item is over, which is the
      // one case there is nothing to do. Pause, Seek and Stop are static
      // targets: the original position holds however late they arrive.
      var ticksToUse = positionTicks;
      if (command == SyncPlayCommand.unpause) {
        ticksToUse = _estimateCurrentTicks(positionTicks, serverTime);
        final duration = getDurationTicks?.call() ?? 0;
        if (duration > 0 && ticksToUse >= duration) {
          log('SyncPlay: Ignoring Unpause from ${(-delay).inSeconds}s ago; '
              'the group has run past the end of the item');
          return;
        }
      }
      onStateUpdate((state) => state.copyWith(
            isProcessingCommand: true,
            processingCommandType: command,
          ));
      log('SyncPlay: Executing late command: ${command.wire} '
          '(${delay.inMilliseconds}ms late)');
      _executeCommand(command, ticksToUse);
    } else {
      onStateUpdate((state) => state.copyWith(
            isProcessingCommand: true,
            processingCommandType: command,
          ));
      // A player that is not running starts late by however long it takes
      // to get going, and used to come out of every resume that far behind
      // the group, to be dragged up to speed afterwards. It is told to play
      // that much early instead.
      var lead = Duration.zero;
      if (command == SyncPlayCommand.unpause && isPlaying?.call() != true) {
        lead = Duration(milliseconds: (getStartLatencyMs?.call() ?? 0).clamp(0, 1500));
      }
      final wait = delay - lead;
      if (delay.inMilliseconds > 5000) {
        log('SyncPlay: Warning - large delay: ${delay.inMilliseconds}ms');
      } else {
        log('SyncPlay: Scheduling command: ${command.wire} '
            'in ${delay.inMilliseconds}ms${lead > Duration.zero ? ' (led by ${lead.inMilliseconds}ms)' : ''}');
      }
      if (wait.isNegative) {
        _executeCommand(command, positionTicks);
      } else {
        _commandTimer = Timer(wait, () => _executeCommand(command, positionTicks));
      }
    }
  }

  /// Resume a player that is not playing, in step with the group.
  ///
  /// The group's position is [positionTicks] until [when] and runs on from
  /// there. The player was put on that position with a seek and then played,
  /// and a seek is the slow part: a phone needs a second or more before it
  /// shows a picture again, came out of every resume and every join that far
  /// behind, and spent the next ten seconds jumping and racing to catch up.
  ///
  /// Mostly no seek is needed. A player that was paused with the group, or
  /// has just loaded the item a little ahead of it, stands close to where
  /// the group is about to be: it only has to start at the right moment,
  /// which is when the group's position reaches its own. Only a player that
  /// stands somewhere else altogether is moved, and then to where the group
  /// will be once the seek is over rather than to where it is now.
  Future<void> _resumePaused(DateTime when, int positionTicks, int schedule) async {
    _resuming = true;
    try {
      // How long until the group's position reaches the player's.
      int untilGroupArrives() {
        final remoteNow = timeSync()?.localDateToRemote(DateTime.now().toUtc()) ?? DateTime.now().toUtc();
        final playerTicks = getPositionTicks?.call() ?? positionTicks;
        return ticksToMilliseconds(playerTicks - positionTicks) - remoteNow.difference(when).inMilliseconds;
      }

      final lead = ((getStartLatencyMs?.call() ?? 0) + _leadTrimMs).clamp(0, 1000);
      var wait = untilGroupArrives();
      if (wait - lead < -150 || wait > 5000) {
        final remoteNow = timeSync()?.localDateToRemote(DateTime.now().toUtc()) ?? DateTime.now().toUtc();
        final since = remoteNow.difference(when).inMilliseconds;
        final seekLead = _seekLeadMs > 0 ? _seekLeadMs + 200 : 1000;
        final ahead = since + seekLead + lead;
        var target = positionTicks + millisecondsToTicks(ahead > 0 ? ahead : 0);
        final duration = getDurationTicks?.call() ?? 0;
        if (duration > 0 && target >= duration) target = positionTicks + millisecondsToTicks(since > 0 ? since : 0);
        log('SyncPlay: Resume: the player is ${-wait}ms from the group; '
            'seeking to where the group will be in ${seekLead + lead}ms');
        final seekTimer = Stopwatch()..start();
        await onSeek?.call(target);
        if (schedule != _schedule) return;
        // Until it can play, or until it has to.
        final room = untilGroupArrives() - lead;
        var settled = true;
        if (waitUntilPlayable != null) {
          settled = await waitUntilPlayable!().then((_) => true).timeout(
                Duration(milliseconds: room > 0 ? room : 0),
                onTimeout: () => false,
              );
          if (schedule != _schedule) return;
        } else {
          await _waitUntilBuffering(timeout: const Duration(milliseconds: 150));
          while (isBuffering?.call() == true) {
            if (untilGroupArrives() - lead <= 0) {
              settled = false;
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 25));
            if (schedule != _schedule) return;
          }
        }
        final took = seekTimer.elapsedMilliseconds;
        final measured = settled ? took : took + 500;
        _seekLeadMs = (_seekLeadMs == 0 ? measured : (_seekLeadMs + measured) ~/ 2).clamp(100, 5000);
        log('SyncPlay: Resume: seek ${settled ? 'took' : 'still going after'} ${took}ms; allowing ${_seekLeadMs}ms');
        wait = untilGroupArrives();
      }

      final fire = wait - lead;
      log('SyncPlay: Resume: the group reaches this player in ${wait}ms; playing in ${fire > 0 ? fire : 0}ms');
      if (fire > 0) {
        await Future<void>.delayed(Duration(milliseconds: fire));
        if (schedule != _schedule) return;
      }
      _resumedAt = DateTime.now();
      await onPlay?.call();
      if (isBuffering?.call() == true) {
        await _waitUntilNotBuffering();
      }
    } catch (e) {
      log('SyncPlay: Resume failed: $e');
    } finally {
      _resuming = false;
      if (schedule == _schedule) {
        onStateUpdate((state) => state.copyWith(
              isProcessingCommand: false,
              processingCommandType: null,
            ));
      }
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
          final needsCorrectionSeek = (positionTicks - currentTicks).abs() > ticksPerSecond;
          if (needsCorrectionSeek) {
            await onSeek?.call(positionTicks);
            // Seek can put native ExoPlayer through STATE_BUFFERING; hold
            // isProcessingCommand=true until that clears. Same rationale as
            // the Unpause and Seek paths.
            if (isBuffering?.call() == true) {
              await _waitUntilNotBuffering();
            }
          }
          break;

        case SyncPlayCommand.unpause:
          // Seek first, then play for smoother unpause alignment. A player
          // that is already running is only moved for a difference of more
          // than a second, since a seek interrupts it; one that is paused
          // can be placed exactly at no visible cost. That is where a member
          // who has just joined sits - loaded near the live position, with
          // the group held for them - and a second's dead zone left them
          // starting behind everyone else and being dragged into step.
          //
          // A running player that can change its rate is left alone for
          // longer still: drift correction closes anything under three
          // seconds without a cut, and the one case that gets here is a
          // player that played on through a hold - about a second ahead,
          // which a one-second limit turned into a jump back as often as not.
          final currentTicks = getPositionTicks?.call() ?? 0;
          final threshold = isPlaying?.call() != true
              ? ticksPerSecond ~/ 4
              : hasPlaybackRate?.call() == true
                  ? ticksPerSecond * 3
                  : ticksPerSecond;
          if ((positionTicks - currentTicks).abs() > threshold) {
            await onSeek?.call(positionTicks);
          }
          await onPlay?.call();
          // Resuming from pause can put native ExoPlayer (Android-TV /
          // leanback) through STATE_BUFFERING for several hundred ms
          // while it primes the resumed buffer. Hold isProcessingCommand
          // true for that window — otherwise the player-state listener
          // leaks a stale Buffering report once the time-based cooldown
          // expires, which forms a feedback loop in any SyncPlay group
          // containing a TV.
          if (isBuffering?.call() == true) {
            await _waitUntilNotBuffering();
          }
          break;

        case SyncPlayCommand.seek:
          await onPause?.call();
          await onSeek?.call(positionTicks);
          // Wait for the seek-induced buffering to clear before
          // reporting Ready. The buffering listener in
          // video_player_provider is suppressed while
          // isProcessingCommand is true, so we own the Ready signal
          // here. Without this wait the listener would fire a
          // Ready(isPlaying:false) (we paused as part of the seek)
          // that overrides the explicit Ready below — server would
          // then keep the group paused instead of broadcasting
          // Unpause, and the player would not auto-resume.
          //
          // Cap the wait at 2 s: libMPV (phone/web) keeps
          // `paused-for-cache` true conservatively while the player
          // is paused — it only flips to false once the cache is
          // fully topped up, which can take many seconds even when
          // there is plenty already buffered to play. ExoPlayer
          // (Android-TV) settles seek-buffering well within 2 s, so
          // shortening this timeout doesn't regress the TV path. If
          // the cap is reached we still fire onReportReady; the
          // server's Unpause then arrives normally and the next
          // onPlay flips libMPV to "playing" mode where it emits
          // buffering=false immediately.
          //
          // The seek call returns before the player has started on it, so
          // asking straight away usually found it "not buffering" and
          // reported Ready at once; the group then resumed on a player that
          // took another second or two to produce a picture and spent the
          // next few seconds racing to catch up. Give the flag a moment to
          // come up first.
          await _settleAfterSeek(const Duration(seconds: 3));
          // At the seek's own target, not at what the player reports: paused,
          // it goes on reporting where it was before the seek, the server
          // refuses a Ready more than half a second off the group's position
          // and sends the Seek again - and the whole wait is paid twice.
          await onReportReady?.call(positionTicks);
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

  /// Poll the [isBuffering] callback until it returns `false` or the
  /// timeout expires. Used by the Seek command handler so the explicit
  /// `onReportReady` fires only once the player has finished buffering.
  Future<void> _waitUntilNotBuffering({
    Duration timeout = const Duration(seconds: 10),
    // A cheap boolean, asked often: each tick of this is latency added to
    // the Ready the group waits on.
    Duration pollInterval = const Duration(milliseconds: 25),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (isBuffering?.call() == true && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Poll until the player reports buffering, or [timeout] passes without
  /// it: a seek inside what is already buffered never does.
  Future<void> _waitUntilBuffering({required Duration timeout}) async {
    final deadline = DateTime.now().add(timeout);
    while (isBuffering?.call() != true && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  /// Whether a command is scheduled but has not fired yet.
  bool get hasScheduledCommand => (_commandTimer?.isActive ?? false) || _resuming;

  /// Cancel any pending commands
  void cancelPendingCommands() {
    _commandTimer?.cancel();
    _schedule++;
  }

  /// Clear last command context used for duplicate detection and correction.
  void clearLastCommand() {
    _lastCommand = null;
    _unpauseHeld = false;
  }

  /// Dispose resources
  void dispose() {
    _commandTimer?.cancel();
  }
}

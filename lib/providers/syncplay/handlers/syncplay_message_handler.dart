import 'package:fladder/providers/syncplay/syncplay_log.dart';

import 'package:fladder/l10n/generated/app_localizations.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:flutter/material.dart';

/// Callback for reporting ready state after seek
typedef ReportReadyCallback = Future<void> Function({bool isPlaying});

/// Callback for starting playback of an item
typedef StartPlaybackCallback = Future<void> Function(String itemId, int startPositionTicks);

/// Callback that pauses the local player without sending a SyncPlay
/// pause request. Used when the group enters Waiting because another
/// client is buffering — we must mirror the group state locally.
typedef LocalPauseCallback = Future<void> Function();

/// Handles SyncPlay group update messages from WebSocket
class SyncPlayMessageHandler {
  SyncPlayMessageHandler({
    required this.onStateUpdate,
    required this.reportReady,
    required this.startPlayback,
    required this.isBuffering,
    required this.getContext,
    required this.onGroupJoined,
    required this.onGroupJoinFailed,
    this.onGroupLeftOrKicked,
    this.onStateUpdateToPlaying,
    this.onGroupGone,
    this.onLocalPauseForBuffer,
    this.fetchParticipants,
    this.onNewPlaylist,
  });

  final void Function(SyncPlayState Function(SyncPlayState)) onStateUpdate;
  final ReportReadyCallback reportReady;
  final StartPlaybackCallback startPlayback;
  final bool Function() isBuffering;
  final BuildContext? Function() getContext;
  final void Function() onGroupJoined;
  final void Function() onGroupJoinFailed;

  /// Called when we leave or are kicked so controller can cancel pending commands and clear processing state.
  final void Function()? onGroupLeftOrKicked;

  /// The group's participants as the server lists them right now, or null
  /// when it cannot be asked. The join and leave frames name a user, not a
  /// session, and the server lists each user once however many devices
  /// they are on: taking a name off the list on the first leave frame
  /// showed a group of nobody while the same person was still in it from
  /// another client. The list is taken from the server after each frame.
  final Future<List<String>?> Function()? fetchParticipants;

  /// Told of every queue the server hands over as a new playlist, and
  /// whether it was empty. The one that follows a join says whether the
  /// group has anything to play.
  final void Function(bool isEmpty)? onNewPlaylist;

  /// Called when group state becomes Playing so controller can ensure player is actually playing (per docs).
  final void Function()? onStateUpdateToPlaying;

  /// Called when the user is no longer part of the group from the
  /// server's perspective (kicked, group disposed, etc.) so that the
  /// controller can surface a user-visible notification.
  final void Function({required bool wasKicked})? onGroupGone;

  /// Called when the group enters Waiting because another client is
  /// buffering. Mirrors the group state locally before reporting Ready
  /// so we don't keep playing while the group is logically paused.
  final LocalPauseCallback? onLocalPauseForBuffer;

  /// Handle group update message
  void handleGroupUpdate(Map<String, dynamic> data, SyncPlayState currentState) {
    _wasInGroupAtLastUpdate = currentState.isInGroup;
    final updateType = data['Type'] as String?;
    final updateData = data['Data'];

    switch (updateType) {
      case 'GroupJoined':
        _handleGroupJoined(updateData as Map<String, dynamic>);
        break;
      case 'UserJoined':
        _handleUserJoined(updateData as String?, currentState);
        break;
      case 'UserLeft':
        _handleUserLeft(updateData as String?, currentState);
        break;
      case 'GroupLeft':
        _handleGroupLeft();
        break;
      case 'GroupDoesNotExist':
        _handleGroupDoesNotExist();
        break;
      case 'NotInGroup':
        _handleNotInGroup();
        break;
      case 'LibraryAccessDenied':
        _handleLibraryAccessDenied();
        break;
      case 'StateUpdate':
        _handleStateUpdate(updateData as Map<String, dynamic>);
        break;
      case 'PlayQueue':
        _handlePlayQueue(updateData as Map<String, dynamic>, currentState);
        break;
    }
  }

  void _handleGroupJoined(Map<String, dynamic> data) {
    final groupId = data['GroupId'] as String?;
    final groupName = data['GroupName'] as String?;
    final stateStr = data['State'] as String?;
    final participants = (data['Participants'] as List?)?.cast<String>() ?? [];

    // GroupJoined carries a GroupInfoDto: id, name, state, participants,
    // timestamp — the server NEVER includes the playing item or position
    // here. The authoritative item arrives moments later in the PlayQueue
    // (NewPlaylist) snapshot WaitingGroupState.SessionJoined sends every
    // joiner. Falling back to this client's previous playingItemId here made
    // joins auto-attach to whatever we played LAST — jumping to old shows —
    // and the stale in-flight start then starved the real one.
    onStateUpdate((state) {
      // Joined again while already in: a resume restores the session, and
      // the server's list names each person once. What was counted here
      // for people on several devices is kept for anyone still listed.
      final rejoined = state.isInGroup && state.groupId == groupId;
      final counted = rejoined
          ? [
              for (final name in participants)
                ...List.filled(state.participants.where((p) => p == name).length.clamp(1, 1 << 16), name),
            ]
          : participants;
      return state.copyWith(
        isInGroup: true,
        groupId: groupId,
        groupName: groupName,
        groupState: _parseGroupState(stateStr),
        participants: counted,
        playingItemId: null,
        playlistItemId: null,
      );
    });

    log('SyncPlay: Joined group "$groupName" ($groupId)');

    // Notify controller that group join was confirmed
    onGroupJoined();
  }

  /// Note: SyncPlay's `UserJoined` / `UserLeft` payloads carry the
  /// participant's display name directly in `Data` (a plain string),
  /// not a userId. No `usersUserIdGet` lookup is needed - calling that
  /// endpoint with the username returns a 400.
  void _handleUserJoined(String? userName, SyncPlayState currentState) {
    if (userName == null) {
      return;
    }
    // One entry per join frame, so a person on two devices is two members.
    // The server names a user, not a session, and lists each user once,
    // so this is the only place a second device can be counted. A session
    // restore - what resume does - also sends a join frame to the others,
    // so the count can run high until the next leave; a group of nobody
    // while someone is still in it was worse.
    final participants = [...currentState.participants, userName];
    onStateUpdate((state) => state.copyWith(participants: participants));
    _refreshParticipants();

    _showSnackbar((l) => l.syncPlayUserJoined(userName));
    log('SyncPlay: User joined: $userName');
  }

  void _handleUserLeft(String? userName, SyncPlayState currentState) {
    if (userName == null) {
      return;
    }
    // One entry goes, not every entry with this name: the other devices of
    // the same person are still in. The server's list then puts back anyone
    // this took off who is in fact still there.
    final participants = [...currentState.participants];
    final index = participants.indexOf(userName);
    if (index >= 0) participants.removeAt(index);
    onStateUpdate((state) => state.copyWith(participants: participants));
    _refreshParticipants();

    _showSnackbar((l) => l.syncPlayUserLeft(userName));
    log('SyncPlay: User left: $userName');
  }

  void _refreshParticipants() {
    final fetch = fetchParticipants;
    if (fetch == null) return;
    fetch().then((listed) {
      if (listed == null) return;
      onStateUpdate((state) {
        if (!state.isInGroup) return state;
        // The server's list is the truth about who is in; the local count
        // is the only knowledge of how many devices each of them is on.
        // Everyone the server lists appears at least once, as many times
        // as they were counted, and nobody it does not list appears.
        final reconciled = <String>[];
        for (final name in listed) {
          final counted = state.participants.where((p) => p == name).length;
          reconciled.addAll(List.filled(counted > 0 ? counted : 1, name));
        }
        return state.copyWith(participants: reconciled);
      });
    }).catchError((Object e) {
      log('SyncPlay: participants refresh failed: $e');
    });
  }

  /// Render a snackbar through the global notification overlay. We
  /// deliberately do NOT pass the navigator-key context here: that
  /// context lives under `Navigator` but not under any `Overlay`, so
  /// `Overlay.of(context)` throws. `FladderSnack` keeps a stored root
  /// context (set by `NotificationManagerInitializer`) that already
  /// resolves to the root overlay.
  void _showSnackbar(String Function(AppLocalizations l) builder) {
    final context = getContext();
    if (context != null) {
      FladderSnack.show(builder(context.localized));
      return;
    }
    try {
      final loc = lookupAppLocalizations(const Locale('en'));
      FladderSnack.show(builder(loc));
    } catch (_) {
      // No fallback available - silently swallow.
    }
  }

  void _handleGroupLeft() {
    onStateUpdate((state) => state.copyWith(
          isInGroup: false,
          groupId: null,
          groupName: null,
          groupState: SyncPlayGroupState.idle,
          participants: [],
          isProcessingCommand: false,
          processingCommandType: null,
        ));
    onGroupLeftOrKicked?.call();
    log('SyncPlay: Left group');
  }

  void _handleGroupDoesNotExist() {
    final wasInGroup = _wasInGroupAtLastUpdate;
    onStateUpdate((state) => state.copyWith(
          isInGroup: false,
          groupId: null,
          groupName: null,
          groupState: SyncPlayGroupState.idle,
          participants: [],
          isProcessingCommand: false,
          processingCommandType: null,
        ));
    onGroupLeftOrKicked?.call();
    log('SyncPlay: Group does not exist');

    if (wasInGroup) {
      onGroupGone?.call(wasKicked: false);
    }

    // Notify controller that group join failed
    onGroupJoinFailed();
  }

  /// The server refuses a join when the joiner can't see the group's current
  /// item (`SyncPlayManager.JoinGroup` checks `HasAccessToItem` and answers
  /// with this instead of `GroupJoined`). It is the third and last way a join
  /// can be rejected, and the only one that was never handled: the join
  /// completer simply went unanswered, so the sheet sat there for the full
  /// 12-second timeout before reporting a failure the server had already
  /// explained. Fail fast, and say why.
  void _handleLibraryAccessDenied() {
    log('SyncPlay: Failed to join group - no access to the group\'s library item');
    _showSnackbar((l) => l.syncPlayFailedToJoinGroup);
    onGroupJoinFailed();
  }

  void _handleNotInGroup() {
    final wasInGroup = _wasInGroupAtLastUpdate;
    onStateUpdate((state) => state.copyWith(
          isInGroup: false,
          groupId: null,
          groupName: null,
          groupState: SyncPlayGroupState.idle,
          participants: [],
          isProcessingCommand: false,
          processingCommandType: null,
        ));
    onGroupLeftOrKicked?.call();
    log('SyncPlay: Not in group - server rejected operation');

    if (wasInGroup) {
      onGroupGone?.call(wasKicked: true);
    }

    // Notify controller that group join failed
    onGroupJoinFailed();
  }

  bool _wasInGroupAtLastUpdate = false;

  void _handleStateUpdate(Map<String, dynamic> data) {
    final stateStr = data['State'] as String?;
    final reasonStr = data['Reason'] as String?;
    final positionTicks = data['PositionTicks'] as int? ?? 0;
    final newGroupState = _parseGroupState(stateStr);
    final reason = SyncPlayStateReason.fromWire(reasonStr);

    onStateUpdate((state) => state.copyWith(
          groupState: newGroupState,
          stateReason: reasonStr,
          positionTicks: positionTicks,
        ));

    log('SyncPlay: State update: $stateStr (reason: $reasonStr, positionTicks: $positionTicks)');

    if (newGroupState == SyncPlayGroupState.waiting) {
      _handleWaitingState(reason);
    }

    // Per docs: when state becomes Playing, ensure player is actually
    // playing (recover if Unpause was missed).
    if (newGroupState == SyncPlayGroupState.playing) {
      onStateUpdateToPlaying?.call();
    }
  }

  void _handleWaitingState(SyncPlayStateReason? reason) {
    if (reason == SyncPlayStateReason.buffer) {
      // Per spec: another client is buffering — pause locally first, then
      // report ready so the server knows we're aligned.
      final pauseFuture = onLocalPauseForBuffer?.call() ?? Future<void>.value();
      pauseFuture.then((_) {
        if (!isBuffering()) {
          reportReady(isPlaying: true);
        }
      });
      return;
    }
    if (reason == SyncPlayStateReason.unpause) {
      if (!isBuffering()) {
        reportReady(isPlaying: true);
      }
    }
  }

  void _handlePlayQueue(Map<String, dynamic> data, SyncPlayState currentState) {
    final playlist = data['Playlist'] as List? ?? [];
    final playingItemIndex = data['PlayingItemIndex'] as int? ?? 0;
    final startPositionTicks = data['StartPositionTicks'] as int? ?? 0;
    final isPlayingNow = data['IsPlaying'] as bool? ?? false;
    final reason = data['Reason'] as String?;

    String? playingItemId;
    String? playlistItemId;

    if (playlist.isNotEmpty && playingItemIndex < playlist.length) {
      final item = playlist[playingItemIndex] as Map<String, dynamic>;
      playingItemId = item['ItemId'] as String?;
      playlistItemId = item['PlaylistItemId'] as String?;
    }

    final previousItemId = currentState.playingItemId;

    onStateUpdate((state) => state.copyWith(
          playingItemId: playingItemId,
          playlistItemId: playlistItemId,
          positionTicks: startPositionTicks,
        ));

    log('SyncPlay: PlayQueue update - playing: $playingItemId (reason: $reason, isPlaying: $isPlayingNow, previousItemId: $previousItemId)');
    if (reason == 'NewPlaylist') onNewPlaylist?.call(playlist.isEmpty);

    // Trigger playback for NewPlaylist/SetCurrentItem/NextItem/PreviousItem regardless of
    // whether the item changed (the same user who set the queue also receives the update
    // and needs to start playing).
    final shouldTrigger = playingItemId != null &&
        (reason == 'NewPlaylist' ||
            reason == 'SetCurrentItem' ||
            reason == 'NextItem' ||
            reason == 'PreviousItem' ||
            (playingItemId != previousItemId && isPlayingNow));

    log('SyncPlay: shouldTrigger=$shouldTrigger (reason: $reason)');

    if (shouldTrigger) {
      log('SyncPlay: Triggering playback for item: $playingItemId');
      startPlayback(playingItemId, startPositionTicks);
    }
  }

  SyncPlayGroupState _parseGroupState(String? state) {
    switch (state?.toLowerCase()) {
      case 'idle':
        return SyncPlayGroupState.idle;
      case 'waiting':
        return SyncPlayGroupState.waiting;
      case 'paused':
        return SyncPlayGroupState.paused;
      case 'playing':
        return SyncPlayGroupState.playing;
      default:
        return SyncPlayGroupState.idle;
    }
  }
}

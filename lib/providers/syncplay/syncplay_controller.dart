import 'dart:async';
import 'dart:developer' as developer;

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/router_provider.dart';
import 'package:fladder/providers/syncplay/handlers/syncplay_command_handler.dart';
import 'package:fladder/providers/syncplay/handlers/syncplay_message_handler.dart';
import 'package:fladder/providers/syncplay/time_sync_service.dart';
import 'package:fladder/providers/syncplay/websocket_manager.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller for SyncPlay synchronized playback
class SyncPlayController {
  static const bool _verboseSyncPlayLogs = false;

  SyncPlayController(this._ref) {
    _commandHandler = SyncPlayCommandHandler(
      timeSync: () => _timeSync,
      onStateUpdate: _updateStateWith,
    );
    _messageHandler = SyncPlayMessageHandler(
      onStateUpdate: _updateStateWith,
      reportReady: ({bool isPlaying = true}) => reportReady(isPlaying: isPlaying),
      startPlayback: _startPlayback,
      isBuffering: () => _commandHandler.isBuffering?.call() ?? false,
      getContext: () => getNavigatorKey(_ref)?.currentContext,
      onGroupJoined: _onGroupJoined,
      onGroupJoinFailed: _onGroupJoinFailed,
      onGroupLeftOrKicked: _onGroupLeftOrKicked,
      onStateUpdateToPlaying: _onStateUpdateToPlaying,
    );
  }

  final Ref _ref;

  WebSocketManager? _wsManager;
  TimeSyncService? _timeSync;
  StreamSubscription? _wsMessageSubscription;
  StreamSubscription? _wsStateSubscription;
  Timer? _syncCorrectionTimer;

  late final SyncPlayCommandHandler _commandHandler;
  late final SyncPlayMessageHandler _messageHandler;

  SyncPlayState _state = SyncPlayState();
  final _stateController = StreamController<SyncPlayState>.broadcast();

  Stream<SyncPlayState> get stateStream => _stateController.stream;

  SyncPlayState get state => _state;

  // Lifecycle state for reconnection
  String? _lastGroupId;
  bool _wasConnected = false;

  // Completer for waiting on group join confirmation
  Completer<bool>? _joinGroupCompleter;

  // Player callbacks (delegated to command handler)
  set onPlay(SyncPlayPlayerCallback? callback) => _commandHandler.onPlay = callback;

  set onPause(SyncPlayPlayerCallback? callback) => _commandHandler.onPause = callback;

  set onSeek(SyncPlaySeekCallback? callback) => _commandHandler.onSeek = callback;

  set onStop(SyncPlayPlayerCallback? callback) => _commandHandler.onStop = callback;

  set getPositionTicks(SyncPlayPositionCallback? callback) => _commandHandler.getPositionTicks = callback;

  set isPlaying(bool Function()? callback) => _commandHandler.isPlaying = callback;

  set isBuffering(bool Function()? callback) => _commandHandler.isBuffering = callback;

  set onSeekRequested(SyncPlaySeekCallback? callback) => _commandHandler.onSeekRequested = callback;

  set onReportReady(SyncPlayReportReadyCallback? callback) => _commandHandler.onReportReady = callback;

  set onSetSpeed(SyncPlaySetSpeedCallback? callback) => _commandHandler.onSetSpeed = callback;

  set hasPlaybackRate(bool Function()? callback) => _commandHandler.hasPlaybackRate = callback;

  void log(String message) {
    final isImportant = message.contains('Failed') || message.contains('Error') || message.contains('Cannot');
    if (_verboseSyncPlayLogs || isImportant) {
      developer.log(message);
    }
  }

  /// Mark that a SyncPlay command was executed locally.
  /// Used by player-side cooldown logic to avoid feedback loops.
  void markCommandExecuted([DateTime? at]) {
    _updateStateWith((state) => state.copyWith(
          lastCommandTime: at ?? DateTime.now().toUtc(),
        ));
  }

  /// Update buffering/reloading status used by SyncPlay integration.
  void setPlayerBufferingState(bool isBuffering) {
    if (isBuffering) {
      _syncCorrectionTimer?.cancel();
      _syncCorrectionTimer = null;
      final setSpeed = _commandHandler.onSetSpeed;
      if (setSpeed != null) {
        unawaited(
          setSpeed(1.0).catchError((Object error, StackTrace stackTrace) {
            log('SyncPlay: Failed to reset speed while buffering: $error');
          }),
        );
      }
      _updateStateWith((state) => state.copyWith(
            correctionState: state.correctionState.copyWith(
              playerIsBuffering: true,
              syncEnabled: false,
              activeStrategy: SyncCorrectionStrategy.none,
            ),
          ));
      return;
    }

    _updateStateWith((state) => state.copyWith(
          correctionState: state.correctionState.copyWith(
            playerIsBuffering: false,
            syncEnabled: true,
          ),
        ));
  }

  /// Reset correction strategy/state when commands are cleared, on stop,
  /// or around rejoin flows.
  void resetCorrectionState({
    String reason = 'reset',
    bool syncEnabled = true,
  }) {
    _syncCorrectionTimer?.cancel();
    _syncCorrectionTimer = null;

    final setSpeed = _commandHandler.onSetSpeed;
    if (setSpeed != null) {
      unawaited(
        setSpeed(1.0).catchError((Object error, StackTrace stackTrace) {
          log('SyncPlay: Failed to reset speed during correction reset: $error');
        }),
      );
    }
    _commandHandler.clearLastCommand();

    log('SyncPlay: Reset correction state ($reason)');
    _updateStateWith((state) => state.copyWith(
          correctionState: state.correctionState.copyWith(
            activeStrategy: SyncCorrectionStrategy.none,
            syncEnabled: syncEnabled,
            playbackDiffMillis: 0,
            syncAttempts: 0,
          ),
        ));
  }

  /// Update current playback drift against estimated SyncPlay server time.
  ///
  /// Drift is computed as:
  /// `estimatedServerPositionTicks - currentLocalPositionTicks`.
  /// Positive means local player is behind, negative means ahead.
  void updatePlaybackDrift({
    required int currentPositionTicks,
    DateTime? at,
  }) {
    if (!_commandHandler.canAttemptSyncCorrection(_state)) {
      return;
    }

    final lastCommand = _commandHandler.lastCommand;
    if (lastCommand == null) {
      return;
    }

    final when = DateTime.tryParse(lastCommand.when);
    if (when == null) {
      return;
    }

    final now = (at ?? DateTime.now().toUtc());
    final remoteNow = _timeSync?.localDateToRemote(now) ?? now;
    final elapsedMs = remoteNow.difference(when).inMilliseconds;

    final estimatedServerTicks = lastCommand.positionTicks + millisecondsToTicks(elapsedMs);
    final diffTicks = estimatedServerTicks - currentPositionTicks;
    final diffMillis = ticksToMilliseconds(diffTicks).toDouble();
    final correctionConfig = _state.correctionConfig;
    final correctionState = _state.correctionState;
    final strategy = selectSyncCorrectionStrategy(
      config: correctionConfig,
      state: correctionState,
      diffMillis: diffMillis,
      hasPlaybackRate: _commandHandler.hasPlaybackRate?.call() == true,
    );

    if (strategy == SyncCorrectionStrategy.speedToSync) {
      _applySpeedToSync(
        diffMillis: diffMillis,
        config: correctionConfig,
        now: now,
      );
      return;
    }

    if (strategy == SyncCorrectionStrategy.skipToSync) {
      _applySkipToSync(
        diffMillis: diffMillis,
        targetPositionTicks: estimatedServerTicks,
        config: correctionConfig,
        now: now,
      );
      return;
    }

    _updateStateWith((state) => state.copyWith(
          correctionState: state.correctionState.copyWith(
            playbackDiffMillis: diffMillis,
            lastSyncAt: now,
          ),
        ));
  }

  void _applySpeedToSync({
    required double diffMillis,
    required SyncCorrectionConfig config,
    required DateTime now,
  }) {
    final setSpeed = _commandHandler.onSetSpeed;
    if (setSpeed == null) {
      return;
    }

    var speedToSyncTimeMs = config.speedToSyncDurationMs;
    const minSpeed = 0.2;
    if (diffMillis <= -speedToSyncTimeMs * minSpeed) {
      speedToSyncTimeMs = diffMillis.abs() / (1.0 - minSpeed);
    }

    final rawSpeed = 1.0 + (diffMillis / speedToSyncTimeMs);
    final speed = rawSpeed < minSpeed ? minSpeed : rawSpeed;
    final resetDuration = Duration(
      milliseconds: speedToSyncTimeMs.round(),
    );

    _syncCorrectionTimer?.cancel();
    unawaited(
      setSpeed(speed).catchError((Object error, StackTrace stackTrace) {
        log('SyncPlay: Failed to apply SpeedToSync rate: $error');
      }),
    );
    log(
      'SyncPlay: SpeedToSync applied '
      '(speed=${speed.toStringAsFixed(2)}, '
      'diffMs=${diffMillis.toStringAsFixed(1)})',
    );

    _updateStateWith((state) => state.copyWith(
          correctionState: state.correctionState.copyWith(
            playbackDiffMillis: diffMillis,
            lastSyncAt: now,
            activeStrategy: SyncCorrectionStrategy.speedToSync,
            syncEnabled: false,
            syncAttempts: state.correctionState.syncAttempts + 1,
          ),
        ));

    _syncCorrectionTimer = Timer(resetDuration, () {
      final resetSpeed = _commandHandler.onSetSpeed;
      if (resetSpeed != null) {
        unawaited(
          resetSpeed(1.0).catchError((Object error, StackTrace stackTrace) {
            log('SyncPlay: Failed to reset speed after SpeedToSync: $error');
          }),
        );
      }
      _updateStateWith((state) => state.copyWith(
            correctionState: state.correctionState.copyWith(
              activeStrategy: SyncCorrectionStrategy.none,
              syncEnabled: true,
            ),
          ));
    });
  }

  void _applySkipToSync({
    required double diffMillis,
    required int targetPositionTicks,
    required SyncCorrectionConfig config,
    required DateTime now,
  }) {
    final seek = _commandHandler.onSeek;
    if (seek == null) {
      return;
    }

    _syncCorrectionTimer?.cancel();
    unawaited(
      seek(targetPositionTicks).catchError((Object error, StackTrace stackTrace) {
        log('SyncPlay: Failed to apply SkipToSync seek: $error');
      }),
    );
    log(
      'SyncPlay: SkipToSync applied '
      '(targetTicks=$targetPositionTicks, '
      'diffMs=${diffMillis.toStringAsFixed(1)})',
    );

    _updateStateWith((state) => state.copyWith(
          correctionState: state.correctionState.copyWith(
            playbackDiffMillis: diffMillis,
            lastSyncAt: now,
            activeStrategy: SyncCorrectionStrategy.skipToSync,
            syncEnabled: false,
            syncAttempts: state.correctionState.syncAttempts + 1,
          ),
        ));

    final cooldownDuration = Duration(
      milliseconds: (config.maxDelaySpeedToSyncMs / 2.0).round(),
    );
    _syncCorrectionTimer = Timer(cooldownDuration, () {
      _updateStateWith((state) => state.copyWith(
            correctionState: state.correctionState.copyWith(
              activeStrategy: SyncCorrectionStrategy.none,
              syncEnabled: true,
            ),
          ));
    });
  }

  JellyfinOpenApi get _api => _ref.read(jellyApiProvider).api;

  /// Initialize and connect to SyncPlay
  Future<void> connect() async {
    final user = _ref.read(userProvider);
    if (user == null) {
      log('SyncPlay: Cannot connect without user');
      return;
    }

    final serverUrl = _ref.read(serverUrlProvider);
    if (serverUrl == null || serverUrl.isEmpty) {
      log('SyncPlay: Cannot connect without server URL');
      return;
    }

    // Initialize time sync
    _timeSync = TimeSyncService(_api);
    _timeSync!.start();

    // Initialize WebSocket
    log('SyncPlay: Initializing WebSocket with deviceId: ${user.credentials.deviceId}');
    _wsManager = WebSocketManager(
      serverUrl: serverUrl,
      token: user.credentials.token,
      deviceId: user.credentials.deviceId,
    );

    _wsStateSubscription = _wsManager!.connectionState.listen(_handleConnectionState);
    _wsMessageSubscription = _wsManager!.messages.listen(_handleMessage);

    await _wsManager!.connect();
  }

  /// Disconnect from SyncPlay
  Future<void> disconnect() async {
    resetCorrectionState(
      reason: 'disconnect',
      syncEnabled: false,
    );
    await leaveGroup();
    _commandHandler.cancelPendingCommands();
    _wsMessageSubscription?.cancel();
    _wsStateSubscription?.cancel();
    _timeSync?.dispose();
    await _wsManager?.dispose();
    _wsManager = null;
    _timeSync = null;
    _updateState(SyncPlayState());
  }

  /// List available SyncPlay groups
  Future<List<GroupInfoDto>> listGroups() async {
    try {
      final response = await _api.syncPlayListGet();
      return response.body ?? [];
    } catch (e) {
      log('SyncPlay: Failed to list groups: $e');
      return [];
    }
  }

  /// Create a new SyncPlay group
  Future<GroupInfoDto?> createGroup(String groupName) async {
    try {
      final response = await _api.syncPlayNewPost(
        body: NewGroupRequestDto(groupName: groupName),
      );
      return response.body;
    } catch (e) {
      log('SyncPlay: Failed to create group: $e');
      return null;
    }
  }

  /// Join an existing SyncPlay group
  /// Returns true only after receiving GroupJoined confirmation from WebSocket
  Future<bool> joinGroup(String groupId) async {
    // Check if already in a group
    if (_state.isInGroup) {
      log('SyncPlay: Already in a group, leaving first...');
      await leaveGroup();
    }

    // Check if WebSocket is connected
    if (!_state.isConnected) {
      log('SyncPlay: WebSocket not connected, cannot join group');
      return false;
    }

    try {
      log('SyncPlay: Joining group: $groupId');

      // Create completer to wait for GroupJoined confirmation
      _joinGroupCompleter = Completer<bool>();

      await _api.syncPlayJoinPost(
        body: JoinGroupRequestDto(groupId: groupId),
      );
      _lastGroupId = groupId;
      log('SyncPlay: Join request sent, waiting for confirmation...');

      // Wait for GroupJoined message with timeout
      final confirmed = await _joinGroupCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          log('SyncPlay: Timeout waiting for GroupJoined confirmation');
          return false;
        },
      );

      _joinGroupCompleter = null;

      if (confirmed) {
        log('SyncPlay: Group join confirmed');
      } else {
        log('SyncPlay: Group join not confirmed');
        _lastGroupId = null;
      }

      return confirmed;
    } catch (e) {
      log('SyncPlay: Failed to join group: $e');
      _joinGroupCompleter?.complete(false);
      _joinGroupCompleter = null;
      return false;
    }
  }

  /// Called by message handler when GroupJoined is received
  void _onGroupJoined() {
    resetCorrectionState(
      reason: 'group_joined',
      syncEnabled: true,
    );
    _joinGroupCompleter?.complete(true);
  }

  /// Called by message handler when NotInGroup/GroupDoesNotExist is received
  void _onGroupJoinFailed() {
    _joinGroupCompleter?.complete(false);
  }

  /// Called when we leave or are kicked; cancel pending commands and clear processing so playback is not stuck.
  void _onGroupLeftOrKicked() {
    _commandHandler.cancelPendingCommands();
    resetCorrectionState(
      reason: 'group_left_or_kicked',
      syncEnabled: false,
    );
    _updateStateWith((s) => s.copyWith(
          isProcessingCommand: false,
          processingCommandType: null,
        ));
  }

  /// When server reports Playing, ensure player is actually playing (per docs: recover if Unpause command was missed).
  void _onStateUpdateToPlaying() {
    if (_commandHandler.isPlaying?.call() != true) {
      log('SyncPlay: State is Playing but player not playing, triggering play');
      _commandHandler.onPlay?.call();
    }
  }

  /// Leave the current SyncPlay group.
  /// Resets processing state and cancels pending commands so playback is not stuck (per docs).
  Future<void> leaveGroup() async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      await _api.syncPlayLeavePost();
      _lastGroupId = null;
      _commandHandler.cancelPendingCommands();
      resetCorrectionState(
        reason: 'leave_group',
        syncEnabled: false,
      );
      _updateState(_state.copyWith(
        isInGroup: false,
        groupId: null,
        groupName: null,
        groupState: SyncPlayGroupState.idle,
        participants: [],
        isProcessingCommand: false,
        processingCommandType: null,
        positionTicks: 0,
        playlistItemId: null,
      ));
      log('SyncPlay: Left group, state reset');
    } catch (e) {
      log('SyncPlay: Failed to leave group: $e');
      // Still reset local state so we are not stuck
      _commandHandler.cancelPendingCommands();
      resetCorrectionState(
        reason: 'leave_group_failed_local_reset',
        syncEnabled: false,
      );
      _updateState(_state.copyWith(
        isInGroup: false,
        groupId: null,
        groupName: null,
        groupState: SyncPlayGroupState.idle,
        participants: [],
        isProcessingCommand: false,
        processingCommandType: null,
      ));
    }
  }

  /// Request pause
  Future<void> requestPause() async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      await _api.syncPlayPausePost();
    } catch (e) {
      log('SyncPlay: Failed to request pause: $e');
    }
  }

  /// Request unpause/play (server will move to Waiting until all clients report Ready, then broadcast Unpause).
  Future<void> requestUnpause() async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      log('SyncPlay: Sending Unpause request');
      await _api.syncPlayUnpausePost();
    } catch (e) {
      log('SyncPlay: Failed to request unpause: $e');
    }
  }

  /// Request seek
  Future<void> requestSeek(int positionTicks) async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      await _api.syncPlaySeekPost(
        body: SeekRequestDto(positionTicks: positionTicks),
      );
    } catch (e) {
      log('SyncPlay: Failed to request seek: $e');
    }
  }

  /// Report buffering state
  Future<void> reportBuffering() async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      final when = _timeSync?.localDateToRemote(DateTime.now().toUtc());
      await _api.syncPlayBufferingPost(
        body: BufferRequestDto(
          when: when,
          positionTicks: _commandHandler.getPositionTicks?.call() ?? 0,
          isPlaying: false,
          playlistItemId: _state.playlistItemId,
        ),
      );
    } catch (e) {
      log('SyncPlay: Failed to report buffering: $e');
    }
  }

  /// Report ready state (required for server to broadcast Unpause when in Waiting).
  Future<void> reportReady({bool isPlaying = true}) async {
    if (!_state.isInGroup) {
      return;
    }
    try {
      final when = _timeSync?.localDateToRemote(DateTime.now().toUtc());
      final ticks = _commandHandler.getPositionTicks?.call() ?? 0;
      log('SyncPlay: Reporting Ready (isPlaying=$isPlaying, positionTicks=$ticks)');
      await _api.syncPlayReadyPost(
        body: ReadyRequestDto(
          when: when,
          positionTicks: ticks,
          isPlaying: isPlaying,
          playlistItemId: _state.playlistItemId,
        ),
      );
    } catch (e) {
      log('SyncPlay: Failed to report ready: $e');
    }
  }

  /// Report ping to server
  Future<void> reportPing() async {
    if (!_state.isInGroup || _timeSync == null) {
      return;
    }
    try {
      await _api.syncPlayPingPost(
        body: PingRequestDto(ping: _timeSync!.ping.inMilliseconds),
      );
    } catch (e) {
      log('SyncPlay: Failed to report ping: $e');
    }
  }

  /// Set a new queue/playlist
  Future<void> setNewQueue({
    required List<String> itemIds,
    int playingItemPosition = 0,
    int startPositionTicks = 0,
  }) async {
    if (!_state.isInGroup) {
      log('SyncPlay: Cannot set queue - not in group');
      return;
    }
    try {
      final body = PlayRequestDto(
        playingQueue: itemIds,
        playingItemPosition: playingItemPosition,
        startPositionTicks: startPositionTicks,
      );
      log('SyncPlay: Setting new queue: ${body.toJson()}');
      final response = await _api.syncPlaySetNewQueuePost(body: body);
      log('SyncPlay: SetNewQueue response: ${response.statusCode} - ${response.body}');
    } catch (e) {
      log('SyncPlay: Failed to set new queue: $e');
    }
  }

  void _handleConnectionState(WebSocketConnectionState wsState) {
    log('SyncPlay: WebSocket connection state: $wsState');
    final isConnected = wsState == WebSocketConnectionState.connected;
    _updateState(_state.copyWith(isConnected: isConnected));
    log('SyncPlay: isConnected updated to: $isConnected');
  }

  void _handleMessage(Map<String, dynamic> message) {
    final messageType = message['MessageType'] as String?;
    final data = message['Data'];

    log('SyncPlay: Received WebSocket message: $messageType');

    switch (messageType) {
      case 'SyncPlayCommand':
        final cmd = (data as Map<String, dynamic>)['Command'] as String?;
        log('SyncPlay: Received SyncPlayCommand: $cmd');
        _commandHandler.handleCommand(data, _state);
        break;
      case 'SyncPlayGroupUpdate':
        log('SyncPlay: GroupUpdate data: $data');
        _messageHandler.handleGroupUpdate(data as Map<String, dynamic>, _state);
        break;
      default:
        // Log unhandled message types for debugging
        if (messageType?.startsWith('SyncPlay') == true) {
          log('SyncPlay: Unhandled SyncPlay message type: $messageType');
        }
    }
  }

  /// Start playback of an item from SyncPlay
  Future<void> _startPlayback(String itemId, int startPositionTicks) async {
    log('SyncPlay: _startPlayback called for item: $itemId, ticks: $startPositionTicks');

    try {
      // Fetch the item from Jellyfin
      log('SyncPlay: Fetching item from API...');
      final api = _ref.read(jellyApiProvider);
      final itemResponse = await api.usersUserIdItemsItemIdGet(itemId: itemId);
      final itemModel = itemResponse.body;

      if (itemModel == null) {
        log('SyncPlay: Failed to fetch item $itemId - response body was null');
        return;
      }
      log('SyncPlay: Fetched item: ${itemModel.name}');

      // Create playback model (context is optional - null for SyncPlay auto-play)
      log('SyncPlay: Creating playback model...');
      final playbackHelper = _ref.read(playbackModelHelper);
      final startPosition = Duration(microseconds: startPositionTicks ~/ 10);

      final playbackModel = await playbackHelper.createPlaybackModel(
        null, // No context needed for SyncPlay
        itemModel,
        startPosition: startPosition,
      );

      if (playbackModel == null) {
        log('SyncPlay: Failed to create playback model for $itemId');
        return;
      }
      log('SyncPlay: Playback model created successfully');

      // Load and play
      log('SyncPlay: Loading playback item...');
      final loadedCorrectly = await _ref.read(videoPlayerProvider.notifier).loadPlaybackItem(
            playbackModel,
            startPosition,
          );

      if (!loadedCorrectly) {
        log('SyncPlay: Failed to load playback item $itemId');
        return;
      }
      log('SyncPlay: Playback item loaded successfully');

      // Set state to fullScreen
      _ref.read(mediaPlaybackProvider.notifier).update(
            (state) => state.copyWith(state: VideoPlayerState.fullScreen),
          );
      log('SyncPlay: Set state to fullScreen');

      // Open the player - this handles both native (Android TV) and Flutter players correctly
      // For Android TV (NativePlayer), this launches the native activity
      // For other platforms, this opens the Flutter VideoPlayer
      final navigatorKey = getNavigatorKey(_ref);
      final context = navigatorKey?.currentContext;
      log('SyncPlay: Navigator context: ${context != null ? "exists" : "null"}');

      if (context != null) {
        await _ref.read(videoPlayerProvider.notifier).openPlayer(context);
        log('SyncPlay: Successfully opened player for $itemId');
      } else {
        log('SyncPlay: No navigator context available, player loaded but not opened fullscreen');
      }
    } catch (e, stackTrace) {
      log('SyncPlay: Error starting playback: $e\n$stackTrace');
    }
  }

  void _updateState(SyncPlayState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _updateStateWith(SyncPlayState Function(SyncPlayState) updater) {
    _state = updater(_state);
    _stateController.add(_state);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle Handling (for mobile background/resume)
  // ─────────────────────────────────────────────────────────────────────────

  /// Handle app lifecycle state changes
  /// Call this from a WidgetsBindingObserver when app state changes
  Future<void> handleAppLifecycleChange(AppLifecycleState lifecycleState) async {
    // On web, we want to stay connected even in background and avoid forced reconnection on resume.
    if (kIsWeb) {
      return;
    }

    switch (lifecycleState) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // App going to background - remember state for reconnection
        _wasConnected = _wsManager?.currentState == WebSocketConnectionState.connected;
        log('SyncPlay: App paused, wasConnected=$_wasConnected, lastGroupId=$_lastGroupId');
        break;

      case AppLifecycleState.resumed:
        // App returning to foreground - attempt reconnection if needed
        log('SyncPlay: App resumed, wasConnected=$_wasConnected, isInGroup=${_state.isInGroup}');
        if (_wasConnected || _state.isInGroup) {
          await _handleAppResume();
        }
        break;

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // No action needed
        break;
    }
  }

  /// Handle app resume - reconnect WebSocket and optionally rejoin group
  Future<void> _handleAppResume() async {
    // Force reconnect WebSocket
    if (_wsManager != null) {
      log('SyncPlay: Force reconnecting WebSocket on resume');
      await _wsManager!.forceReconnect();

      // Wait for connection to establish
      await Future.delayed(const Duration(milliseconds: 500));

      // Restart time sync if it was active
      if (_timeSync != null) {
        _timeSync!.start();
        await _timeSync!.forceUpdate();
      }

      // If we were in a group but got disconnected, try to rejoin
      if (_lastGroupId != null && !_state.isInGroup) {
        resetCorrectionState(
          reason: 'pre_rejoin',
          syncEnabled: false,
        );
        log('SyncPlay: Attempting to rejoin group $_lastGroupId');
        final success = await joinGroup(_lastGroupId!);
        if (!success) {
          log('SyncPlay: Failed to rejoin group, clearing lastGroupId');
          _lastGroupId = null;
        }
      }
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    _commandHandler.dispose();
    await disconnect();
    await _stateController.close();
  }
}

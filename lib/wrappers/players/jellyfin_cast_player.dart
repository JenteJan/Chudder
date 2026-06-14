import 'dart:async';

import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:fladder/wrappers/players/cast/cast_message_transport.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_receiver_player.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_channel.dart';

final _log = Logger('Cast.jellyfin.native');

/// [CastMessageTransport] over the native Google Cast SDK: custom-namespace
/// messaging via the `flutter_chrome_cast` MethodChannel bridge
/// ([JellyfinCastChannel]), and device volume / teardown via the SDK's session
/// manager.
class NativeCastTransport implements CastMessageTransport {
  @override
  Stream<String> get messages => JellyfinCastChannel.instance.messages;

  @override
  Future<void> sendMessage(String json) =>
      JellyfinCastChannel.instance.sendMessage(jellyfinCastNamespace, json);

  @override
  Future<void> setVolume(double level) async {
    GoogleCastSessionManager.instance.setDeviceVolume(level);
  }

  @override
  Future<void> dispose() async {
    try {
      await GoogleCastSessionManager.instance.endSessionAndStopCasting();
    } catch (_) {}
  }
}

/// The native (mobile) Jellyfin Cast receiver player. Adds the SDK-specific
/// timing logic on top of [JellyfinReceiverPlayer]: rejoin detection,
/// media-status-as-acknowledgment, and stop-before-PlayNow for a live receiver.
class JellyfinCastPlayer extends JellyfinReceiverPlayer {
  JellyfinCastPlayer._(super.transport, super.context, super.deviceName);

  // Set on any sign of life (custom message or active media status); never
  // reset — a live receiver has its listener registered, so one send suffices.
  bool _receiverAlive = false;
  CastMediaPlayerState? _lastMediaState;
  Completer<void>? _stopCompleter;

  /// Connects to [device] (launching app id F007D354, set at SDK init) and
  /// registers the Jellyfin message namespace.
  static Future<JellyfinCastPlayer> connect(
    GoogleCastDevice device,
    JellyfinCastContext context, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.friendlyName}"');
    final sessions = GoogleCastSessionManager.instance;

    final connected = Completer<void>();
    late final StreamSubscription sub;
    sub = sessions.currentSessionStream.listen((session) {
      if (session?.connectionState == GoogleCastConnectState.connected && !connected.isCompleted) {
        connected.complete();
      }
    });

    try {
      await sessions.startSessionWithDevice(device);
      if (sessions.connectionState != GoogleCastConnectState.connected) {
        await connected.future.timeout(timeout);
      }
    } finally {
      await sub.cancel();
    }

    await JellyfinCastChannel.instance.registerNamespace(jellyfinCastNamespace);
    _log.info('Jellyfin cast session connected to "${device.friendlyName}"');
    final player = JellyfinCastPlayer._(NativeCastTransport(), context, device.friendlyName);

    // A rejoined receiver announces itself right after connect, but the first
    // loadVideo runs before that lands — catch it here so loadVideo takes the
    // safe stop-before-PlayNow path instead of treating a live receiver as a
    // cold boot (which races its internal stop event and wedges the display).
    try {
      await JellyfinCastChannel.instance.messages.first.timeout(const Duration(milliseconds: 1500));
      player._receiverAlive = true;
      _log.info('Receiver is already live (rejoined session)');
    } on TimeoutException {
      // Fresh receiver boot — the PlayNow retry schedule handles its startup.
    }
    return player;
  }

  @override
  Future<void> onInit() async {
    // The Cast media status reacts to PlayNow (LOADING) well before the
    // receiver's first custom message — use it as the earliest acknowledgment
    // so the retry loop stops before it can restart playback, and as the idle
    // signal that confirms a Stop.
    subs.add(GoogleCastRemoteMediaClient.instance.mediaStatusStream.listen((status) {
      final state = status?.playerState;
      _lastMediaState = state;
      if (state == CastMediaPlayerState.loading ||
          state == CastMediaPlayerState.buffering ||
          state == CastMediaPlayerState.playing) {
        markAcknowledged('media status ${state!.name}');
      }
      if (state == CastMediaPlayerState.idle && _stopCompleter?.isCompleted == false) {
        _stopCompleter?.complete();
      }
    }));
  }

  @override
  void markAcknowledged(String via) {
    _receiverAlive = true;
    super.markAcknowledged(via);
  }

  /// Whether the receiver currently has a stream (a rejoined session can carry
  /// a zombie stream from a previous cast).
  bool get _mediaActive =>
      _lastMediaState == CastMediaPlayerState.loading ||
      _lastMediaState == CastMediaPlayerState.buffering ||
      _lastMediaState == CastMediaPlayerState.playing ||
      _lastMediaState == CastMediaPlayerState.paused;

  @override
  Future<void> beginPlayback() async {
    if (!_receiverAlive) {
      startPlayNowAttempts();
      return;
    }
    // A live receiver may still hold a previous stream; PlayNow on top of it
    // races the late stop event and wedges the display. Always stop and wait
    // for idle first (a cheap no-op on an already-idle receiver), then a single
    // PlayNow — the listener is registered, so a duplicate would restart it.
    _log.info('Stopping any active stream on "$deviceName" before PlayNow${_mediaActive ? ' (media active)' : ''}');
    await sendCommand('Stop', {});
    await _waitForReceiverStop(const Duration(seconds: 3));
    _log.info('PlayNow → "$deviceName" (receiver alive, single send)');
    final options = playNowOptions;
    if (options != null) await sendCommand('PlayNow', options);
  }

  @override
  Future<void> awaitReceiverStop() => _waitForReceiverStop(const Duration(seconds: 5));

  @override
  void onReport(ReceiverReport report) {
    if (report.type == 'playbackstop' && _stopCompleter?.isCompleted == false) {
      _stopCompleter?.complete();
    }
  }

  /// Completes when the receiver confirms the current stream stopped (its
  /// `playbackstop` message or an idle media status), or after [timeout].
  Future<void> _waitForReceiverStop(Duration timeout) async {
    final completer = Completer<void>();
    _stopCompleter = completer;
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      _log.fine('Receiver did not confirm stop within ${timeout.inSeconds}s — continuing');
    } finally {
      _stopCompleter = null;
    }
    // Brief settle so the receiver's stop UI flip lands before our new load.
    await Future.delayed(const Duration(milliseconds: 400));
  }
}

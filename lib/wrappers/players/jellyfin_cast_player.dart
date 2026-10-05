import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:logging/logging.dart';

import 'package:chudder/wrappers/players/cast/cast_message_transport.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_receiver_player.dart';
import 'package:chudder/wrappers/players/jellyfin_cast_channel.dart';

final _log = Logger('Cast.jellyfin.native');

/// [CastMessageTransport] over the native Google Cast SDK: custom-namespace
/// messaging via the `flutter_chrome_cast` MethodChannel bridge
/// ([JellyfinCastChannel]), and device volume / teardown via the SDK's session
/// manager.
class NativeCastTransport implements CastMessageTransport {
  @override
  Stream<String> get messages => JellyfinCastChannel.instance.messages;

  /// Android relays the SDK's session lifecycle natively; a suspension there is
  /// transient (the SDK reconnects on its own) and only an end or a failed
  /// resume is final. iOS has no such bridge — the provider watches the
  /// plugin's session stream there instead.
  @override
  Stream<CastLinkEvent> get linkEvents => JellyfinCastChannel.instance.sessionEvents
      .map((event) => switch (event) {
            CastSessionEvent.suspended => CastLinkEvent.suspended,
            CastSessionEvent.resumed => CastLinkEvent.resumed,
            CastSessionEvent.ended || CastSessionEvent.resumeFailed => CastLinkEvent.ended,
            CastSessionEvent.started || CastSessionEvent.startFailed => null,
          })
      .where((event) => event != null)
      .cast<CastLinkEvent>();

  @override
  Future<void> sendMessage(String json) => JellyfinCastChannel.instance.sendMessage(jellyfinCastNamespace, json);

  @override
  Future<void> setVolume(double level) async {
    GoogleCastSessionManager.instance.setDeviceVolume(level);
  }

  @override
  Future<void> close({required bool stopReceiver}) async {
    // Bounded: if the platform channel never replies (session already dead,
    // SDK wedged), teardown must still complete or the whole player swap —
    // and with it disconnect() — hangs forever.
    final sessions = GoogleCastSessionManager.instance;
    try {
      await (stopReceiver ? sessions.endSessionAndStopCasting() : sessions.endSession())
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      _log.warning('Ending the Cast session did not complete cleanly: $error');
    }
  }
}

/// The native (mobile) Jellyfin Cast receiver player. Adds the SDK-specific
/// timing logic on top of [JellyfinReceiverPlayer]: rejoin detection,
/// media-status-as-acknowledgment, and stop-before-PlayNow for a live receiver.
class JellyfinCastPlayer extends JellyfinReceiverPlayer {
  JellyfinCastPlayer._(super.transport, super.context, super.deviceName, {required super.onSessionEnded});

  // Set on any sign of life (custom message or active media status); never
  // reset — a live receiver has its listener registered, so one send suffices.
  bool _receiverAlive = false;
  CastMediaPlayerState? _lastMediaState;

  /// Connects to [device] (launching the receiver app id the SDK was set up
  /// with) and registers the Jellyfin message namespace.
  static Future<JellyfinCastPlayer> connect(
    GoogleCastDevice device,
    JellyfinCastContext context, {
    required void Function() onSessionEnded,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.friendlyName}"');
    final sessions = GoogleCastSessionManager.instance;
    final alreadyConnected = sessions.connectionState == GoogleCastConnectState.connected &&
        sessions.currentSession?.device?.deviceID == device.deviceID;

    if (!alreadyConnected) {
      final connected = Completer<void>();
      final sub = sessions.currentSessionStream.listen((session) {
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
    }
    return _open(device.friendlyName, context, onSessionEnded: onSessionEnded);
  }

  /// Attaches to the session the Cast SDK already holds — one it resumed on
  /// its own after the app was closed and opened again.
  static Future<JellyfinCastPlayer> attach(
    String deviceName,
    JellyfinCastContext context, {
    required void Function() onSessionEnded,
  }) {
    _log.info('Rejoining the Cast session on "$deviceName"');
    return _open(deviceName, context, onSessionEnded: onSessionEnded);
  }

  static Future<JellyfinCastPlayer> _open(
    String deviceName,
    JellyfinCastContext context, {
    required void Function() onSessionEnded,
  }) async {
    await JellyfinCastChannel.instance.registerNamespace(jellyfinCastNamespace);
    // Android relays the SDK's granular session lifecycle (started/suspended/
    // resumed/ended) natively; iOS has no such bridge and keeps the provider's
    // currentSessionStream fallback.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await JellyfinCastChannel.instance.startSessionMonitoring();
      } catch (error) {
        _log.warning('Could not start native session monitoring: $error');
      }
    }
    _log.info('Jellyfin cast session connected to "$deviceName"');
    final player = JellyfinCastPlayer._(NativeCastTransport(), context, deviceName, onSessionEnded: onSessionEnded);

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
      if (state == CastMediaPlayerState.idle) confirmReceiverStopped();
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
    await stopReceiverAndWait(const Duration(seconds: 3));
    _log.info('PlayNow → "$deviceName" (receiver alive, single send)');
    final options = playNowOptions;
    if (options != null) await sendCommand('PlayNow', options);
  }
}

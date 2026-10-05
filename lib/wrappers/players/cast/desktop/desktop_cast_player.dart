import 'dart:async';

import 'package:logging/logging.dart';

import 'package:chudder/wrappers/players/cast/cast_message_transport.dart';
import 'package:chudder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:chudder/wrappers/players/cast/desktop/castv2_channel.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_receiver_player.dart';

final _log = Logger('Cast.jellyfin.desktop');

/// How long to keep trying to get a dropped link back, and how far apart —
/// about a minute in all, the window in which a Wi-Fi hiccup or a sleeping
/// laptop usually comes back.
const _reconnectDelays = [
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
  Duration(seconds: 8),
  Duration(seconds: 15),
  Duration(seconds: 30),
];

/// [CastMessageTransport] over a raw CASTV2 socket — the desktop counterpart to
/// `NativeCastTransport` (mobile SDK) and `_WebCastTransport` (Cast Web Sender).
///
/// The desktop has no session manager to hold the session through a dropped
/// connection, so this does what the SDKs do: a lost link is reported as a
/// suspension and the same receiver session is rejoined, and only a session
/// the device itself ended — or one that cannot be reached for a minute —
/// ends the cast.
class DesktopCastTransport implements CastMessageTransport {
  DesktopCastTransport(this._channel, this._appId) {
    _watch(_channel);
  }

  CastV2Channel _channel;
  final String _appId;
  final _messages = StreamController<String>.broadcast();
  final _linkEvents = StreamController<CastLinkEvent>.broadcast();
  StreamSubscription<String>? _messagesSub;
  bool _closed = false;

  /// The receiver app's session on the device, for rejoining it later.
  String get sessionId => _channel.sessionId;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<CastLinkEvent> get linkEvents => _linkEvents.stream;

  void _watch(CastV2Channel channel) {
    unawaited(_messagesSub?.cancel());
    _messagesSub = channel.customMessages.listen((message) {
      if (!_messages.isClosed) _messages.add(message);
    });
    unawaited(channel.onEnded.then((reason) {
      if (_closed || !identical(channel, _channel)) return;
      switch (reason) {
        case CastChannelEnd.sessionEnded:
          _emit(CastLinkEvent.ended);
        case CastChannelEnd.connectionLost:
          unawaited(_reconnect());
        case CastChannelEnd.closedByUs:
          break;
      }
    }));
  }

  Future<void> _reconnect() async {
    final lost = _channel;
    _log.info('Link to ${lost.host} lost — rejoining session ${lost.sessionId}');
    _emit(CastLinkEvent.suspended);
    for (final delay in _reconnectDelays) {
      await Future<void>.delayed(delay);
      if (_closed) return;
      try {
        final channel = await CastV2Channel.connect(
          lost.host,
          lost.port,
          _appId,
          joinSessionId: lost.sessionId,
          timeout: const Duration(seconds: 8),
        );
        if (_closed) {
          await channel.close();
          return;
        }
        _channel = channel;
        _watch(channel);
        _log.info('Rejoined session ${lost.sessionId} on ${lost.host}');
        _emit(CastLinkEvent.resumed);
        return;
      } on CastSessionGoneException {
        _log.info('Session ${lost.sessionId} ended while the link was down');
        _emit(CastLinkEvent.ended);
        return;
      } catch (error) {
        _log.fine('Rejoin attempt failed: $error');
      }
    }
    _log.warning('Could not reach ${lost.host} again — ending the cast');
    _emit(CastLinkEvent.ended);
  }

  void _emit(CastLinkEvent event) {
    if (!_linkEvents.isClosed) _linkEvents.add(event);
  }

  @override
  Future<void> sendMessage(String json) async => _channel.sendCustom(jellyfinCastNamespace, json);

  @override
  Future<void> setVolume(double level) async => _channel.setVolume(level);

  @override
  Future<void> close({required bool stopReceiver}) async {
    if (_closed) return;
    _closed = true;
    await (stopReceiver ? _channel.stop() : _channel.close());
    await _messagesSub?.cancel();
    await _messages.close();
    await _linkEvents.close();
  }
}

/// The desktop Jellyfin Cast receiver player (Windows/Linux/macOS).
///
/// Deliberately thin, like [WebJellyfinCastPlayer]: the mobile subclass carries
/// SDK-specific timing workarounds (rejoin detection, media-status-as-ack) that
/// don't apply here, because we own the connection and know the receiver is
/// listening before we send anything.
class DesktopJellyfinCastPlayer extends JellyfinReceiverPlayer {
  DesktopJellyfinCastPlayer._(DesktopCastTransport super.transport, super.context, super.deviceName,
      {required super.onSessionEnded});

  /// The receiver session on the device, remembered so a restarted app can
  /// rejoin it.
  String get sessionId => (transport as DesktopCastTransport).sessionId;

  /// Connects to [device] with receiver app [appId], joining the app if it
  /// already runs there. With [joinSessionId] only that session is joined
  /// (after a restart of this app); a [CastSessionGoneException] says it is
  /// over.
  static Future<DesktopJellyfinCastPlayer> connect(
    CastDeviceInfo device,
    String appId,
    JellyfinCastContext context, {
    required void Function() onSessionEnded,
    String? joinSessionId,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.name}" (${device.host})');
    final channel = await CastV2Channel.connect(
      device.host,
      device.port,
      appId,
      joinSessionId: joinSessionId,
      timeout: timeout,
    );
    return DesktopJellyfinCastPlayer._(DesktopCastTransport(channel, appId), context, device.name,
        onSessionEnded: onSessionEnded);
  }
}

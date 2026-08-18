import 'dart:async';

import 'package:logging/logging.dart';

import 'package:fladder/wrappers/players/cast/cast_message_transport.dart';
import 'package:fladder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:fladder/wrappers/players/cast/desktop/castv2_channel.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_receiver_player.dart';

final _log = Logger('Cast.jellyfin.desktop');

/// [CastMessageTransport] over a raw CASTV2 socket — the desktop counterpart to
/// `NativeCastTransport` (mobile SDK) and `_WebCastTransport` (Cast Web Sender).
///
/// All the receiver-control logic lives in [JellyfinReceiverPlayer]; this only
/// moves bytes.
class DesktopCastTransport implements CastMessageTransport {
  DesktopCastTransport(this._channel, this._onSessionEnded) {
    // The socket dropping *is* the session ending on desktop — there's no
    // session manager to tell us separately.
    _closedSub = _channel.onClosed.asStream().listen((_) {
      if (!_disposed) _onSessionEnded();
    });
  }

  final CastV2Channel _channel;
  final void Function() _onSessionEnded;
  StreamSubscription<void>? _closedSub;
  bool _disposed = false;

  @override
  Stream<String> get messages => _channel.customMessages;

  @override
  Future<void> sendMessage(String json) async => _channel.sendCustom(jellyfinCastNamespace, json);

  @override
  Future<void> setVolume(double level) async => _channel.setVolume(level);

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _closedSub?.cancel();
    _closedSub = null;
    await _channel.dispose();
  }
}

/// The desktop Jellyfin Cast receiver player (Windows/Linux/macOS).
///
/// Deliberately thin, like [WebJellyfinCastPlayer]: the mobile subclass carries
/// SDK-specific timing workarounds (rejoin detection, media-status-as-ack) that
/// don't apply here, because we own the connection and know the receiver is
/// freshly launched and listening before we send anything.
class DesktopJellyfinCastPlayer extends JellyfinReceiverPlayer {
  DesktopJellyfinCastPlayer._(super.transport, super.context, super.deviceName, {required super.onSessionEnded});

  /// Connects to [device], launching the Jellyfin receiver on it.
  static Future<DesktopJellyfinCastPlayer> connect(
    CastDeviceInfo device,
    JellyfinCastContext context, {
    required void Function() onSessionEnded,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _log.info('Starting Jellyfin cast session with "${device.name}" (${device.host})');
    final channel = await CastV2Channel.connect(
      device.host,
      device.port,
      jellyfinReceiverAppId,
      timeout: timeout,
    );
    final transport = DesktopCastTransport(channel, onSessionEnded);
    return DesktopJellyfinCastPlayer._(transport, context, device.name, onSessionEnded: onSessionEnded);
  }
}

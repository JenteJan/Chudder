import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';

/// Non-web stub: the Cast Web Sender only exists in the browser build.
bool webCastAvailable() => false;

Future<BasePlayer> connectWebCast(
  JellyfinCastContext context, {
  required void Function() onSessionEnded,
}) =>
    throw UnsupportedError('Web Cast is only available on the web build');

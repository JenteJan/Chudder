// Stops whatever the Jellyfin receiver is playing on a Chromecast and closes
// the receiver: `CAST_HOST=<address> flutter test tool/cast_probe/stop_chromecast_test.dart`.
// For a probe run that left the television playing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/wrappers/players/cast/desktop/castv2_channel.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';

void main() {
  final host = Platform.environment['CAST_HOST'] ?? '';
  final appId = Platform.environment['CAST_APP_ID'] ?? jellyfinReceiverAppId;

  test('the receiver is stopped', () async {
    final channel = await CastV2Channel.connect(host, 8009, appId, timeout: const Duration(seconds: 15));
    await channel.stop();
    // ignore: avoid_print
    print('stopped the receiver on $host');
  }, skip: host.isEmpty);
}

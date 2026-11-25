import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/wrappers/players/cast/desktop/cast_device_auth.dart';
import 'package:chudder/wrappers/players/cast/desktop/castv2_channel.dart';

/// Connects to a fake Cast device on 127.0.0.1:FAKE_CAST_PORT, which must be
/// refused before anything but the challenge is sent.
void main() {
  test('a fake Cast device is refused', () async {
    final port = int.parse(Platform.environment['FAKE_CAST_PORT'] ?? '18009');
    await expectLater(
      CastV2Channel.connect('127.0.0.1', port, 'F007D354', timeout: const Duration(seconds: 5)),
      throwsA(isA<CastDeviceAuthException>()),
    );
  });
}

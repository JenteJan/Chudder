import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/wrappers/players/windows_hdr.dart';

/// HDR video only switches the window to HDR while its display is in HDR: an
/// HDR swap chain anywhere else is clipped at SDR white.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chudder/hdr');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  bool? displayHdr;
  final calls = <String>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'supported' => true,
        'displayHdr' => displayHdr,
        _ => null,
      };
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('passes on what the runner says about the display', () async {
    displayHdr = true;
    expect(await WindowsHdr.displayHdr(), isTrue);
    displayHdr = false;
    expect(await WindowsHdr.displayHdr(), isFalse);
    expect(calls, contains('displayHdr'));
  });

  test('a runner without the method counts as a display that is not in HDR', () async {
    displayHdr = null;
    expect(await WindowsHdr.displayHdr(), isFalse);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'supported') return true;
      throw MissingPluginException();
    });
    expect(await WindowsHdr.displayHdr(), isFalse);
  });
}

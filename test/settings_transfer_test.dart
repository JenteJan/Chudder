import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/util/settings_transfer.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an export leaves out logins and what only describes this device', () async {
    SharedPreferences.setMockInitialValues({
      'loginCredentialsKey': ['secret'],
      'clientSettings': jsonEncode({
        'syncPath': r'D:\Films',
        'posterSize': 0.9,
        'size': {'x': 1, 'y': 2}
      }),
      'videoPlayerSettings': jsonEncode({'playerOptions': 'libMDK', 'enableSpeedBoost': true}),
    });
    final preferences = await SharedPreferences.getInstance();

    final bundle = SettingsBundle.collect(preferences, device: '1.0 (Windows)');
    final encoded = bundle.encode();

    expect(encoded, isNot(contains('secret')));
    expect(encoded, isNot(contains('Films')));
    expect(encoded, isNot(contains('libMDK')));
    expect(bundle.sections[SettingsSection.app], {'posterSize': 0.9});
    expect(bundle.sections[SettingsSection.player], {'enableSpeedBoost': true});
  });

  test('an import takes only the chosen parts and keeps this device\'s own fields', () async {
    final bundle = SettingsBundle.decode(jsonEncode({
      'format': SettingsBundle.format,
      'version': 1,
      'exportedAt': '2026-10-15T10:00:00.000',
      'device': '1.0 (Android TV)',
      'settings': {
        'clientSettings': {'posterSize': 0.5, 'syncPath': '/sdcard/other'},
        'homeSettings': {'nextUp': false},
      },
    }));
    expect(bundle, isNotNull);
    expect(bundle!.device, '1.0 (Android TV)');

    SharedPreferences.setMockInitialValues({
      'clientSettings': jsonEncode({'syncPath': r'D:\Films', 'posterSize': 0.9}),
      'homeSettings': jsonEncode({'nextUp': true}),
    });
    final preferences = await SharedPreferences.getInstance();

    await bundle.writeTo(preferences, {SettingsSection.app});

    final client = jsonDecode(preferences.getString('clientSettings')!);
    expect(client['posterSize'], 0.5);
    expect(client['syncPath'], r'D:\Films');
    // Not chosen: untouched.
    expect(jsonDecode(preferences.getString('homeSettings')!)['nextUp'], isTrue);
  });

  test('anything else is not taken for an export', () {
    expect(SettingsBundle.decode('{"settings": {}}'), isNull);
    expect(SettingsBundle.decode('not json at all'), isNull);
  });
}

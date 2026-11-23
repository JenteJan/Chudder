// Scanning for servers is what makes iOS, macOS and Android ask for local
// network access, so there it waits for the user.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/discovery_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/screens/login/widgets/discover_servers_widget.dart';

import '../dpad/dpad_walk.dart';

var _scans = 0;

class _Discovery extends ServerDiscovery {
  @override
  Stream<List<DiscoveryInfo>> build() {
    _scans++;
    return Stream.value(const [
      DiscoveryInfo(id: 'a', name: 'Living room', address: 'http://192.168.1.20:8096', endPointAddress: null),
    ]);
  }
}

Future<SharedPreferences> _open(WidgetTester tester, {Map<String, Object> stored = const {}}) async {
  _scans = 0;
  SharedPreferences.setMockInitialValues(stored);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    dpadApp(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        serverDiscoveryProvider.overrideWith(_Discovery.new),
      ],
      child: Scaffold(
        body: DiscoverServersWidget(serverCredentials: const [], onPressed: (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

// The framework wants the override gone before the test ends, so a tearDown is too late.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('macOS: nothing scans until the user asks, then the choice is remembered', (tester) async {
    await _on(TargetPlatform.macOS, () async {
      final prefs = await _open(tester);

      expect(_scans, 0);
      expect(find.text('Find servers on this network'), findsOneWidget);
      expect(find.text('Living room'), findsNothing);

      await tester.tap(find.text('Find servers on this network'));
      await tester.pumpAndSettle();

      expect(_scans, 1);
      expect(find.text('Living room'), findsOneWidget);
      expect(prefs.getBool('serverDiscoveryChosen'), isTrue);
    });
  });

  testWidgets('macOS: having asked before, the screen scans by itself', (tester) async {
    await _on(TargetPlatform.macOS, () async {
      await _open(tester, stored: {'serverDiscoveryChosen': true});

      expect(_scans, 1);
      expect(find.text('Living room'), findsOneWidget);
      expect(find.text('Find servers on this network'), findsNothing);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform waits for the user too', (tester) async {
      await _on(platform, () async {
        await _open(tester);
        expect(_scans, 0);
        expect(find.text('Find servers on this network'), findsOneWidget);
      });
    });
  }

  for (final platform in [TargetPlatform.linux]) {
    testWidgets('$platform asks for nothing, so it scans at once', (tester) async {
      await _on(platform, () async {
        await _open(tester);
        expect(_scans, 1);
        expect(find.text('Living room'), findsOneWidget);
        expect(find.text('Find servers on this network'), findsNothing);
      });
    });
  }
}

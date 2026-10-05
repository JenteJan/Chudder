// Stays in a SyncPlay group as its second member, so that a phone test has a
// group that does not disappear when the phone's connection drops.
//
// Run: flutter test integration_test/syncplay_member_test.dart -d windows --dart-define=HOLD_SECONDS=600

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chudder/main.dart' as app;
import 'package:chudder/providers/incognito_mode_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

const _hold = int.fromEnvironment('HOLD_SECONDS', defaultValue: 600);

void _out(String line) => debugPrint('[member] $line');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hold a syncplay group open', (tester) async {
    app.main([]);
    for (var i = 0; i < 240 && find.byType(NavigationBody).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBody).first), listen: false);
    container.read(incognitoModeProvider.notifier).state = false;
    final syncPlay = container.read(syncPlayProvider.notifier);
    await syncPlay.connect();
    final group = await syncPlay.createGroup('cast-test');
    for (var i = 0; i < 200 && !container.read(isSyncPlayActiveProvider); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    _out('READY group ${group?.groupName} active=${container.read(isSyncPlayActiveProvider)}');

    final end = DateTime.now().add(const Duration(seconds: _hold));
    var last = DateTime.now();
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (DateTime.now().difference(last) > const Duration(seconds: 20)) {
        last = DateTime.now();
        final state = container.read(syncPlayProvider);
        _out('participants=${state.participants} state=${state.groupState} active=${container.read(isSyncPlayActiveProvider)}');
      }
    }
    await syncPlay.leaveGroup();
  }, timeout: const Timeout(Duration(minutes: 20)));
}

// Signing in empties what the last account left behind. In a debug build, Riverpod
// refuses a provider to read one that depends on it, and the dashboard (through the
// server address) depends on the sign-in provider: reading it from there threw a
// cycle error once the dashboard existed, so every sign-in after the first hung.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/auth_provider.dart';
import 'package:chudder/providers/dashboard_provider.dart';
import 'package:chudder/providers/shared_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearing the last account works while the dashboard exists', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance())],
    );
    // Not disposed: the dashboard pulls in the websocket controller, which writes
    // state while it is torn down, and none of that is what this is about.

    // The dashboard follows the server address, which follows the sign-in provider.
    container.read(dashboardProvider);
    expect(container.exists(dashboardProvider), isTrue);

    expect(() => container.read(authProvider.notifier).clearAllProviders(), returnsNormally);
  });

  test('clearing the last account works when nothing has been made yet', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance())],
    );
    addTearDown(container.dispose);

    expect(() => container.read(authProvider.notifier).clearAllProviders(), returnsNormally);
    expect(container.exists(dashboardProvider), isFalse);
  });
}

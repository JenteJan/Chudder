// Adding an account by remote: the server step, the code and the password.

import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart' as chopper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/fake/fake_jellyfin_open_api.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/models/login_screen_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/auth_provider.dart';
import 'package:chudder/providers/discovery_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/screens/login/login_screen_credentials.dart';

import 'dpad_walk.dart';

class _QuickConnectApi extends FakeJellyfinOpenApi {
  @override
  Future<chopper.Response<QuickConnectResult>> quickConnectInitiatePost() async =>
      chopper.Response(http.Response('', 200), const QuickConnectResult(code: '482913', secret: 's'));

  @override
  Future<chopper.Response<QuickConnectResult>> quickConnectConnectGet({required String? secret}) async =>
      chopper.Response(http.Response('', 200), const QuickConnectResult(authenticated: false, secret: 's'));
}

class _Service extends JellyService {
  _Service(Ref ref) : super(ref, _QuickConnectApi());

  @override
  JellyfinOpenApi get api => _QuickConnectApi();
}

class _Api extends JellyApi {
  @override
  JellyService build() => _Service(ref);
}

class _Auth extends AuthNotifier {
  _Auth(super.ref, LoginScreenModel preset) {
    state = preset;
  }
}

class _Discovery extends ServerDiscovery {
  @override
  Stream<List<DiscoveryInfo>> build() => Stream.value(const [
    DiscoveryInfo(id: 'a', name: 'Living room', address: 'http://192.168.1.20:8096', endPointAddress: null),
  ]);
}

final _server = ServerLoginModel(
  tempCredentials: CredentialsModel.internal(url: 'https://media.example.com', serverName: 'Home Media'),
  hasQuickConnect: true,
);

Future<void> _open(WidgetTester tester, LoginScreenModel state) async {
  SharedPreferences.setMockInitialValues({});
  await pumpDpad(
    tester,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      authProvider.overrideWith((ref) => _Auth(ref, state)),
      jellyApiProvider.overrideWith(_Api.new),
      serverDiscoveryProvider.overrideWith(_Discovery.new),
    ],
    child: const SingleChildScrollView(child: LoginScreenCredentials()),
  );
}

Future<void> _close(WidgetTester tester) async {
  // Lets the code panel's poll timer go.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('server step: address, connect, found servers and auth link', (tester) async {
    await _open(tester, LoginScreenModel(screen: LoginScreenType.login));
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(LoginScreenCredentials));
    walk.expectAllReachable(within: find.byType(LoginScreenCredentials));
    await _close(tester);
  });

  testWidgets('code step: the code, a new one, the password route and change server', (tester) async {
    await _open(tester, LoginScreenModel(screen: LoginScreenType.code, serverLoginModel: _server));
    expect(find.text('482913'), findsOneWidget);
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(LoginScreenCredentials));
    walk.expectAllReachable(within: find.byType(LoginScreenCredentials));
    await _close(tester);
  });

  testWidgets('password step: fields, sign in, advanced and back to the code', (tester) async {
    await _open(tester, LoginScreenModel(screen: LoginScreenType.code, serverLoginModel: _server));
    await tester.tap(find.text('Use a password instead'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('Use a code instead'), findsOneWidget);
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(LoginScreenCredentials));
    await _close(tester);
  });
}

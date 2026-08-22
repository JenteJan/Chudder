import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/local_network_permission.dart';

part 'connectivity_provider.g.dart';

enum ConnectionState {
  offline,
  mobile,
  wifi,
  ethernet;

  bool get homeInternet => switch (this) {
        ConnectionState.offline => false,
        ConnectionState.mobile => false,
        ConnectionState.wifi => true,
        ConnectionState.ethernet => true,
      };
}

final offlineStateProvider = Provider<bool>((ref) {
  final isLoggedIn = ref.watch(userProvider.select((value) => value != null));
  return ref.watch(connectivityStatusProvider.select((value) => value == ConnectionState.offline)) && isLoggedIn;
});

@Riverpod(keepAlive: true)
class ConnectivityStatus extends _$ConnectivityStatus {
  String? localUrl;

  /// Runs only while offline. Nothing else brings the app back on its own: it
  /// stops talking to the server once it thinks it is offline, so waiting for
  /// a request to succeed means waiting for the user to try something, and a
  /// connectivity event never comes when the Wi-Fi was fine all along.
  Timer? _offlineRecheck;
  static const _offlineRecheckInterval = Duration(seconds: 10);

  /// One probe at a time. Every caller shares it: a screenful of requests used
  /// to start a screenful of probes at the same instant, and a phone opening
  /// sixteen TLS connections to one host makes them all slow enough to time
  /// out together — which the app then read as the network being down.
  Future<void>? _inFlight;

  /// A single timeout is a phone being a phone, not an outage. Two in a row
  /// before the app stops talking to the server.
  int _failures = 0;
  static const _failuresBeforeOffline = 2;

  @override
  ConnectionState build() {
    ref.listen(userProvider, (previous, next) {
      checkLocalUrl(previous, next);
    });
    final subscription = Connectivity().onConnectivityChanged.listen(onStateChange);
    ref.onDispose(() {
      _offlineRecheck?.cancel();
      subscription.cancel();
    });
    checkConnectivity();
    return ConnectionState.mobile;
  }

  void _watchForRecovery() {
    if (state == ConnectionState.offline) {
      _offlineRecheck ??= Timer.periodic(_offlineRecheckInterval, (_) => checkConnectivity());
    } else {
      _offlineRecheck?.cancel();
      _offlineRecheck = null;
    }
  }

  void checkLocalUrl(AccountModel? previous, AccountModel? next) {
    final newUrl = next?.credentials.localUrl;
    if (localUrl != newUrl) {
      checkConnectivity();
    }
  }

  Future<void> onStateChange(List<ConnectivityResult> connectivityResult) async {
    if (connectivityResult.contains(ConnectivityResult.ethernet)) {
      state = ConnectionState.ethernet;
    } else if (connectivityResult.contains(ConnectivityResult.wifi)) {
      state = ConnectionState.wifi;
    } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
      state = ConnectionState.mobile;
    } else if (connectivityResult.contains(ConnectivityResult.none)) {
      state = ConnectionState.offline;
    }
    _watchForRecovery();
    final newUrl = ref.read(userProvider.select((value) => value?.credentials.localUrl));
    if (localUrl == newUrl) return;
    localUrl = newUrl;
    final localConnection =
        localUrl != null && localUrl?.isNotEmpty == true ? await fetchSystemInfoDynamic(normalizeUrl(localUrl!)) : null;
    final correctServerResponse =
        localConnection?.id == ref.read(userProvider.select((value) => value?.credentials.serverId));
    ref.read(localConnectionAvailableProvider.notifier).update((state) => correctServerResponse);
  }

  Future<void> checkConnectivity() => _inFlight ??= _probe().whenComplete(() => _inFlight = null);

  Future<void> _probe() async {
    final serverUrl = ref.read(serverUrlProvider);
    // Nothing to reach for yet. Probing "" fails instantly and said offline,
    // which is how the app could open onto an offline screen before it had
    // been told where the server is.
    if (serverUrl == null || serverUrl.isEmpty) return;

    final connectivityResult = await Connectivity().checkConnectivity();
    final reachable = await probeJellyfinUrl(serverUrl) != null;

    if (reachable) {
      _failures = 0;
      onStateChange(connectivityResult);
      return;
    }

    if (++_failures < _failuresBeforeOffline) return;
    onStateChange([ConnectivityResult.none]);
  }

  /// Called when a request came back. That is better evidence than any probe
  /// could be, so this asks the server nothing — the only open question is
  /// which kind of connection carried it, and only if the app had given up.
  Future<void> reportReachable() async {
    _failures = 0;
    if (state != ConnectionState.offline) return;
    onStateChange(await Connectivity().checkConnectivity());
  }

  /// The last known state. This used to fire a request of its own every time
  /// it was read, and it is read before every API call — so a screen's worth
  /// of requests became two screens' worth, on the phone least able to carry
  /// them. Losing the connection is reported by the requests themselves.
  ConnectionState getConnectivityStates() => state;
}

Future<PublicSystemInfo?> fetchSystemInfoDynamic(String baseUrl) async {
  if (baseUrl.isEmpty) return null;
  try {
    // The local URL is by definition on the LAN; without the grant this probe
    // times out and the account silently falls back to its remote address.
    await LocalNetworkPermission.ensureForUrl(baseUrl);
    final uri = buildServerUriFromBase(baseUrl, pathSegments: const ['System', 'Info', 'Public']);
    if (uri == null) return null;
    final response = await http.get(uri).timeout(const Duration(seconds: 1));
    if (response.statusCode == 200) {
      return PublicSystemInfo.fromJson(jsonDecode(response.body));
    }
    return null;
  } catch (e) {
    log(e.toString());
    return null;
  }
}

final localConnectionAvailableProvider = StateProvider<bool>((ref) {
  return false;
});

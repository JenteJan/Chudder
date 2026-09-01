import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/util/local_network_permission.dart';
import 'package:fladder/util/recyclable_http_client.dart';

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

// Lands in cast_log.txt (the crash-log buffer forwards this logger) so
// reachability behavior can be diagnosed from a real session.
final _connectivityLog = Logger('Connectivity');

@Riverpod(keepAlive: true)
class ConnectivityStatus extends _$ConnectivityStatus {
  String? localUrl;

  /// Runs only while offline. Nothing else brings the app back on its own: it
  /// stops talking to the server once it thinks it is offline, so waiting for
  /// a request to succeed means waiting for the user to try something, and a
  /// connectivity event never comes when the Wi-Fi was fine all along.
  Timer? _offlineRecheck;
  /// First recheck delay. Recovery is usually immediate - a phone leaving a
  /// lift, wifi coming back - so the early probes stay quick.
  static const _offlineRecheckInterval = Duration(seconds: 4);

  /// Ceiling of the recheck backoff.
  ///
  /// A fixed 4s cadence was fine for a blip and wrong for the case the app is
  /// actually built for: a deliberate offline session. It woke the radio every
  /// four seconds indefinitely, and wrote two lines each time into the
  /// diagnostics file - about 1800 lines an hour, which flushed everything
  /// worth keeping out of its window within a few hours.
  static const _offlineRecheckMaxInterval = Duration(seconds: 64);

  /// Consecutive offline rechecks, for the backoff. Reset whenever the state
  /// leaves offline, so the next disconnection starts fast again.
  int _offlineRechecks = 0;

  /// One probe at a time. Every caller shares it: a screenful of requests used
  /// to start a screenful of probes at the same instant, and a phone opening
  /// sixteen TLS connections to one host makes them all slow enough to time
  /// out together — which the app then read as the network being down.
  Future<void>? _inFlight;

  /// Watchdog while ONLINE. A mid-session disconnect had no detector at all:
  /// connectivity events only fire when the interface itself changes (and on
  /// Windows often not even then), browsing cached screens fires no requests,
  /// and a request that does fire spends 30s+ timing out before the
  /// interceptor flips the state. This probes only when nothing else has
  /// confirmed the server recently, so an active session costs nothing extra.
  Timer? _onlineHeartbeat;
  DateTime _lastConfirmedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _heartbeatInterval = Duration(seconds: 15);
  static const _confirmationStaleAfter = Duration(seconds: 20);

  /// A single timeout is a phone being a phone, not an outage. Two in a row
  /// before the app stops talking to the server.
  int _failures = 0;
  static const _failuresBeforeOffline = 2;

  /// Whether the server has EVER answered this session. Before the first
  /// confirmation the two-strike patience is wrong: a cold start without a
  /// route to the server sat "online" for probe+retry+probe (~13s) before
  /// admitting anything. First strike counts until we've been online once —
  /// a false alarm self-corrects at the next 10s recheck.
  bool _everConfirmed = false;

  @override
  ConnectionState build() {
    ref.listen(userProvider, (previous, next) {
      checkLocalUrl(previous, next);
    });
    // The startup probe usually runs before the stored account has loaded,
    // so it bails on an empty server URL — and nothing else ever re-probed.
    // On a phone opened without a route to the server (5G, no VPN) the app
    // then sat in its initial "online" state forever with no offline chip.
    // Probe the moment a server URL appears or changes.
    ref.listen(serverUrlProvider, (previous, next) {
      if (previous != next && next != null && next.isNotEmpty) {
        checkConnectivity();
      }
    });
    final subscription = Connectivity().onConnectivityChanged.listen((result) {
      _connectivityLog.info('OS connectivity event: $result (state=$state)');
      // Offline means "the server is unreachable", not "there is no
      // internet" — an OS event announcing wifi/mobile is no proof the
      // server answers, so while offline only a successful probe or request
      // may bring the state back. Applying the event directly here was
      // resurrecting "online" every time Android re-announced its network.
      if (state != ConnectionState.offline) {
        onStateChange(result);
      }
      // A network-type change (wifi → mobile, VPN up/down) says nothing about
      // whether the SERVER is reachable from the new network — probe it.
      // Deduped by _inFlight; only the real OS event triggers this, so the
      // probe's own onStateChange calls can't loop.
      checkConnectivity();
      // Reconnects race the probe: wifi "connected" fires the event a couple
      // of seconds before routes and DNS actually work, so the immediate
      // probe often loses and recovery used to wait for the periodic
      // recheck. A short burst behind the event wins the race whichever
      // moment the network becomes real.
      if (state == ConnectionState.offline) {
        Timer(const Duration(seconds: 2), () {
          if (state == ConnectionState.offline) checkConnectivity();
        });
        Timer(const Duration(seconds: 5), () {
          if (state == ConnectionState.offline) checkConnectivity();
        });
      }
    });
    _onlineHeartbeat = Timer.periodic(_heartbeatInterval, (_) {
      // The offline recheck timer owns recovery; this one only detects loss.
      if (state == ConnectionState.offline) return;
      if (DateTime.now().difference(_lastConfirmedAt) < _confirmationStaleAfter) return;
      checkConnectivity();
    });
    ref.onDispose(() {
      _offlineRecheck?.cancel();
      _onlineHeartbeat?.cancel();
      subscription.cancel();
    });
    checkConnectivity();
    return ConnectionState.mobile;
  }

  void _watchForRecovery() {
    if (state == ConnectionState.offline) {
      _offlineRecheck ??= _scheduleOfflineRecheck();
    } else {
      _offlineRecheck?.cancel();
      _offlineRecheck = null;
      _offlineRechecks = 0;
    }
  }

  /// One-shot rather than periodic, so each delay can be longer than the last.
  Timer _scheduleOfflineRecheck() {
    final delay = _offlineRecheckDelay(_offlineRechecks);
    return Timer(delay, () async {
      _offlineRecheck = null;
      if (state != ConnectionState.offline) return;
      _offlineRechecks++;
      await checkConnectivity();
      if (state == ConnectionState.offline) {
        _offlineRecheck ??= _scheduleOfflineRecheck();
      }
    });
  }

  /// Doubling from [_offlineRecheckInterval] up to
  /// [_offlineRecheckMaxInterval], then flat - it never stops looking.
  Duration _offlineRecheckDelay(int attempt) {
    final seconds = _offlineRecheckInterval.inSeconds * (1 << attempt.clamp(0, 8));
    return seconds >= _offlineRecheckMaxInterval.inSeconds
        ? _offlineRecheckMaxInterval
        : Duration(seconds: seconds);
  }

  void checkLocalUrl(AccountModel? previous, AccountModel? next) {
    final newUrl = next?.credentials.localUrl;
    if (localUrl != newUrl) {
      checkConnectivity();
    }
  }

  Future<void> onStateChange(List<ConnectivityResult> connectivityResult) async {
    final before = state;
    if (connectivityResult.contains(ConnectivityResult.ethernet)) {
      state = ConnectionState.ethernet;
    } else if (connectivityResult.contains(ConnectivityResult.wifi)) {
      state = ConnectionState.wifi;
    } else if (connectivityResult.contains(ConnectivityResult.mobile)) {
      state = ConnectionState.mobile;
    } else if (connectivityResult.contains(ConnectivityResult.none)) {
      state = ConnectionState.offline;
    }
    if (before != state) {
      _connectivityLog.info('State: $before -> $state');
      if (before == ConnectionState.offline) {
        // The pool is full of sockets that died with the old network; every
        // request that grabs one hangs for a ~20s OS timeout. Fresh pool,
        // instant recovery.
        _connectivityLog.info('Recycling HTTP connection pool after reconnect');
        recyclableHttpClient.recycle();
      }
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
    final reachable = await probeJellyfinReachable(serverUrl);
    _connectivityLog.info('Probe $serverUrl -> ${reachable ? 'reachable' : 'UNREACHABLE'} '
        '(failures=$_failures, state=$state, network=$connectivityResult)');

    if (reachable) {
      _failures = 0;
      _everConfirmed = true;
      _lastConfirmedAt = DateTime.now();
      onStateChange(connectivityResult);
      return;
    }

    // The OS itself says there is no network at all: no second opinion
    // needed, the strike patience is for flaky-but-present networks.
    if (connectivityResult.contains(ConnectivityResult.none) || !_everConfirmed) {
      // Only the transition is worth a line. Repeating it on every recheck
      // said nothing new and was half of what filled the diagnostics file.
      if (state != ConnectionState.offline) {
        _connectivityLog.info('Marking OFFLINE '
            '(${!_everConfirmed ? 'never confirmed online yet' : 'OS reports no network'})');
      }
      _failures = _failuresBeforeOffline;
      onStateChange([ConnectivityResult.none]);
      return;
    }

    if (++_failures < _failuresBeforeOffline) {
      // The second strike has to actually happen: nothing else re-probes
      // while the app still believes it is online, so a single failed
      // startup probe (server genuinely unreachable — remote without the
      // VPN) left the app "online" forever.
      Timer(const Duration(seconds: 3), checkConnectivity);
      return;
    }
    _connectivityLog.info('Two failed probes - marking OFFLINE');
    onStateChange([ConnectivityResult.none]);
  }

  /// Historic hook for "a request came back". Responses turned out to be
  /// terrible evidence — proxies, DNS block pages and captive portals all
  /// answer — so this no longer touches the state. The strict probe is the
  /// only thing that moves it, in either direction.
  Future<void> reportReachable() async {}

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

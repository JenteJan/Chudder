import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/local_network_permission.dart';
import 'package:chudder/util/recyclable_http_client.dart';

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

  /// What the reachability decisions are made from. Seams for tests; the app
  /// always runs on the real ones.
  @visibleForTesting
  static Future<List<ConnectivityResult>> Function() readOsConnectivity = () => Connectivity().checkConnectivity();
  @visibleForTesting
  static Stream<List<ConnectivityResult>> Function() osConnectivityEvents = () => Connectivity().onConnectivityChanged;
  @visibleForTesting
  static Future<bool> Function(String baseUrl) probeServer = probeJellyfinReachable;
  @visibleForTesting
  static void Function() recycleConnections = recyclableHttpClient.recycle;

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

  /// Whether the server has answered at least once since the app started.
  /// Tells a launch without a connection apart from one lost along the way.
  bool get everConfirmed => _everConfirmed;

  /// Whether the app is on screen. In the background a failed probe proves
  /// nothing: Android cuts a backgrounded app off the network (Doze, data
  /// saver's background restriction on mobile data) while the server is
  /// perfectly reachable. The heartbeat kept probing there, two failures put
  /// the app offline behind the user's back, and it opened on the offline
  /// state - and on the downloads - every time it came back.
  bool _foreground = true;

  /// A short window after the app comes back to the foreground, after it
  /// starts, or after the phone moves to another network, in which a failed
  /// probe is not yet a verdict. The radio waking up, the new network's
  /// routes and DNS settling (on the home network the server's name answers
  /// with its LAN address, elsewhere with the public one) all take a moment,
  /// and the first request or probe usually loses that race. Failures here
  /// still count as one strike, so a real outage is admitted at the first
  /// failure after the window: about [_settleGrace] when nothing answers.
  Timer? _graceTimer;
  static const _settleGrace = Duration(seconds: 4);

  /// The re-probe that keeps checking while the grace window is open, so the
  /// verdict comes as soon as the window closes rather than at the heartbeat.
  Timer? _graceRecheck;
  static const _graceRecheckDelay = Duration(seconds: 2);

  bool get _inGrace => _graceTimer?.isActive ?? false;

  /// The one-off re-probes (the second strike, the bursts behind a network
  /// event), kept so that disposing the provider stops them too.
  final Set<Timer> _oneOffs = {};

  void _probeLater(Duration delay, {bool onlyWhileOffline = false}) {
    late final Timer timer;
    timer = Timer(delay, () {
      _oneOffs.remove(timer);
      if (onlyWhileOffline && state != ConnectionState.offline) return;
      checkConnectivity();
    });
    _oneOffs.add(timer);
  }

  /// The OS's last network reading, to tell a real change of network from
  /// Android re-announcing the one it is already on.
  List<ConnectivityResult>? _lastOsResult;

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
    final subscription = osConnectivityEvents().listen(_onOsConnectivityEvent);
    _onlineHeartbeat = Timer.periodic(_heartbeatInterval, (_) {
      // The offline recheck timer owns recovery; this one only detects loss.
      if (state == ConnectionState.offline) return;
      if (!_foreground) return;
      if (DateTime.now().difference(_lastConfirmedAt) < _confirmationStaleAfter) return;
      checkConnectivity();
    });
    ref.onDispose(() {
      _offlineRecheck?.cancel();
      _onlineHeartbeat?.cancel();
      _graceTimer?.cancel();
      _graceRecheck?.cancel();
      for (final timer in _oneOffs) {
        timer.cancel();
      }
      subscription.cancel();
    });
    // A launch is the radio waking up too - often literally, when Android
    // restarts an app it killed in the background and the user is already
    // looking at it.
    _openGrace();
    checkConnectivity();
    return ConnectionState.mobile;
  }

  void _onOsConnectivityEvent(List<ConnectivityResult> result) {
    _connectivityLog.info('OS connectivity event: $result (state=$state)');
    // Offline means "the server is unreachable", not "there is no
    // internet" — an OS event announcing wifi/mobile is no proof the
    // server answers, so while offline only a successful probe or request
    // may bring the state back. Applying the event directly here was
    // resurrecting "online" every time Android re-announced its network.
    //
    // An event saying there is no network at all gets the same treatment as
    // the OS reading in `_probe`: it is a claim, not a verdict. Windows says
    // "none" on machines whose adapter its Network List Manager cannot
    // classify, and acting on that here put the app offline for the couple
    // of seconds until the probe below answered — long enough for the
    // dashboard to rebuild itself out of downloads. The probe decides.
    final osSaysNone = !_hasNetwork(result);
    final changed = !_sameResult(_lastOsResult, result);
    _lastOsResult = result;
    if (changed && !osSaysNone) {
      // A new network. The pooled keep-alive sockets were opened on the old
      // one and now lead nowhere; the first requests would pick them up and
      // hang until the OS gave up on them, then read as the server being
      // gone. The server's address may have changed with the network too -
      // split DNS gives the LAN address at home and the public one away -
      // and only a fresh connection asks again.
      _connectivityLog.info('Network changed - recycling HTTP connection pool');
      recycleConnections();
      _openGrace();
      // Whether the local address answers is a property of the network,
      // not of the account: ask again from the new one.
      _refreshLocalConnection(force: true);
    }
    if (state != ConnectionState.offline && !osSaysNone) {
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
      _probeLater(const Duration(seconds: 2), onlyWhileOffline: true);
      _probeLater(const Duration(seconds: 5), onlyWhileOffline: true);
    }
  }

  /// The app went to the background. Probes carry on - one that succeeds is
  /// still good news - but a failure there is not held against the server.
  void onBackgrounded() {
    _foreground = false;
  }

  /// The app is back on screen after being in the background.
  ///
  /// Everything the pool holds is suspect by now: the phone may be on another
  /// network, and even on the same one a NAT or proxy has long since dropped
  /// connections that sat idle while the app was away. Starting fresh costs a
  /// handshake; keeping them cost the first screenful of requests, which
  /// failed together and used to take the app offline on the spot.
  void onResumed() {
    _foreground = true;
    _connectivityLog.info('Resumed - recycling HTTP connection pool');
    recycleConnections();
    _openGrace();
    checkConnectivity();
  }

  /// A request could not reach the server. Evidence, not a verdict: the
  /// probe decides, with the same patience as every other failure. Requests
  /// used to take the app offline themselves, which let one stale socket
  /// after a network change skip every safeguard the probe has.
  void reportConnectionFailure() {
    checkConnectivity();
  }

  void _openGrace() {
    _graceTimer?.cancel();
    _graceTimer = Timer(_settleGrace, () {});
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
        recycleConnections();
      }
    }
    _watchForRecovery();
    await _refreshLocalConnection();
  }

  /// Whether the account's local address answers, which decides the URL
  /// every request goes to. Asked when the local address changes, and with
  /// [force] whenever the network does.
  Future<void> _refreshLocalConnection({bool force = false}) async {
    final newUrl = ref.read(userProvider.select((value) => value?.credentials.localUrl));
    if (!force && localUrl == newUrl) return;
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

    final connectivityResult = await readOsConnectivity();
    final reachable = await probeServer(serverUrl);
    _connectivityLog.info('Probe $serverUrl -> ${reachable ? 'reachable' : 'UNREACHABLE'} '
        '(failures=$_failures, state=$state, network=$connectivityResult)');

    if (reachable) {
      _failures = 0;
      _everConfirmed = true;
      _lastConfirmedAt = DateTime.now();
      _graceRecheck?.cancel();
      _graceRecheck = null;
      // The server answering is the better witness. Windows reports no
      // network now and then while there plainly is one - seen right after a
      // video player shuts down - and taking its word over a probe that just
      // reached the server put up the offline banner on a working connection.
      onStateChange(!_hasNetwork(connectivityResult)
          ? [
              switch (state) {
                ConnectionState.wifi => ConnectivityResult.wifi,
                ConnectionState.mobile => ConnectivityResult.mobile,
                _ => ConnectivityResult.ethernet,
              }
            ]
          : connectivityResult);
      return;
    }

    // Already offline: nothing to decide, the recovery recheck carries on.
    if (state == ConnectionState.offline) return;

    // See [_foreground]. The resume re-probes with a clean slate.
    if (!_foreground) return;

    if (_inGrace) {
      // One strike at most, however many failures the window sees: the
      // first failure after it is then the second strike and decides.
      _failures = _failuresBeforeOffline - 1;
      _graceRecheck ??= Timer(_graceRecheckDelay, () {
        _graceRecheck = null;
        if (state != ConnectionState.offline) checkConnectivity();
      });
      return;
    }

    // The OS itself says there is no network at all: no second opinion
    // needed, the strike patience is for flaky-but-present networks.
    if (connectivityResult.contains(ConnectivityResult.none) || !_everConfirmed) {
      _connectivityLog.info('Marking OFFLINE '
          '(${!_everConfirmed ? 'never confirmed online yet' : 'OS reports no network'})');
      _failures = _failuresBeforeOffline;
      onStateChange([ConnectivityResult.none]);
      return;
    }

    if (++_failures < _failuresBeforeOffline) {
      // The second strike has to actually happen: nothing else re-probes
      // while the app still believes it is online, so a single failed
      // startup probe (server genuinely unreachable — remote without the
      // VPN) left the app "online" forever.
      _probeLater(const Duration(seconds: 3));
      return;
    }
    _connectivityLog.info('Two failed probes - marking OFFLINE');
    onStateChange([ConnectivityResult.none]);
  }

  static bool _hasNetwork(List<ConnectivityResult> result) => result.any((connection) =>
      connection == ConnectivityResult.ethernet ||
      connection == ConnectivityResult.wifi ||
      connection == ConnectivityResult.mobile);

  static bool _sameResult(List<ConnectivityResult>? a, List<ConnectivityResult> b) =>
      a != null && a.toSet().containsAll(b) && b.toSet().containsAll(a);

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

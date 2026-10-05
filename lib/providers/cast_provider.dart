import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, ImageProvider, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/profiles/airplay_profile.dart';
import 'package:chudder/profiles/chromecast_profile.dart';
import 'package:chudder/profiles/dlna_profile.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/settings/subtitle_settings_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/util/bitrate_helper.dart';
import 'package:chudder/util/local_network_permission.dart';
import 'package:chudder/util/map_bool_helper.dart';
import 'package:chudder/wrappers/players/airplay_video_player.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/cast/cast_queue.dart';
import 'package:chudder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:chudder/wrappers/players/cast/desktop/castv2_channel.dart' show CastSessionGoneException;
import 'package:chudder/wrappers/players/cast/desktop/desktop_cast_player.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_receiver_player.dart';
import 'package:chudder/wrappers/players/cast/web/cast_web.dart';
import 'package:chudder/wrappers/players/cast_player.dart';
import 'package:chudder/wrappers/players/dlna_discovery.dart';
import 'package:chudder/wrappers/players/dlna_player.dart';
import 'package:chudder/wrappers/players/jellyfin_cast_channel.dart';
import 'package:chudder/wrappers/players/jellyfin_cast_player.dart';
import 'package:chudder/wrappers/players/remote_device.dart';

/// Platforms with a native Google Cast SDK wired up (`flutter_chrome_cast`).
bool get _chromecastSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Desktop has no first-party Cast SDK, so Chromecasts are found by our own mDNS
/// scan and driven over our own CASTV2 client ([DesktopJellyfinCastPlayer]).
/// The receiver can't tell the difference — it's the same wire protocol the
/// mobile SDK speaks.
///
/// This path always uses the Jellyfin receiver: the universal-receiver fallback
/// needs the phone to re-serve a transcode over plain HTTP, which desktop
/// doesn't set up.
bool get _desktopCastSupported => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// Whether DLNA discovery can run at all. Web has no raw UDP/SSDP; every other
/// platform we ship runs the same pure-Dart discovery code.
bool get _dlnaSupported => !kIsWeb;

/// Whether to offer video AirPlay (an `AVPlayer`-backed player routed out by the
/// OS). iOS + macOS — both register a native `AVRoutePickerView`.
bool get _airPlaySupported => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// Which kind of receiver a Chromecast runs:
///
/// - The Jellyfin receiver (stable `F007D354`, unstable `6F511C87`, or one the
///   server admin added — see [castReceiverAppIdProvider]): it plays the item
///   from the server itself, switches tracks, reports its own progress and
///   plays on when this app goes away. Its web app needs a 2nd-gen or newer
///   Chromecast.
/// - Google's default media receiver (`CC1AD845`): a tiny native player that
///   runs on *every* Chromecast generation, including the 2013 first-gen
///   dongle, fed a progressive H.264/AAC transcode (see [chromecastProfile])
///   through this device. Kept for a first-gen-only household.
///
/// The Jellyfin receiver is what this app uses; flip this for the fallback.
const _useJellyfinReceiver = true;
const _defaultReceiverAppId = 'CC1AD845';

/// Key of the desktop cast session remembered for rejoining after a restart.
const _desktopSessionKey = 'castDesktopSession';

enum CastConnectionStatus { idle, connecting, connected, disconnecting, error }

class CastState {
  final List<RemoteDevice> devices;
  final bool discovering;
  final CastConnectionStatus status;
  final String? connectedDeviceName;
  final String? connectedDeviceId;

  /// Whether the connected device can be left playing on its own (the picker
  /// then offers to disconnect without stopping it).
  final bool canLeavePlaying;
  final String? error;

  const CastState({
    this.devices = const [],
    this.discovering = false,
    this.status = CastConnectionStatus.idle,
    this.connectedDeviceName,
    this.connectedDeviceId,
    this.canLeavePlaying = false,
    this.error,
  });

  bool get isConnected => status == CastConnectionStatus.connected;

  CastState copyWith({
    List<RemoteDevice>? devices,
    bool? discovering,
    CastConnectionStatus? status,
    String? connectedDeviceName,
    String? connectedDeviceId,
    bool? canLeavePlaying,
    String? error,
  }) {
    return CastState(
      devices: devices ?? this.devices,
      discovering: discovering ?? this.discovering,
      status: status ?? this.status,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      canLeavePlaying: canLeavePlaying ?? this.canLeavePlaying,
      error: error,
    );
  }
}

/// The Chromecast receiver apps the server offers (Jellyfin's stable and
/// unstable builds, or ones its admin added), for the receiver setting.
final castReceiverApplicationsProvider = FutureProvider.autoDispose<List<CastReceiverApplication>>((ref) async {
  final response = await ref.read(jellyApiProvider).systemInfoGet();
  final receivers = response.body?.castReceiverApplications ?? const [];
  return receivers.where((receiver) => (receiver.id ?? '').isNotEmpty).toList();
});

/// The receiver app to launch on a Chromecast: the one picked in the user's
/// Jellyfin settings (shared with jellyfin-web; the server always resolves it
/// to one it offers), else Jellyfin's stable build.
final castReceiverAppIdProvider = Provider<String>((ref) {
  final picked = ref.watch(userProvider.select((user) => user?.userConfiguration?.castReceiverId));
  return (picked == null || picked.isEmpty) ? jellyfinReceiverAppId : picked;
});

final _log = Logger('Cast');

final castProvider = StateNotifierProvider<CastNotifier, CastState>((ref) => CastNotifier(ref));

class CastNotifier extends StateNotifier<CastState> with WidgetsBindingObserver {
  CastNotifier(this.ref) : super(const CastState()) {
    WidgetsBinding.instance.addObserver(this);
  }

  final Ref ref;

  /// Dart timers freeze while Android caches/freezes the process, so on
  /// return to the foreground the receiver's state is requested fresh instead
  /// of trusting whatever the app believed when it was frozen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState != AppLifecycleState.resumed) return;
    final player = _activeReceiverPlayer;
    if (player == null || !state.isConnected) return;
    _log.info('App resumed while casting — requesting fresh receiver state');
    unawaited(player.onConnectionResumed());
  }

  bool _castInitialized = false;

  /// The kind of the currently-connected device, so the native Cast
  /// session listener only tears down for an actual Chromecast session (not
  /// while connected to DLNA/AirPlay).
  RemoteDeviceKind? _activeKind;

  /// The active Jellyfin-receiver player (native/desktop/web Chromecast), so
  /// the app-lifecycle hook can ask it to resync when the app comes back to
  /// the foreground.
  JellyfinReceiverPlayer? _activeReceiverPlayer;
  StreamSubscription<GoogleCastSession?>? _castSessionSub;
  StreamSubscription<List<GoogleCastDevice>>? _castDevicesSub;

  /// Bridge to the native side that opens the system AirPlay picker
  /// (`AVRoutePickerView`). It's the only way to present Apple's device sheet —
  /// there's no public programmatic API — so we trigger it from a hidden picker.
  static const _airplayChannel = MethodChannel('uk.jentejan.chudder/airplay');

  // Latest discovered devices per source, merged into the published list by
  // [_publishDevices]. Chromecast devices arrive live via `devicesStream` (so
  // they appear without a manual reload); DLNA renderers are filled by a scan.
  List<GoogleCastDevice> _castDevices = const [];
  List<CastDeviceInfo> _desktopCastDevices = const [];
  List<DlnaRenderer> _dlnaRenderers = const [];

  /// Rebuilds [CastState.devices] from the current sources, in a stable order:
  /// AirPlay, web, Chromecast, DLNA (audio-only renderers only while playing
  /// music).
  void _publishDevices() {
    final audioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? false;
    state = state.copyWith(devices: [
      if (_airPlaySupported) RemoteDevice.airplay(),
      if (webCastAvailable()) RemoteDevice.webCast(),
      ..._castDevices.map(RemoteDevice.chromecast),
      ..._desktopCastDevices.map(RemoteDevice.desktopChromecast),
      ..._dlnaRenderers.where((r) => r.supportsVideo || audioPlayback).map(RemoteDevice.dlna),
    ]);
  }

  /// The receiver app id the native Cast SDK currently runs with.
  String? _sdkAppId;

  /// The receiver app to launch on a Chromecast now.
  String get _receiverAppId => _useJellyfinReceiver ? ref.read(castReceiverAppIdProvider) : _defaultReceiverAppId;

  /// Initializes the native Cast SDK once, with the receiver the user picked,
  /// and moves an already running SDK over when the pick changed since.
  Future<void> _ensureCastInitialized() async {
    if (!_chromecastSupported) return;
    final appId = _receiverAppId;
    if (_castInitialized) {
      // Not under a running cast: a new receiver id ends the session on it.
      // The next connect applies it.
      if (!state.isConnected) await _applyReceiverAppId(appId);
      return;
    }
    try {
      final GoogleCastOptions options;
      if (Platform.isIOS) {
        // iOS picks devices by discovery criteria (the receiver to launch is
        // implicit in the criteria), not by an explicit appId like Android.
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(appId),
        );
      } else {
        // Android builds its options natively (ChudderCastOptionsProvider)
        // from the id stored here, so the SDK has them even when it starts
        // before Dart does.
        await JellyfinCastChannel.instance.setReceiverAppId(appId);
        options = GoogleCastOptionsAndroid(appId: appId);
      }
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _castInitialized = true;
      _sdkAppId = appId;

      // iOS only: detect a native Chromecast session ending outside the app and
      // restore local playback (#10). Android instead gets granular session
      // lifecycle events from its native SessionManagerListener (see
      // JellyfinCastPlayer.onInit) — there, a `disconnected` connection state
      // can also mean a *suspended* session the SDK is about to auto-resume
      // (the plugin maps both to the same value), so tearing down on it would
      // kill a healthy cast after any transient network drop.
      if (Platform.isIOS) {
        _castSessionSub ??= GoogleCastSessionManager.instance.currentSessionStream.listen((session) {
          final connectionState = session?.connectionState;
          final ended = session == null || connectionState == GoogleCastConnectState.disconnected;
          if (ended && _activeKind == RemoteDeviceKind.chromecast) {
            _handleExternalCastEnd();
          }
        });
      }

      // Chromecast devices arrive asynchronously and keep changing — publish
      // them live so they appear without the user hitting reload (#4).
      _castDevicesSub ??= GoogleCastDiscoveryManager.instance.devicesStream.listen((devices) {
        _castDevices = devices;
        _publishDevices();
      });
    } catch (error, stack) {
      _log.warning('Failed to initialize Cast SDK', error, stack);
    }
  }

  /// Moves the running Cast SDK to receiver [appId]. Android can do that on
  /// the spot; iOS reads it once per run of the app. Returns whether the SDK
  /// now uses it.
  Future<bool> _applyReceiverAppId(String appId) async {
    if (_sdkAppId == appId) return true;
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      if (await JellyfinCastChannel.instance.setReceiverAppId(appId)) {
        _log.info('Cast SDK moved to receiver $appId');
        _sdkAppId = appId;
        return true;
      }
    } catch (error) {
      _log.warning('Could not move the Cast SDK to receiver $appId: $error');
    }
    return false;
  }

  /// Whether a newly picked receiver is in use straight away. False only on
  /// iOS once the Cast SDK has started, where it takes a restart of the app.
  bool get receiverChangeNeedsRestart => !kIsWeb && Platform.isIOS && _castInitialized && _sdkAppId != _receiverAppId;

  /// Android gates LAN discovery behind runtime permissions, and both gates fail
  /// *silently* — mDNS (Chromecast) and SSDP (DLNA) return nothing rather than
  /// throwing — so we ask up front and surface a denial as a real error instead
  /// of an empty device list:
  ///
  /// - `NEARBY_WIFI_DEVICES` (Android 13+, targetSdk 33+) for the Wi-Fi scan the
  ///   Cast SDK runs while discovering. `flutter_chrome_cast` ships code to
  ///   request this but never wires it up, so it's on us.
  /// - `ACCESS_LOCAL_NETWORK` (Android 17+, targetSdk 37+) for raw
  ///   local-network sockets, via [LocalNetworkPermission] — the same grant the
  ///   app already needs to reach a server on the LAN.
  ///
  /// Returns false only when local-network access was actually denied; a denied
  /// nearby-Wi-Fi grant degrades discovery but doesn't block it outright.
  static bool _nearbyWifiGranted = false;

  Future<bool> _ensureDiscoveryPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    // Asked once per run; a grant that is held does not need a platform
    // round trip before every scan.
    if (!_nearbyWifiGranted) {
      final nearby = await Permission.nearbyWifiDevices.request();
      _nearbyWifiGranted = nearby.isGranted;
      if (!nearby.isGranted) {
        _log.warning('NEARBY_WIFI_DEVICES not granted ($nearby) — Chromecast discovery may find nothing');
      }
    }

    return LocalNetworkPermission.ensure();
  }

  /// Scans for Chromecast receivers (native Cast SDK) and DLNA renderers (SSDP),
  /// publishing devices **incrementally** as they're found so the picker fills
  /// in immediately instead of waiting for the whole scan window (#6).
  Future<void> discover({Duration timeout = const Duration(seconds: 5)}) async {
    if (state.discovering) return;
    state = state.copyWith(discovering: true, error: null);
    // Show fixed entries + any Chromecasts already known immediately.
    _publishDevices();
    // What the last scan found stays on the list while this one runs, and
    // is dropped only once this scan has finished without finding it again.
    // Clearing at the start left the picker empty for the whole window every
    // time it was opened, for a television picked moments before.
    final previousRenderers = _dlnaRenderers;
    final freshDesktopIds = <String>{};

    // `copyWith` treats a null `error` as "clear it", so the failure has to be
    // carried out here and applied together with `discovering: false` — setting
    // it inside the catch would be wiped by the finally.
    String? failure;
    try {
      if (!await _ensureDiscoveryPermissions()) {
        failure = 'Chudder needs local network access to find Chromecast and DLNA devices. '
            'Grant it under Settings → Apps → Chudder → Permissions, then scan again.';
        return;
      }

      await _ensureCastInitialized();
      if (_chromecastSupported) {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      }

      // Desktop: our own mDNS scan, published incrementally like DLNA below.
      // Runs concurrently with the SSDP scan since the two don't interact.
      // The same physical Chromecast can arrive from both scans (mDNS id is
      // its TXT id, SSDP id is its UDN), so dedupe by host as well as id.
      void addDesktopCastDevice(CastDeviceInfo device) {
        freshDesktopIds.add(device.id);
        final known = _desktopCastDevices.where((existing) => existing.id == device.id || existing.host == device.host);
        if (known.isNotEmpty) {
          freshDesktopIds.addAll(known.map((existing) => existing.id));
          return;
        }
        _desktopCastDevices = [..._desktopCastDevices, device];
        _publishDevices();
      }

      final Future<void> desktopScan = _desktopCastSupported
          ? CastMdnsDiscovery.discover(
              timeout: timeout,
              onDevice: addDesktopCastDevice,
            )
          : Future<void>.value();

      final renderers = <DlnaRenderer>[];
      if (_dlnaSupported) {
        await DlnaDiscovery.discover(
          timeout: timeout,
          onRenderer: (renderer) {
            renderers.add(renderer);
            _dlnaRenderers = [
              ...renderers,
              ...previousRenderers.where((previous) => renderers.every((found) => found.id != previous.id)),
            ];
            _publishDevices();
          },
          // Chromecasts announce over SSDP (DIAL) too — the reliable desktop
          // discovery path when mDNS delivery is broken on the host (Windows
          // 5353 contention, e.g. adb).
          onCastDevice: _desktopCastSupported ? addDesktopCastDevice : null,
        );
      }

      await desktopScan;
      // Only what this scan actually found.
      if (_dlnaSupported) _dlnaRenderers = List.of(renderers);
      _desktopCastDevices = _desktopCastDevices.where((device) => freshDesktopIds.contains(device.id)).toList();
      _publishDevices();
      _log.info('Discovery complete: ${state.devices.length} device(s)');
    } catch (error, stack) {
      _log.severe('Discovery failed', error, stack);
      failure = error.toString();
    } finally {
      state = state.copyWith(discovering: false, error: failure);
    }
  }

  /// Connects to [device] and hands the current playback off to it.
  Future<void> connect(RemoteDevice device) async {
    if (state.status == CastConnectionStatus.connecting || state.status == CastConnectionStatus.disconnecting) {
      return;
    }
    // Switching away from AirPlay: the system owns the AirPlay route and there's
    // no public API to deselect it, so we'd end up routed to two targets at
    // once. Block it and tell the user to stop AirPlay first (the system picker
    // / Control Center), rather than silently fighting the OS.
    if (_activeKind == RemoteDeviceKind.airplay &&
        device.kind != RemoteDeviceKind.airplay &&
        ref.read(videoPlayerProvider).isCasting) {
      state = state.copyWith(
        error: 'Stop AirPlay first — tap "${state.connectedDeviceName ?? 'AirPlay'}" above to '
            'disconnect, then choose ${device.name}.',
      );
      return;
    }
    _log.info('Connecting to ${device.kind.name} device "${device.name}"');
    state = state.copyWith(status: CastConnectionStatus.connecting, connectedDeviceName: device.name, error: null);
    // Switching targets while already casting: tear down the active session
    // first so e.g. AirPlay is actually stopped before Chromecast starts.
    if (ref.read(videoPlayerProvider).isCasting) {
      _log.info('Already casting — stopping the current session before switching');
      // Don't resume on the phone between devices — that briefly bleeds audio
      // out of the speaker. Keep the local player paused; the new device picks
      // up from the same position.
      await ref.read(videoPlayerProvider).stopCasting(resumeLocal: false);
    }
    try {
      final BasePlayer player;
      if (kIsWeb && device.kind == RemoteDeviceKind.chromecast) {
        // Web: hand the current item to the Jellyfin receiver via the Cast Web
        // Sender (requestSession pops Chrome's device picker).
        final context = _buildJellyfinContext();
        if (context == null) throw StateError('No item or credentials available to cast');
        player = await connectWebCast(context, appId: _receiverAppId, onSessionEnded: _handleExternalCastEnd);
      } else if (device.desktopCast != null) {
        // Desktop: our own CASTV2 client launches (or joins) the Jellyfin
        // receiver and talks to it over the same custom namespace the mobile
        // SDK uses.
        final context = _buildJellyfinContext();
        if (context == null) throw StateError('No item or credentials available to cast');
        final appId = _receiverAppId;
        final desktop = await DesktopJellyfinCastPlayer.connect(
          device.desktopCast!,
          appId,
          context,
          onSessionEnded: _handleExternalCastEnd,
        );
        _rememberDesktopSession(device.desktopCast!, appId, desktop.sessionId);
        player = desktop;
      } else if (device.kind == RemoteDeviceKind.chromecast) {
        if (_useJellyfinReceiver) {
          // The Jellyfin receiver plays the item itself. Make sure the SDK
          // launches the receiver the user picked.
          await _ensureCastInitialized();
          final context = _buildJellyfinContext();
          if (context == null) throw StateError('No item or credentials available to cast');
          player =
              await JellyfinCastPlayer.connect(device.cast!, context, onSessionEnded: _handleExternalCastEnd);
        } else {
          // Universal path: hand the default receiver a Chromecast-friendly
          // progressive transcode, re-served over plain HTTP by the phone. The
          // URL is resolved lazily per item at load time (connect-before-play).
          // Seed the client's current selection so the cast starts matching
          // it; audio only overrides when it differs from the source's native
          // default.
          final current = ref.read(playBackModel);
          final selectedAudio = current?.mediaStreams?.defaultAudioStreamIndex;
          final audioOverride =
              (selectedAudio != null && selectedAudio != _nativeDefaultAudioIndex(current)) ? selectedAudio : null;
          player = await CastPlayer.connect(
            device.cast!,
            streamBuilder: _chromecastStreamUrl,
            image: _currentItemImage(),
            initialAudioStreamIndex: audioOverride,
            initialSubtitleStreamIndex: current?.mediaStreams?.defaultSubStreamIndex,
            initialMaxBitrate: _selectedCastBitrate(current),
          );
        }
      } else if (device.kind == RemoteDeviceKind.airplay) {
        // Swap to an AVPlayer-backed player fed a Jellyfin HLS transcode (built
        // lazily per item); the user then routes it to the Apple TV via the
        // system AirPlay picker. Seed the tracks the client is using so the
        // cast starts with the same audio/subtitle selection (it always
        // transcodes, so the chosen audio is safe to bake in directly).
        final current = ref.read(playBackModel);
        player = await AirPlayVideoPlayer.connect(
          streamBuilder: _airplayStreamUrl,
          image: _currentItemImage(),
          onSessionEnded: _handleExternalCastEnd,
          initialAudioStreamIndex: current?.mediaStreams?.defaultAudioStreamIndex,
          initialSubtitleStreamIndex: current?.mediaStreams?.defaultSubStreamIndex,
        );
      } else {
        // Seed the client's current selection so the cast starts matching it.
        // Audio only overrides when it differs from the renderer's native
        // default (else direct play already serves the right track); a chosen
        // subtitle or non-original quality forces the transcode path.
        final current = ref.read(playBackModel);
        final selectedAudio = current?.mediaStreams?.defaultAudioStreamIndex;
        final audioOverride =
            (selectedAudio != null && selectedAudio != _nativeDefaultAudioIndex(current)) ? selectedAudio : null;
        player = await DlnaPlayer.connect(
          device.dlna!,
          streamBuilder: _dlnaStreamUrl,
          image: _currentItemImage(),
          castServerBase: ref.read(clientSettingsProvider).castServerUrl,
          onSessionEnded: _handleExternalCastEnd,
          initialAudioStreamIndex: audioOverride,
          initialSubtitleStreamIndex: current?.mediaStreams?.defaultSubStreamIndex,
          initialMaxBitrate: _selectedCastBitrate(current),
          knownDuration: () => ref.read(playBackModel)?.item.overview.runTime,
          title: () => ref.read(playBackModel)?.item.name,
          subtitleSidecarBuilder: _dlnaSubtitleSidecarUrl,
        );
      }
      await _takeOver(player, kind: device.kind, id: device.id, name: device.name);

      // AirPlay has no per-device target — the AVPlayer is now live with
      // external playback on; open the system picker so the user can route it to
      // an Apple TV. Video follows the route automatically.
      if (device.kind == RemoteDeviceKind.airplay) {
        unawaited(_presentAirPlayPicker());
      }

      // Connected with nothing playing locally: if the receiver already has a
      // stream in progress (started earlier or by another sender, e.g. the
      // phone), adopt it as the active playback instead of leaving the app
      // blank. Applies to every Jellyfin-receiver transport — mobile SDK,
      // desktop CASTV2 and web alike.
      if (player is JellyfinReceiverPlayer && ref.read(playBackModel) == null) {
        unawaited(_adoptRemotePlayback(player));
      }
    } catch (error, stack) {
      _log.severe('Failed to connect to "${device.name}"', error, stack);
      // Roll back a half-finished handoff: if the remote player got installed
      // before the failure, restore local playback so `isCasting` can't stay
      // true while the picker says "not connected".
      if (ref.read(videoPlayerProvider).isCasting) {
        try {
          await ref.read(videoPlayerProvider).stopCasting();
        } catch (rollbackError) {
          _log.warning('Rollback after failed connect also failed: $rollbackError');
        }
      }
      // A failed device *switch* left the phone paused holding pre-switch
      // media, with the receiver's position only stashed — restore a consistent
      // local state so that stale position/media can't leak into later playback
      // or a later cast. A no-op after a failed fresh connect.
      await ref.read(videoPlayerProvider).abortCastSwitch();
      state = state.copyWith(status: CastConnectionStatus.error, error: error.toString());
    }
  }

  /// Hands playback to [player] and marks the cast connected.
  Future<void> _takeOver(BasePlayer player, {required RemoteDeviceKind kind, required String id, required String name}) async {
    // Before the handoff: a receiver that carries on to its next queued item
    // straight away must find the app listening.
    if (player is JellyfinReceiverPlayer) player.onReceiverChangedItem = _followReceiver;
    await ref.read(videoPlayerProvider).startCasting(player);
    _activeKind = kind;
    _activeReceiverPlayer = player is JellyfinReceiverPlayer ? player : null;
    _log.info('Now casting to "$name"');
    state = state.copyWith(
      status: CastConnectionStatus.connected,
      connectedDeviceName: name,
      connectedDeviceId: id,
      canLeavePlaying: player is RemotePlayer && (player as RemotePlayer).canLeavePlaying,
    );
  }

  /// The receiver started another item by itself — the next one of its queue
  /// when one ended (also with this app closed, in which case this runs when
  /// the app is back), or a skip with the TV's remote. Shows that item as the
  /// one playing, with the queue moved along to it.
  Future<void> _followReceiver(String itemId) async {
    final current = ref.read(playBackModel);
    if (current == null || current.item.id == itemId || !state.isConnected) return;

    final queue = current.playbackQueue;
    final known = [...queue.queue, ...queue.nextUpQueue].firstWhereOrNull((entry) => entry.id == itemId);
    final item = known ?? (await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: itemId)).body;
    if (item == null) throw StateError('Item $itemId not found on the server');
    // An item outside the queue the app knows (started from another app)
    // brings its own.
    final model = await ref.read(playbackModelHelper).createPlaybackModel(
          null,
          item,
          oldModel: known != null ? current : null,
        );
    if (model == null) throw StateError('No playback model for $itemId');

    // The user may have switched or disconnected while this was loading.
    if (!state.isConnected || ref.read(playBackModel)?.item.id != current.item.id) return;
    final advanced = known != null ? queue.advanceFromCurrentTo(current.item.id, itemId) : null;
    await ref.read(videoPlayerProvider).followCastItem(advanced != null ? model.updatePlaybackQueue(advanced) : model);
    _log.info('Following the receiver: now showing "${item.name}"');
  }

  /// Picks a running cast back up after this app was closed and opened again:
  /// the session the Cast SDK resumed on its own (Android), the one this
  /// desktop app remembers, or the one a reloaded browser tab auto-joined.
  /// Quietly does nothing when there is none, or when the TV is no longer
  /// playing anything of ours.
  ///
  /// Google's sender checklist asks for exactly this: leaving the app leaves
  /// the TV playing, and coming back shows its controls again.
  Future<void> restoreSession() async {
    if (state.status != CastConnectionStatus.idle) return;
    if (ref.read(videoPlayerProvider).isCasting || ref.read(playBackModel) != null) return;
    if (!_useJellyfinReceiver) return;
    final context = _buildJellyfinContext();
    if (context == null) return;

    JellyfinReceiverPlayer? player;
    String? id;
    String? name;
    try {
      if (kIsWeb) {
        final resumed = await resumeWebCast(context, onSessionEnded: _handleExternalCastEnd);
        if (resumed is JellyfinReceiverPlayer) {
          player = resumed;
          id = RemoteDevice.webCast().id;
          name = resumed.deviceName;
        }
      } else if (_chromecastSupported && Platform.isAndroid) {
        await _ensureCastInitialized();
        final session = await _awaitResumedSdkSession();
        if (session == null) return;
        player = await JellyfinCastPlayer.attach(session.deviceName, context, onSessionEnded: _handleExternalCastEnd);
        id = 'cast:${session.deviceId}';
        name = session.deviceName;
      } else if (_desktopCastSupported) {
        final saved = _rememberedDesktopSession();
        if (saved == null) return;
        try {
          player = await DesktopJellyfinCastPlayer.connect(
            saved.device,
            saved.appId,
            context,
            joinSessionId: saved.sessionId,
            onSessionEnded: _handleExternalCastEnd,
            timeout: const Duration(seconds: 6),
          );
        } on CastSessionGoneException {
          _forgetDesktopSession();
          return;
        }
        id = RemoteDevice.desktopChromecast(saved.device).id;
        name = saved.device.name;
      }
    } catch (error) {
      _log.info('No cast to pick back up: $error');
      return;
    }
    if (player == null || id == null || name == null) return;
    // Something else took over while we were joining.
    if (state.status != CastConnectionStatus.idle || ref.read(playBackModel) != null) {
      await player.leave();
      return;
    }

    _log.info('Picking the cast on "$name" back up');
    state = state.copyWith(status: CastConnectionStatus.connecting, connectedDeviceName: name, error: null);
    try {
      await _takeOver(player, kind: RemoteDeviceKind.chromecast, id: id, name: name);
    } catch (error, stack) {
      _log.warning('Could not pick the cast back up', error, stack);
      state = CastState(devices: state.devices, discovering: state.discovering);
      return;
    }
    // An idle receiver — stopped on the TV since — is nothing to come back
    // to: leave it be rather than hold a session on it.
    if (!await _adoptRemotePlayback(player)) {
      _log.info('"$name" is not playing anything — letting it go');
      await leave();
    }
  }

  /// The Cast SDK resumes a saved session by itself shortly after it starts;
  /// waits a few seconds for that. Null when there is nothing to resume.
  Future<({String deviceId, String deviceName, bool connected})?> _awaitResumedSdkSession() async {
    final started = DateTime.now();
    while (true) {
      final waited = DateTime.now().difference(started);
      final session = await JellyfinCastChannel.instance.currentSession();
      if (session != null && session.connected) return session;
      // No session at all after a few seconds: there was nothing to resume.
      // One still resuming gets a little longer to finish.
      if (session == null && waited > const Duration(seconds: 4)) return null;
      if (waited > const Duration(seconds: 10)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Remembers the desktop session so the next start of the app can rejoin it.
  void _rememberDesktopSession(CastDeviceInfo device, String appId, String sessionId) {
    unawaited(ref.read(sharedPreferencesProvider).setString(
          _desktopSessionKey,
          jsonEncode({
            'id': device.id,
            'name': device.name,
            'host': device.host,
            'port': device.port,
            'appId': appId,
            'sessionId': sessionId,
          }),
        ));
  }

  void _forgetDesktopSession() {
    if (!_desktopCastSupported) return;
    unawaited(ref.read(sharedPreferencesProvider).remove(_desktopSessionKey));
  }

  ({CastDeviceInfo device, String appId, String sessionId})? _rememberedDesktopSession() {
    final raw = ref.read(sharedPreferencesProvider).getString(_desktopSessionKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        device: CastDeviceInfo(
          id: json['id'] as String,
          name: json['name'] as String,
          host: json['host'] as String,
          port: json['port'] as int,
        ),
        appId: json['appId'] as String,
        sessionId: json['sessionId'] as String,
      );
    } catch (_) {
      _forgetDesktopSession();
      return null;
    }
  }

  /// Opens the system AirPlay picker so the user can choose an Apple TV for the
  /// now-active AVPlayer session. Best-effort: if the native side can't present
  /// it (older OS, no route button), the AVPlayer still plays locally and the
  /// user can route via Control Center.
  Future<void> _presentAirPlayPicker() async {
    try {
      await _airplayChannel.invokeMethod<void>('present');
    } catch (error) {
      _log.warning('Could not open the system AirPlay picker: $error');
    }
  }

  /// Releases the system AirPlay route on disconnect (iOS deactivates the audio
  /// session; no-op on macOS). Without this, the route stays selected and local
  /// playback keeps casting its audio to the Apple TV.
  Future<void> _endAirPlay() async {
    try {
      await _airplayChannel.invokeMethod<void>('stop');
    } catch (error) {
      _log.warning('Could not release the AirPlay route: $error');
    }
  }

  /// Gathers the credentials + current item (if any — connecting without
  /// active playback puts the app in remote-control mode) for the receiver.
  JellyfinCastContext? _buildJellyfinContext() {
    final current = ref.read(playBackModel);
    final credentials = ref.read(userProvider)?.credentials;
    final userId = ref.read(userProvider)?.id;
    if (credentials == null || userId == null) return null;

    final item = current?.item;
    return JellyfinCastContext(
      serverAddress: credentials.url,
      accessToken: credentials.token,
      userId: userId,
      deviceId: credentials.deviceId,
      serverId: credentials.serverId,
      serverVersion: '',
      itemStub: item == null
          ? const {}
          : jellyfinItemStub(item, serverId: credentials.serverId, audio: current!.isAudioPlayback),
      upcoming: castUpcomingFor(ref, current),
      startPosition: ref.read(videoPlayerProvider).lastState?.position ?? Duration.zero,
      // A quality the user capped carries over (the receiver otherwise runs a
      // bandwidth test before the first play and picks its own).
      maxBitrate: switch (_selectedCastBitrate(current)) {
        final cap? when cap < _dlnaOriginalBitrate => cap,
        _ => null,
      },
      // Without mediaSourceId the server ignores the track indexes entirely.
      mediaSourceId: current?.mediaStreams?.currentVersionStream?.id ?? item?.id,
      audioStreamIndex: current?.mediaStreams?.defaultAudioStreamIndex,
      subtitleStreamIndex: current?.mediaStreams?.defaultSubStreamIndex,
      subtitleAppearance: receiverSubtitleAppearance(ref.read(subtitleSettingsProvider)),
      image: _currentItemImage(),
    );
  }

  /// Builds a Chromecast-compatible stream URL for the current item by asking
  /// Jellyfin for a progressive transcode constrained to what the default
  /// receiver can decode (H.264 ≤ L4.1, ≤ 1080p, ≤ 8 Mbps, AAC stereo — see
  /// [chromecastProfile]). Returns null if there's no item or no transcode.
  Future<String?> _chromecastStreamUrl({
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? maxBitrate,
    Duration? startPosition,
  }) async {
    final current = ref.read(playBackModel);
    if (current == null) return null;
    final hasSubtitle = subtitleStreamIndex != null && subtitleStreamIndex >= 0;
    // A real quality cap (below the "original" sentinel) lowers the transcode
    // bitrate; null/auto/original keeps the default cast cap.
    final cappedBitrate = (maxBitrate != null && maxBitrate < _dlnaOriginalBitrate) ? maxBitrate : null;
    try {
      final response = await ref.read(jellyApiProvider).itemsItemIdPlaybackInfoPost(
            itemId: current.item.id,
            body: PlaybackInfoDto(
              userId: ref.read(userProvider)?.id,
              autoOpenLiveStream: true,
              enableTranscoding: true,
              enableDirectPlay: false,
              enableDirectStream: false,
              // The progressive transcode begins here, so casting a
              // half-watched item resumes: the receiver can't time-seek a live
              // transcode.
              startTimeTicks:
                  startPosition != null && startPosition > Duration.zero ? startPosition.inMicroseconds * 10 : null,
              maxStreamingBitrate: cappedBitrate ?? chromecastMaxBitrate,
              deviceProfile: chromecastProfile,
              // Without mediaSourceId the server ignores the track indexes.
              mediaSourceId: current.mediaStreams?.currentVersionStream?.id ?? current.item.id,
              audioStreamIndex: audioStreamIndex,
              subtitleStreamIndex: hasSubtitle ? subtitleStreamIndex : null,
              // The default receiver can't render a separate track, so burn it in.
              alwaysBurnInSubtitleWhenTranscoding: hasSubtitle,
            ),
          );
      final mediaSource = response.body?.mediaSources?.firstOrNull;
      final transcodingUrl = mediaSource?.transcodingUrl;
      if (transcodingUrl == null) {
        _log.warning('No transcoding URL returned for Chromecast');
        return null;
      }
      final url = buildServerUrl(ref, relativeUrl: transcodingUrl);
      _log.info('Chromecast transcode stream resolved');
      return url;
    } catch (error, stack) {
      _log.warning('Failed to resolve Chromecast transcode URL', error, stack);
      return null;
    }
  }

  /// Builds an AirPlay-compatible stream URL for the current item: a Jellyfin
  /// **HLS** transcode constrained to what `AVPlayer` decodes (H.264/AAC — see
  /// [airplayProfile]). [audioStreamIndex]/[subtitleStreamIndex] select tracks
  /// for mid-play switching; the subtitle is burned in because AVPlayer over HLS
  /// shows that most reliably. Returns null if there's no item or no transcode.
  Future<String?> _airplayStreamUrl({int? audioStreamIndex, int? subtitleStreamIndex}) async {
    final current = ref.read(playBackModel);
    if (current == null) return null;
    final hasSubtitle = subtitleStreamIndex != null && subtitleStreamIndex >= 0;
    try {
      final response = await ref.read(jellyApiProvider).itemsItemIdPlaybackInfoPost(
            itemId: current.item.id,
            body: PlaybackInfoDto(
              userId: ref.read(userProvider)?.id,
              autoOpenLiveStream: true,
              enableTranscoding: true,
              enableDirectPlay: false,
              enableDirectStream: false,
              maxStreamingBitrate: airplayMaxBitrate,
              deviceProfile: airplayProfile,
              // Track selection needs the mediaSourceId or the server ignores it.
              mediaSourceId: current.mediaStreams?.currentVersionStream?.id ?? current.item.id,
              audioStreamIndex: audioStreamIndex,
              // -1 is "off" and has to reach the server as -1. Sending no
              // index at all asks Jellyfin to choose a subtitle by the user's
              // preferences, which is how turning subtitles off left one on
              // the Apple TV.
              subtitleStreamIndex: subtitleStreamIndex,
              alwaysBurnInSubtitleWhenTranscoding: hasSubtitle,
            ),
          );
      final mediaSource = response.body?.mediaSources?.firstOrNull;
      final transcodingUrl = mediaSource?.transcodingUrl;
      if (transcodingUrl == null) {
        _log.warning('No transcoding URL returned for AirPlay');
        return null;
      }
      final url = buildServerUrl(ref, relativeUrl: transcodingUrl);
      _log.info('AirPlay HLS transcode stream resolved');
      return url;
    } catch (error, stack) {
      _log.warning('Failed to resolve AirPlay transcode URL', error, stack);
      return null;
    }
  }

  /// The current item's backdrop/poster for the casting placeholder (shared by
  /// every remote player so the casting UI looks the same). Falls through
  /// backdrop → primary → logo so episodes (which usually lack their own
  /// backdrop) still get a background instead of a blank black screen.
  ImageProvider? _currentItemImage() {
    final images = ref.read(playBackModel)?.item.images;
    return (images?.backDrop?.firstOrNull ?? images?.primary ?? images?.logo)?.imageProvider;
  }

  /// The audio track the renderer would pick on its own (the container's default
  /// or first), so we only force a transcode when the user actually chose a
  /// *different* one — picking the default still allows direct play.
  int? _nativeDefaultAudioIndex(PlaybackModel? model) {
    final audio = model?.mediaStreams?.audioStreams;
    return (audio?.firstWhereOrNull((stream) => stream.isDefault) ?? audio?.firstOrNull)?.index;
  }

  /// Maps the currently-selected quality to a max-bitrate cap for casting:
  /// "Original" → a very high sentinel (so it direct-plays), "Auto"/none → no
  /// cap, a specific quality → its bitrate (which forces a transcode).
  int? _selectedCastBitrate(PlaybackModel? model) {
    final selected = model?.bitRateOptions.enabledFirst.keys.firstOrNull;
    return switch (selected) {
      null || Bitrate.auto => null,
      Bitrate.original => _dlnaOriginalBitrate,
      _ => selected.bitRate,
    };
  }

  /// Builds a DLNA-compatible stream URL for the current item: a Jellyfin
  /// progressive MP4 transcode constrained to what renderers decode (H.264/AAC
  /// — see [dlnaProfile]). Returns null if there's no item or no transcode.
  /// "Original" quality maps to this sentinel cap (see [applyCastQuality]); at or
  /// above it we don't force a transcode, so the file can direct-play.
  static const _dlnaOriginalBitrate = 1000000000;

  /// Whether the selected subtitle stream is text-based (servable as an SRT
  /// sidecar). Image subs (PGS/VOBSUB/DVB) can only be burned in.
  bool _isTextSubtitle(PlaybackModel model, int subtitleStreamIndex) {
    final sub = model.mediaStreams?.subStreams.firstWhereOrNull((s) => s.index == subtitleStreamIndex);
    if (sub == null) return false;
    const textCodecs = {'srt', 'subrip', 'ass', 'ssa', 'vtt', 'webvtt', 'mov_text', 'text', 'ttml'};
    return textCodecs.contains(sub.codec.toLowerCase());
  }

  /// Builds the Jellyfin SRT URL for a text subtitle stream, for the DLNA
  /// sidecar (CaptionInfoEx) path. Null when the track isn't text-based —
  /// the caller then falls back to the burn-in transcode.
  ///
  /// [startOffset] shifts the cues by where the stream begins (the server's
  /// `startPositionTicks` route segment), so the subtitles of a transcode begun
  /// at the resume point are not that far out of step.
  Future<String?> _dlnaSubtitleSidecarUrl(int subtitleStreamIndex, Duration startOffset) async {
    final current = ref.read(playBackModel);
    if (current == null || !_isTextSubtitle(current, subtitleStreamIndex)) return null;
    final mediaSourceId = current.mediaStreams?.currentVersionStream?.id ?? current.item.id;
    final startTicks = startOffset.inMicroseconds * 10;
    return buildServerUrl(
      ref,
      pathSegments: [
        'Videos',
        current.item.id,
        mediaSourceId,
        'Subtitles',
        '$subtitleStreamIndex',
        '$startTicks',
        'Stream.srt',
      ],
      queryParameters: authQueryParameters(ref.read(userProvider)?.credentials.token),
    );
  }

  Future<DlnaStream?> _dlnaStreamUrl({
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? maxBitrate,
    Duration? startPosition,
  }) async {
    final current = ref.read(playBackModel);
    if (current == null) return null;

    final hasSubtitle = subtitleStreamIndex != null && subtitleStreamIndex >= 0;
    // A text subtitle rides along as an SRT sidecar (CaptionInfoEx) so the
    // video can direct-play — burning it in means a live transcode that webOS
    // frequently refuses to start. Only image subs (PGS/VOBSUB) still need
    // the burn-in path.
    final sidecarSubtitle = hasSubtitle && _isTextSubtitle(current, subtitleStreamIndex);
    // A real quality cap (anything below the "original" sentinel) forces a
    // transcode; null/auto/original leave the file direct-playable.
    final cappedBitrate = (maxBitrate != null && maxBitrate < _dlnaOriginalBitrate) ? maxBitrate : null;
    // The renderer can't switch embedded tracks or burn subs itself, so any of
    // these selections requires a server-side transcode.
    final forceTranscode = (hasSubtitle && !sidecarSubtitle) || audioStreamIndex != null || cappedBitrate != null;
    final burnInSubtitle = hasSubtitle && !sidecarSubtitle;

    try {
      final response = await ref.read(jellyApiProvider).itemsItemIdPlaybackInfoPost(
            itemId: current.item.id,
            body: PlaybackInfoDto(
              userId: ref.read(userProvider)?.id,
              autoOpenLiveStream: true,
              enableTranscoding: true,
              // Begin a transcode at the resume position (1 tick = 100ns) so it
              // plays from the right place — a live transcode can't be
              // time-seeked afterwards. Sent even when we don't force one: the
              // server may still transcode a source the renderer can't take.
              // Ignored by a direct stream.
              startTimeTicks: startPosition != null && startPosition > Duration.zero
                  ? startPosition.inMicroseconds * 10
                  : null,
              // Prefer handing the renderer the original file: capable TVs
              // (webOS/Tizen) play it directly, whereas a forced *live*
              // transcode often can't start on them (it answers UPnP 501 then
              // 701 — it fetches the stream but never transitions to PLAYING).
              // Direct play is disabled only when a track/quality override needs
              // a transcode; otherwise it stays on for compatible sources.
              enableDirectPlay: !forceTranscode,
              enableDirectStream: !forceTranscode,
              maxStreamingBitrate: cappedBitrate ?? dlnaMaxBitrate,
              deviceProfile: dlnaProfile,
              // Without mediaSourceId the server ignores the track indexes.
              mediaSourceId: current.mediaStreams?.currentVersionStream?.id ?? current.item.id,
              audioStreamIndex: audioStreamIndex,
              // A sidecar subtitle is fetched separately by the TV — telling
              // the server about it here would force a transcode for nothing.
              subtitleStreamIndex: burnInSubtitle ? subtitleStreamIndex : null,
              alwaysBurnInSubtitleWhenTranscoding: burnInSubtitle,
            ),
          );
      final mediaSource = response.body?.mediaSources?.firstOrNull;
      if (mediaSource == null) {
        _log.warning('No media source returned for DLNA');
        return null;
      }

      // Direct stream: the same static-file URL the local player uses. A
      // complete file with Range support is what DLNA renderers reliably play.
      if (!forceTranscode &&
          ((mediaSource.supportsDirectStream ?? false) || (mediaSource.supportsDirectPlay ?? false))) {
        final url = buildServerUrl(
          ref,
          pathSegments: ['Videos', mediaSource.id!, 'stream'],
          queryParameters: {
            'Static': 'true',
            'mediaSourceId': mediaSource.id,
            ...authQueryParameters(ref.read(userProvider)?.credentials.token),
            if (mediaSource.eTag != null) 'Tag': mediaSource.eTag,
            if (mediaSource.liveStreamId != null) 'LiveStreamId': mediaSource.liveStreamId,
          },
        );
        _log.info('DLNA direct stream resolved');
        return DlnaStream(url, transcoding: false);
      }

      final transcodingUrl = mediaSource.transcodingUrl;
      if (transcodingUrl == null) {
        _log.warning('No DLNA stream URL (no direct support, no transcode)');
        return null;
      }
      _log.info('DLNA transcode stream resolved${forceTranscode ? '' : ' (source not directly playable)'}');
      return DlnaStream(
        buildServerUrl(ref, relativeUrl: transcodingUrl),
        transcoding: true,
        startOffset: startPosition ?? Duration.zero,
      );
    } catch (error, stack) {
      _log.warning('Failed to resolve DLNA stream URL', error, stack);
      return null;
    }
  }

  /// Adopts a stream already running on the receiver: fetches the reported
  /// item, builds a playback model for it (without restarting the stream) and
  /// surfaces the bottom player bar so the app controls the existing cast.
  /// Returns whether the receiver was playing something.
  Future<bool> _adoptRemotePlayback(JellyfinReceiverPlayer player) async {
    try {
      final itemId = await player.waitForNowPlayingItem(const Duration(seconds: 4));
      if (itemId == null) return false;
      _log.info('Adopting in-progress cast of item $itemId');

      final response = await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: itemId);
      final item = response.body;
      if (item == null) return true;

      final model = await ref.read(playbackModelHelper).createPlaybackModel(null, item);
      if (model == null) return true;

      ref.read(playBackModel.notifier).update((_) => model);
      // Future restarts (track/quality changes) must target the adopted item,
      // and the receiver's own queue behind it is the one the app plays too.
      ref.read(videoPlayerProvider).pointReceiverAt(player, model);
      ref.read(mediaPlaybackProvider.notifier).update(
            (s) => s.copyWith(state: VideoPlayerState.minimized, buffering: false),
          );
    } catch (error, stack) {
      _log.warning('Failed to adopt remote playback', error, stack);
    }
    return true;
  }

  /// Stops casting and resumes playback locally. Surfaces a `disconnecting`
  /// state because closing the remote session (e.g. UPnP Stop to a DLNA
  /// renderer) can take a moment — the picker shows progress instead of
  /// looking frozen.
  ///
  /// Must always land on `idle`: `connect` refuses to run while the status is
  /// `connecting`/`disconnecting`, so a disconnect that never resolves would
  /// wedge casting for the rest of the app session.
  Future<void> disconnect() async {
    if (state.status == CastConnectionStatus.disconnecting) return;
    final wasAirPlay = _activeKind == RemoteDeviceKind.airplay;
    state = state.copyWith(status: CastConnectionStatus.disconnecting);
    _activeKind = null;
    _activeReceiverPlayer = null;
    _forgetDesktopSession();
    try {
      await ref.read(videoPlayerProvider).stopCasting();
      // Tearing down our AVPlayer doesn't deselect the system AirPlay route, so
      // local playback would keep routing its audio to the Apple TV. Ask the
      // native side to release the route so playback returns to the device.
      if (wasAirPlay) await _endAirPlay();
    } catch (error, stack) {
      _log.warning('Disconnect did not complete cleanly', error, stack);
    } finally {
      _resetToIdle();
    }
  }

  /// Disconnects and leaves the device playing (when it can play on without
  /// this app); the app keeps nothing loaded. For closing the app, and for
  /// "keep watching on the TV" in the picker. A desktop session stays
  /// remembered, so the next start of the app picks it back up.
  Future<void> leave() async {
    if (state.status == CastConnectionStatus.disconnecting || state.status == CastConnectionStatus.idle) return;
    state = state.copyWith(status: CastConnectionStatus.disconnecting);
    final wasAirPlay = _activeKind == RemoteDeviceKind.airplay;
    _activeKind = null;
    _activeReceiverPlayer = null;
    try {
      await ref.read(videoPlayerProvider).leaveCasting();
      if (wasAirPlay) await _endAirPlay();
    } catch (error, stack) {
      _log.warning('Leaving the cast did not complete cleanly', error, stack);
    } finally {
      _resetToIdle();
    }
  }

  /// Fresh state rather than copyWith: copyWith's `?? this.x` semantics can't
  /// clear connectedDeviceName/Id, and a stale device id makes the picker
  /// treat a later failed reconnect as a success (its pop check compares
  /// against connectedDeviceId).
  void _resetToIdle() {
    state = CastState(
      devices: state.devices,
      discovering: state.discovering,
      status: CastConnectionStatus.idle,
    );
  }

  /// Called when a cast session ends outside the app (e.g. the user stops it
  /// from Chrome's own cast UI). Tears down our casting state so the app stops
  /// believing it's still casting. Guarded so our own [disconnect] (which also
  /// ends the session) doesn't re-enter.
  void _handleExternalCastEnd() {
    if (state.status == CastConnectionStatus.idle || state.status == CastConnectionStatus.disconnecting) return;
    _log.info('Cast session ended externally — restoring local playback');
    unawaited(disconnect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _castSessionSub?.cancel();
    _castDevicesSub?.cancel();
    super.dispose();
  }
}

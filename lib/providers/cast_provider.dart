import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/profiles/airplay_profile.dart';
import 'package:fladder/profiles/chromecast_profile.dart';
import 'package:fladder/profiles/dlna_profile.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/util/local_network_permission.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/wrappers/players/airplay_video_player.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:fladder/wrappers/players/cast/desktop/desktop_cast_player.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/web/cast_web.dart';
import 'package:fladder/wrappers/players/cast_player.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';
import 'package:fladder/wrappers/players/dlna_player.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_player.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

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

/// The Cast SDK fixes the receiver app id for the whole process (it's read once
/// when the CastContext singleton is first created), so we can only use ONE
/// receiver per app run — we can't pick per-device at connect time.
///
/// - Default media receiver (`CC1AD845`): a tiny native player that runs on
///   *every* Chromecast generation, including the 2013 first-gen dongle. We feed
///   it a progressive H.264/AAC transcode (see [chromecastProfile]).
/// - Jellyfin receiver (`F007D354`): nicer (server-side playback, in-receiver
///   track switching) but its modern JS web app only runs on 2nd-gen+ devices.
///
/// Default to the universal receiver; flip [_useJellyfinReceiver] for a
/// modern-only deployment that wants the richer Jellyfin path.
const _useJellyfinReceiver = true;
const _defaultReceiverAppId = 'CC1AD845';
const _jellyfinReceiverAppId = 'F007D354';
String get _chromecastAppId => _useJellyfinReceiver ? _jellyfinReceiverAppId : _defaultReceiverAppId;

enum CastConnectionStatus { idle, connecting, connected, disconnecting, error }

class CastState {
  final List<RemoteDevice> devices;
  final bool discovering;
  final CastConnectionStatus status;
  final String? connectedDeviceName;
  final String? connectedDeviceId;
  final String? error;

  const CastState({
    this.devices = const [],
    this.discovering = false,
    this.status = CastConnectionStatus.idle,
    this.connectedDeviceName,
    this.connectedDeviceId,
    this.error,
  });

  bool get isConnected => status == CastConnectionStatus.connected;

  CastState copyWith({
    List<RemoteDevice>? devices,
    bool? discovering,
    CastConnectionStatus? status,
    String? connectedDeviceName,
    String? connectedDeviceId,
    String? error,
  }) {
    return CastState(
      devices: devices ?? this.devices,
      discovering: discovering ?? this.discovering,
      status: status ?? this.status,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
      connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
      error: error,
    );
  }
}

final _log = Logger('Cast');

final castProvider = StateNotifierProvider<CastNotifier, CastState>((ref) => CastNotifier(ref));

class CastNotifier extends StateNotifier<CastState> {
  CastNotifier(this.ref) : super(const CastState());

  final Ref ref;

  bool _castInitialized = false;

  /// The kind of the currently-connected device, so the native Cast
  /// session listener only tears down for an actual Chromecast session (not
  /// while connected to DLNA/AirPlay).
  RemoteDeviceKind? _activeKind;
  StreamSubscription<GoogleCastSession?>? _castSessionSub;
  StreamSubscription<List<GoogleCastDevice>>? _castDevicesSub;

  /// Bridge to the native side that opens the system AirPlay picker
  /// (`AVRoutePickerView`). It's the only way to present Apple's device sheet —
  /// there's no public programmatic API — so we trigger it from a hidden picker.
  static const _airplayChannel = MethodChannel('nl.jknaapen.fladder/airplay');

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

  /// Initializes the native Cast SDK once. The Cast SDK fixes the receiver
  /// (Android) or discovery criteria (iOS) at first init; subsequent calls are
  /// no-ops.
  Future<void> _ensureCastInitialized() async {
    if (_castInitialized || !_chromecastSupported) return;
    try {
      final GoogleCastOptions options;
      if (Platform.isIOS) {
        // iOS picks devices by discovery criteria (the receiver to launch is
        // implicit in the criteria), not by an explicit appId like Android.
        options = IOSGoogleCastOptions(
          GoogleCastDiscoveryCriteriaInitialize.initWithApplicationID(_chromecastAppId),
        );
      } else {
        options = GoogleCastOptionsAndroid(appId: _chromecastAppId);
      }
      await GoogleCastContext.instance.setSharedInstanceWithOptions(options);
      _castInitialized = true;

      // Detect a native Chromecast session ending outside the app — the receiver
      // taken over by another sender, turned off, or otherwise disconnected —
      // and restore local playback (#10).
      _castSessionSub ??= GoogleCastSessionManager.instance.currentSessionStream.listen((session) {
        final connectionState = session?.connectionState;
        final ended = session == null || connectionState == GoogleCastConnectState.disconnected;
        if (ended && _activeKind == RemoteDeviceKind.chromecast) {
          _handleExternalCastEnd();
        }
      });

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
  Future<bool> _ensureDiscoveryPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final nearby = await Permission.nearbyWifiDevices.request();
    if (!nearby.isGranted) {
      _log.warning('NEARBY_WIFI_DEVICES not granted ($nearby) — Chromecast discovery may find nothing');
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
    // Fresh DLNA scan; Chromecast devices keep flowing via the devicesStream.
    _dlnaRenderers = const [];
    // Desktop Chromecasts are scan-based too, so they're re-found each time
    // rather than lingering after a device goes away.
    _desktopCastDevices = const [];

    // `copyWith` treats a null `error` as "clear it", so the failure has to be
    // carried out here and applied together with `discovering: false` — setting
    // it inside the catch would be wiped by the finally.
    String? failure;
    try {
      if (!await _ensureDiscoveryPermissions()) {
        failure = 'Fladder needs local network access to find Chromecast and DLNA devices. '
            'Grant it under Settings → Apps → Fladder → Permissions, then scan again.';
        return;
      }

      await _ensureCastInitialized();
      if (_chromecastSupported) {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      }

      // Desktop: our own mDNS scan, published incrementally like DLNA below.
      // Runs concurrently with the SSDP scan since the two don't interact.
      final Future<void> desktopScan = _desktopCastSupported
          ? CastMdnsDiscovery.discover(
              timeout: timeout,
              onDevice: (device) {
                if (_desktopCastDevices.any((existing) => existing.id == device.id)) return;
                _desktopCastDevices = [..._desktopCastDevices, device];
                _publishDevices();
              },
            ).then((devices) => _desktopCastDevices = devices)
          : Future<void>.value();

      if (_dlnaSupported) {
        final renderers = <DlnaRenderer>[];
        await DlnaDiscovery.discover(
          timeout: timeout,
          onRenderer: (renderer) {
            renderers.add(renderer);
            _dlnaRenderers = List.of(renderers);
            _publishDevices();
          },
        );
      }

      await desktopScan;
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
      await ref.read(videoPlayerProvider).stopCasting();
    }
    try {
      final BasePlayer player;
      JellyfinCastPlayer? jellyfinPlayer;
      if (kIsWeb && device.kind == RemoteDeviceKind.chromecast) {
        // Web: hand the current item to the Jellyfin receiver via the Cast Web
        // Sender (requestSession pops Chrome's device picker).
        final context = _buildJellyfinContext();
        if (context == null) throw StateError('No item or credentials available to cast');
        player = await connectWebCast(context, onSessionEnded: _handleExternalCastEnd);
      } else if (device.desktopCast != null) {
        // Desktop: our own CASTV2 client launches the Jellyfin receiver and
        // talks to it over the same custom namespace the mobile SDK uses.
        final context = _buildJellyfinContext();
        if (context == null) throw StateError('No item or credentials available to cast');
        player = await DesktopJellyfinCastPlayer.connect(
          device.desktopCast!,
          context,
          onSessionEnded: _handleExternalCastEnd,
        );
      } else if (device.kind == RemoteDeviceKind.chromecast) {
        if (_useJellyfinReceiver) {
          // Modern-only path: the Jellyfin receiver plays the item itself.
          final context = _buildJellyfinContext();
          if (context == null) throw StateError('No item or credentials available to cast');
          player = jellyfinPlayer =
              await JellyfinCastPlayer.connect(device.cast!, context, onSessionEnded: _handleExternalCastEnd);
        } else {
          // Universal path: hand the default receiver a Chromecast-friendly
          // progressive transcode, re-served over plain HTTP by the phone. The
          // URL is resolved lazily per item at load time (connect-before-play).
          player = await CastPlayer.connect(
            device.cast!,
            streamBuilder: _chromecastStreamUrl,
            image: _currentItemImage(),
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
        );
      }
      await ref.read(videoPlayerProvider).startCasting(player);
      _activeKind = device.kind;
      _log.info('Now casting to "${device.name}"');
      state = state.copyWith(
        status: CastConnectionStatus.connected,
        connectedDeviceName: device.name,
        connectedDeviceId: device.id,
      );

      // AirPlay has no per-device target — the AVPlayer is now live with
      // external playback on; open the system picker so the user can route it to
      // an Apple TV. Video follows the route automatically.
      if (device.kind == RemoteDeviceKind.airplay) {
        unawaited(_presentAirPlayPicker());
      }

      // Connected with nothing playing locally: if the receiver already has a
      // stream in progress (started earlier or by another sender), adopt it as
      // the active playback instead of leaving the app blank.
      if (jellyfinPlayer != null && ref.read(playBackModel) == null) {
        unawaited(_adoptRemotePlayback(jellyfinPlayer));
      }
    } catch (error, stack) {
      _log.severe('Failed to connect to "${device.name}"', error, stack);
      state = state.copyWith(status: CastConnectionStatus.error, error: error.toString());
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
          : {
              'Id': item.id,
              'ServerId': credentials.serverId,
              'Name': item.name,
              // Jellyfin expects PascalCase Type values ("Episode"), which is
              // the enum's JsonValue (`.value`) — `.name` gives the lowercase
              // Dart id.
              'Type': item.jellyType?.value,
              'MediaType': current!.isAudioPlayback ? 'Audio' : 'Video',
              'IsFolder': false,
            },
      startPosition: ref.read(videoPlayerProvider).lastState?.position ?? Duration.zero,
      // Without mediaSourceId the server ignores the track indexes entirely.
      mediaSourceId: current?.mediaStreams?.currentVersionStream?.id ?? item?.id,
      audioStreamIndex: current?.mediaStreams?.defaultAudioStreamIndex,
      subtitleStreamIndex: current?.mediaStreams?.defaultSubStreamIndex,
      image: _currentItemImage(),
    );
  }

  /// Builds a Chromecast-compatible stream URL for the current item by asking
  /// Jellyfin for a progressive transcode constrained to what the default
  /// receiver can decode (H.264 ≤ L4.1, ≤ 1080p, ≤ 8 Mbps, AAC stereo — see
  /// [chromecastProfile]). Returns null if there's no item or no transcode.
  Future<String?> _chromecastStreamUrl() async {
    final current = ref.read(playBackModel);
    if (current == null) return null;
    try {
      final response = await ref.read(jellyApiProvider).itemsItemIdPlaybackInfoPost(
            itemId: current.item.id,
            body: PlaybackInfoDto(
              userId: ref.read(userProvider)?.id,
              autoOpenLiveStream: true,
              enableTranscoding: true,
              enableDirectPlay: false,
              enableDirectStream: false,
              maxStreamingBitrate: chromecastMaxBitrate,
              deviceProfile: chromecastProfile,
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
              subtitleStreamIndex: hasSubtitle ? subtitleStreamIndex : null,
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

  Future<String?> _dlnaStreamUrl({
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? maxBitrate,
    Duration? startPosition,
  }) async {
    final current = ref.read(playBackModel);
    if (current == null) return null;

    final hasSubtitle = subtitleStreamIndex != null && subtitleStreamIndex >= 0;
    // A real quality cap (anything below the "original" sentinel) forces a
    // transcode; null/auto/original leave the file direct-playable.
    final cappedBitrate = (maxBitrate != null && maxBitrate < _dlnaOriginalBitrate) ? maxBitrate : null;
    // The renderer can't switch embedded tracks or burn subs itself, so any of
    // these selections requires a server-side transcode.
    final forceTranscode = hasSubtitle || audioStreamIndex != null || cappedBitrate != null;

    try {
      final response = await ref.read(jellyApiProvider).itemsItemIdPlaybackInfoPost(
            itemId: current.item.id,
            body: PlaybackInfoDto(
              userId: ref.read(userProvider)?.id,
              autoOpenLiveStream: true,
              enableTranscoding: true,
              // Begin the transcode at the resume position (1 tick = 100ns) so
              // it plays from the right place — a live transcode can't be
              // time-seeked afterwards. Ignored by a direct stream.
              startTimeTicks: forceTranscode && startPosition != null && startPosition > Duration.zero
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
              subtitleStreamIndex: hasSubtitle ? subtitleStreamIndex : null,
              // Burn the subtitle in — DLNA renderers can't render a separate
              // selected track reliably.
              alwaysBurnInSubtitleWhenTranscoding: hasSubtitle,
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
            'api_key': ref.read(userProvider)?.credentials.token,
            if (mediaSource.eTag != null) 'Tag': mediaSource.eTag,
            if (mediaSource.liveStreamId != null) 'LiveStreamId': mediaSource.liveStreamId,
          },
        );
        _log.info('DLNA direct stream resolved');
        return url;
      }

      final transcodingUrl = mediaSource.transcodingUrl;
      if (transcodingUrl == null) {
        _log.warning('No DLNA stream URL (no direct support, no transcode)');
        return null;
      }
      _log.info('DLNA transcode stream resolved (source not directly playable)');
      return buildServerUrl(ref, relativeUrl: transcodingUrl);
    } catch (error, stack) {
      _log.warning('Failed to resolve DLNA stream URL', error, stack);
      return null;
    }
  }

  /// Adopts a stream already running on the receiver: fetches the reported
  /// item, builds a playback model for it (without restarting the stream) and
  /// surfaces the bottom player bar so the app controls the existing cast.
  Future<void> _adoptRemotePlayback(JellyfinCastPlayer player) async {
    try {
      final itemId = await player.waitForNowPlayingItem(const Duration(seconds: 3));
      if (itemId == null) return;
      _log.info('Adopting in-progress cast of item $itemId');

      final response = await ref.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: itemId);
      final item = response.body;
      if (item == null) return;

      final model = await ref.read(playbackModelHelper).createPlaybackModel(null, item);
      if (model == null) return;

      ref.read(playBackModel.notifier).update((_) => model);
      // Future restarts (track/quality changes) must target the adopted item.
      player.updateItem(
        itemStub: {
          'Id': item.id,
          'ServerId': ref.read(userProvider)?.credentials.serverId,
          'Name': item.name,
          'Type': item.jellyType?.value,
          'MediaType': model.isAudioPlayback ? 'Audio' : 'Video',
          'IsFolder': false,
        },
        mediaSourceId: model.mediaStreams?.currentVersionStream?.id ?? item.id,
        audioStreamIndex: model.mediaStreams?.defaultAudioStreamIndex,
        subtitleStreamIndex: model.mediaStreams?.defaultSubStreamIndex,
        image: (item.images?.backDrop?.firstOrNull ?? item.images?.primary)?.imageProvider,
      );
      ref.read(mediaPlaybackProvider.notifier).update(
            (s) => s.copyWith(state: VideoPlayerState.minimized, buffering: false),
          );
    } catch (error, stack) {
      _log.warning('Failed to adopt remote playback', error, stack);
    }
  }

  /// Disconnects and resumes playback locally. Surfaces a `disconnecting` state
  /// because closing the remote session (e.g. UPnP Stop to a DLNA renderer) can
  /// take a moment — the picker shows progress instead of looking frozen.
  Future<void> disconnect() async {
    if (state.status == CastConnectionStatus.disconnecting) return;
    final wasAirPlay = _activeKind == RemoteDeviceKind.airplay;
    state = state.copyWith(status: CastConnectionStatus.disconnecting);
    _activeKind = null;
    await ref.read(videoPlayerProvider).stopCasting();
    // Tearing down our AVPlayer doesn't deselect the system AirPlay route, so
    // local playback would keep routing its audio to the Apple TV. Ask the
    // native side to release the route so playback returns to the device.
    if (wasAirPlay) await _endAirPlay();
    state = state.copyWith(status: CastConnectionStatus.idle, connectedDeviceName: null);
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
    _castSessionSub?.cancel();
    _castDevicesSub?.cancel();
    super.dispose();
  }
}

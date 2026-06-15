import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

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
import 'package:fladder/wrappers/players/airplay_video_player.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/web/cast_web.dart';
import 'package:fladder/wrappers/players/cast_player.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';
import 'package:fladder/wrappers/players/dlna_player.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_player.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

/// Platforms with a native Google Cast SDK wired up (`flutter_chrome_cast`).
/// macOS, Linux and Windows have no first-party Cast SDK; on those, only DLNA
/// targets are surfaced.
bool get _chromecastSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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

  // Latest discovered devices per source, merged into the published list by
  // [_publishDevices]. Chromecast devices arrive live via `devicesStream` (so
  // they appear without a manual reload); DLNA renderers are filled by a scan.
  List<GoogleCastDevice> _castDevices = const [];
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

    try {
      await _ensureCastInitialized();
      if (_chromecastSupported) {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      }

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

      _publishDevices();
      _log.info('Discovery complete: ${state.devices.length} device(s)');
    } catch (error, stack) {
      _log.severe('Discovery failed', error, stack);
      state = state.copyWith(error: error.toString());
    } finally {
      state = state.copyWith(discovering: false);
    }
  }

  /// Connects to [device] and hands the current playback off to it.
  Future<void> connect(RemoteDevice device) async {
    if (state.status == CastConnectionStatus.connecting || state.status == CastConnectionStatus.disconnecting) {
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
        // system AirPlay picker.
        player = await AirPlayVideoPlayer.connect(streamBuilder: _airplayStreamUrl, image: _currentItemImage());
      } else {
        player = await DlnaPlayer.connect(
          device.dlna!,
          streamBuilder: _dlnaStreamUrl,
          image: _currentItemImage(),
          castServerBase: ref.read(clientSettingsProvider).castServerUrl,
          onSessionEnded: _handleExternalCastEnd,
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
  /// every remote player so the casting UI looks the same).
  ImageProvider? _currentItemImage() {
    final item = ref.read(playBackModel)?.item;
    return (item?.images?.backDrop?.firstOrNull ?? item?.images?.primary)?.imageProvider;
  }

  /// Builds a DLNA-compatible stream URL for the current item: a Jellyfin
  /// progressive MP4 transcode constrained to what renderers decode (H.264/AAC
  /// — see [dlnaProfile]). Returns null if there's no item or no transcode.
  Future<String?> _dlnaStreamUrl() async {
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
              maxStreamingBitrate: dlnaMaxBitrate,
              deviceProfile: dlnaProfile,
            ),
          );
      final mediaSource = response.body?.mediaSources?.firstOrNull;
      final transcodingUrl = mediaSource?.transcodingUrl;
      if (transcodingUrl == null) {
        _log.warning('No transcoding URL returned for DLNA');
        return null;
      }
      final url = buildServerUrl(ref, relativeUrl: transcodingUrl);
      _log.info('DLNA transcode stream resolved');
      return url;
    } catch (error, stack) {
      _log.warning('Failed to resolve DLNA transcode URL', error, stack);
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
    state = state.copyWith(status: CastConnectionStatus.disconnecting);
    _activeKind = null;
    await ref.read(videoPlayerProvider).stopCasting();
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

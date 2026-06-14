import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/profiles/airplay_profile.dart';
import 'package:fladder/profiles/chromecast_profile.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/wrappers/players/airplay_video_player.dart';
import 'package:fladder/wrappers/players/base_player.dart';
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
/// OS). iOS only for now — macOS needs an AppKit route picker before it's
/// usable, even though the player itself would work there.
bool get _airPlaySupported => !kIsWeb && Platform.isIOS;

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

enum CastConnectionStatus { idle, connecting, connected, error }

class CastState {
  final List<RemoteDevice> devices;
  final bool discovering;
  final CastConnectionStatus status;
  final String? connectedDeviceName;
  final String? error;

  const CastState({
    this.devices = const [],
    this.discovering = false,
    this.status = CastConnectionStatus.idle,
    this.connectedDeviceName,
    this.error,
  });

  bool get isConnected => status == CastConnectionStatus.connected;

  CastState copyWith({
    List<RemoteDevice>? devices,
    bool? discovering,
    CastConnectionStatus? status,
    String? connectedDeviceName,
    String? error,
  }) {
    return CastState(
      devices: devices ?? this.devices,
      discovering: discovering ?? this.discovering,
      status: status ?? this.status,
      connectedDeviceName: connectedDeviceName ?? this.connectedDeviceName,
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
    } catch (error, stack) {
      _log.warning('Failed to initialize Cast SDK', error, stack);
    }
  }

  /// Scans the local network for both Chromecast receivers (native Cast SDK) and
  /// DLNA renderers (SSDP).
  Future<void> discover({Duration timeout = const Duration(seconds: 5)}) async {
    if (state.discovering) return;
    state = state.copyWith(discovering: true, error: null);
    try {
      await _ensureCastInitialized();
      if (_chromecastSupported) {
        await GoogleCastDiscoveryManager.instance.startDiscovery();
      }

      // DLNA scan blocks for [timeout]; the Cast SDK discovers asynchronously in
      // the background, so snapshot its devices after the same window.
      final dlnaDevices = _dlnaSupported ? await DlnaDiscovery.discover(timeout: timeout) : <DlnaRenderer>[];
      final castDevices = _chromecastSupported ? GoogleCastDiscoveryManager.instance.devices : <GoogleCastDevice>[];

      // Audio-only renderers (Sonos etc.) are useless targets for video; only
      // offer them while playing music.
      final audioPlayback = ref.read(playBackModel)?.isAudioPlayback ?? false;
      final dlnaTargets = dlnaDevices.where((renderer) => renderer.supportsVideo || audioPlayback).toList();
      if (dlnaTargets.length != dlnaDevices.length) {
        _log.info('Filtered ${dlnaDevices.length - dlnaTargets.length} audio-only DLNA renderer(s)');
      }

      final devices = <RemoteDevice>[
        // AirPlay has no network scan (the OS owns device discovery); offer it
        // as a fixed entry so the user can swap to the AVPlayer path and then
        // pick the Apple TV via the system picker.
        if (_airPlaySupported) RemoteDevice.airplay(),
        ...castDevices.map(RemoteDevice.chromecast),
        ...dlnaTargets.map(RemoteDevice.dlna),
      ];

      _log.info('Discovery complete: ${castDevices.length} Chromecast + ${dlnaDevices.length} DLNA = '
          '${devices.length} device(s)');
      state = state.copyWith(devices: devices, discovering: false);
    } catch (error, stack) {
      _log.severe('Discovery failed', error, stack);
      state = state.copyWith(discovering: false, error: error.toString());
    }
  }

  /// Connects to [device] and hands the current playback off to it.
  Future<void> connect(RemoteDevice device) async {
    if (state.status == CastConnectionStatus.connecting) return;
    _log.info('Connecting to ${device.kind.name} device "${device.name}"');
    state = state.copyWith(status: CastConnectionStatus.connecting, error: null);
    try {
      final BasePlayer player;
      JellyfinCastPlayer? jellyfinPlayer;
      if (device.kind == RemoteDeviceKind.chromecast) {
        if (_useJellyfinReceiver) {
          // Modern-only path: the Jellyfin receiver plays the item itself.
          final context = _buildJellyfinContext();
          if (context == null) throw StateError('No item or credentials available to cast');
          player = jellyfinPlayer = await JellyfinCastPlayer.connect(device.cast!, context);
        } else {
          // Universal path: hand the default receiver a Chromecast-friendly
          // progressive transcode, re-served over plain HTTP by the phone. The
          // URL is resolved lazily per item at load time (connect-before-play).
          player = await CastPlayer.connect(device.cast!, streamBuilder: _chromecastStreamUrl);
        }
      } else if (device.kind == RemoteDeviceKind.airplay) {
        // Swap to an AVPlayer-backed player fed a Jellyfin HLS transcode (built
        // lazily per item); the user then routes it to the Apple TV via the
        // system AirPlay picker.
        player = await AirPlayVideoPlayer.connect(streamBuilder: _airplayStreamUrl);
      } else {
        player = await DlnaPlayer.connect(
          device.dlna!,
          castServerBase: ref.read(clientSettingsProvider).castServerUrl,
        );
      }
      await ref.read(videoPlayerProvider).startCasting(player);
      _log.info('Now casting to "${device.name}"');
      state = state.copyWith(
        status: CastConnectionStatus.connected,
        connectedDeviceName: device.name,
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
      image: (item?.images?.backDrop?.firstOrNull ?? item?.images?.primary)?.imageProvider,
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
  /// [airplayProfile]). Returns null if there's no item or no transcode.
  Future<String?> _airplayStreamUrl() async {
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
              maxStreamingBitrate: airplayMaxBitrate,
              deviceProfile: airplayProfile,
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

  /// Disconnects and resumes playback locally.
  Future<void> disconnect() async {
    await ref.read(videoPlayerProvider).stopCasting();
    state = state.copyWith(status: CastConnectionStatus.idle, connectedDeviceName: null);
  }
}

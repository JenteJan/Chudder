import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/profiles/chromecast_profile.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast_player.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';
import 'package:fladder/wrappers/players/dlna_player.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

bool get _chromecastSupported => !kIsWeb && Platform.isAndroid;

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

  /// Initializes the native Cast SDK once (Android only).
  Future<void> _ensureCastInitialized() async {
    if (_castInitialized || !_chromecastSupported) return;
    try {
      await GoogleCastContext.instance.setSharedInstanceWithOptions(
        GoogleCastOptionsAndroid(appId: GoogleCastDiscoveryCriteria.kDefaultApplicationId),
      );
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
      final dlnaDevices = await DlnaDiscovery.discover(timeout: timeout);
      final castDevices = _chromecastSupported ? GoogleCastDiscoveryManager.instance.devices : <GoogleCastDevice>[];

      final devices = <RemoteDevice>[
        ...castDevices.map(RemoteDevice.chromecast),
        ...dlnaDevices.map(RemoteDevice.dlna),
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
      if (device.kind == RemoteDeviceKind.chromecast) {
        // The default Chromecast receiver can't decode many direct-play streams
        // (MKV/HEVC), so hand it a transcoded HLS/H.264 stream when we can build one.
        player = await CastPlayer.connect(device.cast!, mediaUrlOverride: await _chromecastStreamUrl());
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
    } catch (error, stack) {
      _log.severe('Failed to connect to "${device.name}"', error, stack);
      state = state.copyWith(status: CastConnectionStatus.error, error: error.toString());
    }
  }

  /// Builds a Chromecast-compatible stream URL for the current item by asking
  /// Jellyfin for a transcode constrained to what the receiver can decode
  /// (H.264 ≤ L4.1, ≤ 1080p, ≤ 20 Mbps, AAC stereo — see [chromecastProfile]).
  /// Returns null on failure, in which case the original stream is used.
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
        _log.warning('No transcoding URL returned for Chromecast; using original URL');
        return null;
      }
      _log.info('Chromecast will use a capped transcoded stream');
      return buildServerUrl(ref, relativeUrl: transcodingUrl);
    } catch (error, stack) {
      _log.warning('Failed to resolve Chromecast transcode URL', error, stack);
      return null;
    }
  }

  /// Disconnects and resumes playback locally.
  Future<void> disconnect() async {
    await ref.read(videoPlayerProvider).stopCasting();
    state = state.copyWith(status: CastConnectionStatus.idle, connectedDeviceName: null);
  }
}

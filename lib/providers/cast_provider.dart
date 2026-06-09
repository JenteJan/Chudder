import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_chrome_cast/flutter_chrome_cast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';
import 'package:fladder/wrappers/players/dlna_player.dart';
import 'package:fladder/wrappers/players/jellyfin_cast_player.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

bool get _chromecastSupported => !kIsWeb && Platform.isAndroid;

/// Jellyfin's registered Cast receiver app id (the one the official apps use).
/// It plays items natively — server-side PlaybackInfo/transcoding — so we just
/// hand it credentials + the item.
const _jellyfinReceiverAppId = 'F007D354';

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
        GoogleCastOptionsAndroid(appId: _jellyfinReceiverAppId),
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
        // Cast to the Jellyfin receiver, which plays the item itself.
        final context = _buildJellyfinContext();
        if (context == null) throw StateError('No item or credentials available to cast');
        player = await JellyfinCastPlayer.connect(device.cast!, context);
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

  /// Gathers the credentials + current item the Jellyfin receiver needs.
  JellyfinCastContext? _buildJellyfinContext() {
    final current = ref.read(playBackModel);
    final credentials = ref.read(userProvider)?.credentials;
    final userId = ref.read(userProvider)?.id;
    if (current == null || credentials == null || userId == null) return null;

    final item = current.item;
    return JellyfinCastContext(
      serverAddress: credentials.url,
      accessToken: credentials.token,
      userId: userId,
      deviceId: credentials.deviceId,
      serverId: credentials.serverId,
      serverVersion: '',
      itemStub: {
        'Id': item.id,
        'ServerId': credentials.serverId,
        'Name': item.name,
        'Type': item.jellyType?.name,
        'MediaType': current.isAudioPlayback ? 'Audio' : 'Video',
        'IsFolder': false,
      },
      startPosition: ref.read(videoPlayerProvider).lastState?.position ?? Duration.zero,
    );
  }

  /// Disconnects and resumes playback locally.
  Future<void> disconnect() async {
    await ref.read(videoPlayerProvider).stopCasting();
    state = state.copyWith(status: CastConnectionStatus.idle, connectedDeviceName: null);
  }
}

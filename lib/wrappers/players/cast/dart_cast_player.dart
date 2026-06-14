import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/cast/castv2/castv2_client.dart';
import 'package:fladder/wrappers/players/cast/castv2/cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/dart_cast_discovery.dart';
import 'package:fladder/wrappers/players/local_media_proxy.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.dartcast');

/// A [BasePlayer] that casts to a Chromecast from desktop (macOS/Windows/Linux)
/// using the pure-Dart [Castv2Client] — no `flutter_chrome_cast`, which Google
/// only ships for android/ios.
///
/// Uses the **default media receiver** (`CC1AD845`): the phone-built progressive
/// transcode (see `chromecastProfile`) is re-served by the on-device proxy and
/// driven via the Cast media namespace (LOAD/PLAY/PAUSE/SEEK). This mirrors the
/// mobile [CastPlayer], just over a Dart transport instead of the native SDK.
/// (The Jellyfin custom receiver over Dart is a follow-up.)
class DartCastPlayer extends BasePlayer implements RemotePlayer {
  DartCastPlayer._(this._target, this._client, this._streamBuilder, this._useProxy);

  static const _defaultReceiverAppId = 'CC1AD845';

  final DartCastTarget _target;
  final Castv2Client _client;

  /// Builds the cast transcode URL for the *current* item, on demand (lazy —
  /// connect-before-play + item switching), uniform with the other paths.
  final Future<String?> Function() _streamBuilder;
  final bool _useProxy;

  final LocalMediaProxy _proxy = LocalMediaProxy();
  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  StreamSubscription? _mediaSub;
  Timer? _statusPoll;
  String? _appTransportId;
  int? _mediaSessionId;

  @override
  String get deviceName => _target.name;

  // Default receiver just pulls a stream; the phone stays the session owner.
  @override
  bool get reportsOwnProgress => false;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  static Future<DartCastPlayer> connect(
    DartCastTarget target, {
    required Future<String?> Function() streamBuilder,
    bool useProxy = true,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _log.info('Connecting to "${target.name}" @ ${target.host}:${target.port}');
    final socket = await TlsCastSocket.connect(target.host, target.port, timeout: timeout);
    final client = Castv2Client(socket)..start();
    try {
      final status = await client.launch(_defaultReceiverAppId, timeout: timeout);
      final transport = status.transportFor(_defaultReceiverAppId);
      if (transport == null) {
        throw StateError('"${target.name}" did not launch the media receiver');
      }
      final player = DartCastPlayer._(target, client, streamBuilder, useProxy);
      player._appTransportId = transport;
      player._listen();
      _log.info('Connected to "${target.name}"');
      return player;
    } catch (error) {
      await client.close();
      rethrow;
    }
  }

  void _listen() {
    _mediaSub = _client.messages
        .where((m) => m.namespace == CastProtocol.media && m.payloadUtf8 != null)
        .listen((message) {
      final status = MediaStatus.parse(message.payloadUtf8!);
      if (status == null) return;
      if (status.mediaSessionId != null) _mediaSessionId = status.mediaSessionId;
      lastState = lastState.update(
        playing: status.isPlaying,
        buffering: status.playerState == 'BUFFERING',
        position: status.currentTime,
      );
      _stateController.add(lastState);
    });
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    final resolved = await _streamBuilder();
    final transport = _appTransportId;
    if (resolved == null || transport == null) {
      _log.warning('No Chromecast stream available for the current item; nothing to load.');
      lastState = lastState.update(buffering: false, playing: false);
      _stateController.add(lastState);
      return;
    }

    var mediaUrl = resolved;
    if (_useProxy) {
      final served = await _proxy.start(resolved);
      if (served != null) {
        mediaUrl = served;
        _log.info('Casting via on-device proxy');
      } else {
        _log.warning('Proxy unavailable — falling back to the direct (HTTPS) stream URL');
      }
    }

    final contentType = mediaUrl.contains('.m3u8') ? 'application/vnd.apple.mpegurl' : 'video/mp4';
    _log.info('LOAD on "${_target.name}" (type $contentType)');
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    _client.sendMedia(
      transport,
      CastProtocol.load(
        contentId: mediaUrl,
        contentType: contentType,
        requestId: _client.nextRequestId(),
        autoplay: play,
      ),
    );
    _startStatusPoll();
  }

  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 2), (_) {
      final transport = _appTransportId;
      final session = _mediaSessionId;
      if (transport != null && session != null) {
        _client.sendMedia(transport, CastProtocol.getMediaStatus(session, _client.nextRequestId()));
      }
    });
  }

  bool get _ready => _appTransportId != null && _mediaSessionId != null;

  @override
  Future<void> play() async {
    if (_ready) _client.sendMedia(_appTransportId!, CastProtocol.play(_mediaSessionId!, _client.nextRequestId()));
  }

  @override
  Future<void> pause() async {
    if (_ready) _client.sendMedia(_appTransportId!, CastProtocol.pause(_mediaSessionId!, _client.nextRequestId()));
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) async {
    if (_ready) {
      _client.sendMedia(_appTransportId!, CastProtocol.seek(_mediaSessionId!, position, _client.nextRequestId()));
      lastState = lastState.update(position: position);
      _stateController.add(lastState);
    }
  }

  // BasePlayer volume is 0–100; the Cast device volume command wants 0–1.
  @override
  Future<void> setVolume(double volume) async => _client.setVolume((volume / 100).clamp(0.0, 1.0));

  // Playback rate isn't supported on this path.
  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<void> stop() async {
    _statusPoll?.cancel();
    if (_ready) {
      _client.sendMedia(_appTransportId!, CastProtocol.mediaCommand('STOP', _mediaSessionId!, _client.nextRequestId()));
    }
  }

  // Switching tracks needs a fresh transcode (not wired v1) — mirror DlnaPlayer.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => _RemotePlaybackPlaceholder(key: key, deviceName: deviceName);

  @override
  Future<void> dispose() async {
    _statusPoll?.cancel();
    await _mediaSub?.cancel();
    await _proxy.stop();
    await _client.close();
    if (!_stateController.isClosed) await _stateController.close();
  }
}

class _RemotePlaybackPlaceholder extends StatelessWidget {
  const _RemotePlaybackPlaceholder({super.key, required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cast_connected, size: 64, color: Colors.white70),
            const SizedBox(height: 16),
            Text(
              'Playing on $deviceName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

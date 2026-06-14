import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/screens/video_player/components/casting_placeholder.dart';
import 'package:fladder/wrappers/players/base_player.dart';
import 'package:fladder/wrappers/players/dlna_discovery.dart';
import 'package:fladder/wrappers/players/local_media_proxy.dart';
import 'package:fladder/wrappers/players/player_states.dart';
import 'package:fladder/wrappers/players/remote_device.dart';

const _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';
const _renderingControl = 'urn:schemas-upnp-org:service:RenderingControl:1';

final _log = Logger('Cast.dlna');

/// A [BasePlayer] that drives a DLNA/UPnP MediaRenderer (LG/Samsung TVs, Sonos,
/// generic DLNA "play to" targets) via AVTransport SOAP actions. Playback happens
/// on the remote device; this class sends commands and polls the renderer's
/// transport/position state back into a [PlayerState] stream.
class DlnaPlayer extends BasePlayer implements RemotePlayer {
  DlnaPlayer(this.renderer, this._streamBuilder, {this.image, this.castServerBase, this.onSessionEnded});

  final DlnaRenderer renderer;

  /// Item backdrop/poster shown behind the casting placeholder (same as the
  /// Chromecast path).
  final ImageProvider? image;

  /// Builds a DLNA-safe transcode URL (see [dlnaProfile]) for the *current*
  /// item, on demand at load time. Replaces the app's local stream URL, which
  /// the renderer often can't play (e.g. a direct-play MKV → UPnP 701). Lazy so
  /// connect-before-play and item switching work — uniform with the other paths.
  final Future<String?> Function() _streamBuilder;

  /// Optional power-user override: a plain-http, LAN-reachable Jellyfin base URL
  /// the renderer can fetch directly. When unset, the stream is proxied through
  /// the phone instead (the zero-config default).
  final String? castServerBase;

  /// Called when the renderer's session ends outside the app — it stopped, was
  /// taken over by another source, or went unreachable (turned off). Lets the
  /// app restore local playback instead of looking stuck "casting".
  final VoidCallback? onSessionEnded;

  @override
  String get deviceName => renderer.name;

  // DLNA renderers just pull a stream; the phone stays the session owner and
  // must keep reporting progress for watched-state to update.
  @override
  bool get reportsOwnProgress => false;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  final LocalMediaProxy _proxy = LocalMediaProxy();
  Timer? _statusPoll;

  /// A resume position to apply once the renderer reports it's actually playing.
  Duration? _pendingSeek;

  /// Until this time, ignore polled play-state/position so a just-issued local
  /// command (play/pause/seek) isn't immediately undone by a lagging poll. After
  /// it expires the renderer's reported state is authoritative again, so changes
  /// made on the TV itself are reflected back.
  DateTime? _commandGuardUntil;

  /// True once the renderer has reported active playback — used to tell an
  /// external stop/takeover apart from never having started.
  bool _wasActive = false;
  int _consecutivePollFailures = 0;
  bool _endedSignaled = false;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  /// Connects by issuing a no-op transport query so failures surface immediately.
  static Future<DlnaPlayer> connect(
    DlnaRenderer renderer, {
    required Future<String?> Function() streamBuilder,
    ImageProvider? image,
    String? castServerBase,
    VoidCallback? onSessionEnded,
  }) async {
    _log.info('Connecting to DLNA renderer "${renderer.name}" @ ${renderer.avTransportControlUrl}');
    final player = DlnaPlayer(renderer, streamBuilder,
        image: image, castServerBase: castServerBase, onSessionEnded: onSessionEnded);
    final ok = await player._soap(renderer.avTransportControlUrl, _avTransport, 'GetTransportInfo',
        '<InstanceID>0</InstanceID>');
    if (ok == null) {
      await player.dispose();
      throw StateError('Could not reach ${renderer.name}');
    }
    _log.info('Connected to "${renderer.name}"');
    return player;
  }

  /// Resolves the URL the renderer should fetch: the configured LAN base if set,
  /// otherwise a local proxy URL on the phone so the renderer never has to deal
  /// with the app's HTTPS Jellyfin endpoint.
  Future<String> _resolveMediaUrl(String url) async {
    final base = castServerBase;
    if (base != null && base.isNotEmpty) {
      final original = Uri.tryParse(url);
      final baseUri = Uri.tryParse(base);
      if (original != null && baseUri != null && baseUri.host.isNotEmpty) {
        final rewritten = original.replace(scheme: baseUri.scheme, host: baseUri.host, port: baseUri.port).toString();
        _log.info('Using configured cast server base ${baseUri.scheme}://${baseUri.host}:${baseUri.port}');
        return rewritten;
      }
    }
    final proxied = await _proxy.start(url);
    if (proxied != null) return proxied;
    _log.warning('Proxy unavailable — falling back to original URL (renderer may not fetch it)');
    return url;
  }

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // Ignore the app's local URL; play a DLNA-safe transcode for the current
    // item (resolved lazily). A raw container like MKV makes renderers reject
    // the SetAVTransportURI with UPnP 701.
    final resolved = await _streamBuilder();
    if (resolved == null) {
      _log.warning('No DLNA stream available for the current item; nothing to load.');
      lastState = lastState.update(buffering: false, playing: false);
      _stateController.add(lastState);
      return;
    }
    _log.info('loadVideo on "${renderer.name}" (start ${startPosition.inSeconds}s, play=$play)');
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    final mediaUrl = await _resolveMediaUrl(resolved);
    final mime = _proxy.isRunning ? _proxy.contentType : _mimeFor(mediaUrl);
    _log.fine('Renderer URL: $mediaUrl (mime $mime)');
    final metadata = _didlMetadata(mediaUrl, mime);
    await _soap(
      renderer.avTransportControlUrl,
      _avTransport,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
          '<CurrentURI>${_escape(mediaUrl)}</CurrentURI>'
          '<CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>',
    );

    if (play) await this.play();

    // Apply the resume position once the renderer reports PLAYING — seeking
    // before the stream is prepared is rejected (701/710).
    _pendingSeek = startPosition > Duration.zero ? startPosition : null;

    _startStatusPoll();
  }

  @override
  Future<void> play() async {
    // Reflect the action immediately so the UI is responsive, then guard against
    // the poll snapping it back before the renderer reports the transition.
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _commandGuardUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    await _soap(renderer.avTransportControlUrl, _avTransport, 'Play', '<InstanceID>0</InstanceID><Speed>1</Speed>');
  }

  @override
  Future<void> pause() async {
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _commandGuardUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    await _soap(renderer.avTransportControlUrl, _avTransport, 'Pause', '<InstanceID>0</InstanceID>');
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  @override
  Future<void> stop() async {
    _statusPoll?.cancel();
    await _soap(renderer.avTransportControlUrl, _avTransport, 'Stop', '<InstanceID>0</InstanceID>');
  }

  @override
  Future<void> seek(Duration position) async {
    if (await _trySeek(position)) {
      lastState = lastState.update(position: position);
      _stateController.add(lastState);
      // Trust the seeked position briefly so polling doesn't snap the UI back
      // while the renderer catches up.
      _commandGuardUntil = DateTime.now().add(const Duration(seconds: 3));
    }
  }

  /// Renderers disagree on seek units — try REL_TIME (absolute position from the
  /// track start) first, then ABS_TIME as a fallback.
  Future<bool> _trySeek(Duration position) async {
    final target = _formatTime(position);
    for (final unit in const ['REL_TIME', 'ABS_TIME']) {
      final result = await _soap(
        renderer.avTransportControlUrl,
        _avTransport,
        'Seek',
        '<InstanceID>0</InstanceID><Unit>$unit</Unit><Target>$target</Target>',
      );
      if (result != null) {
        _log.info('Seeked to $target via $unit on "${renderer.name}"');
        return true;
      }
    }
    _log.warning('Seek to $target rejected by "${renderer.name}"');
    return false;
  }

  @override
  Future<void> setVolume(double volume) async {
    final control = renderer.renderingControlUrl;
    if (control == null) return;
    final clamped = volume.clamp(0, 100).round();
    await _soap(
      control,
      _renderingControl,
      'SetVolume',
      '<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>$clamped</DesiredVolume>',
    );
  }

  // The renderer owns playback rate; leave as a no-op for v1.
  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => model?.index ?? 0;

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit) => CastingPlaceholder(key: key, deviceName: deviceName, image: image);

  @override
  Future<void> dispose() async {
    _statusPoll?.cancel();
    // Close the renderer's session so the TV stops and returns to its home
    // screen instead of holding the (now orphaned) stream.
    try {
      await _soap(renderer.avTransportControlUrl, _avTransport, 'Stop', '<InstanceID>0</InstanceID>');
    } catch (_) {}
    await _proxy.stop();
    try {
      _http.close(force: true);
    } catch (_) {}
    if (!_stateController.isClosed) await _stateController.close();
  }

  /// Fires [onSessionEnded] once when the renderer's session ends outside the
  /// app (external stop/takeover, or the device going unreachable).
  void _signalEnded(String why) {
    if (_endedSignaled) return;
    _endedSignaled = true;
    _log.info('DLNA session ended externally ($why)');
    _statusPoll?.cancel();
    onSessionEnded?.call();
  }

  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 1), (_) => _pollStatus());
  }

  Future<void> _pollStatus() async {
    final transport = await _soap(
        renderer.avTransportControlUrl, _avTransport, 'GetTransportInfo', '<InstanceID>0</InstanceID>');

    // The renderer went unreachable (e.g. turned off): a few failures in a row
    // while a stream was active means the session is gone.
    if (transport == null) {
      _consecutivePollFailures++;
      if (_wasActive && _consecutivePollFailures >= 3) {
        _signalEnded('renderer unreachable');
      }
      return;
    }
    _consecutivePollFailures = 0;

    final positionInfo = await _soap(
        renderer.avTransportControlUrl, _avTransport, 'GetPositionInfo', '<InstanceID>0</InstanceID>');

    bool? playing;
    bool? buffering;
    final transportState = _tag(transport, 'CurrentTransportState');
    switch (transportState) {
      case 'PLAYING':
        playing = true;
        buffering = false;
        _wasActive = true;
        break;
      case 'PAUSED_PLAYBACK':
        playing = false;
        buffering = false;
        _wasActive = true;
        break;
      case 'TRANSITIONING':
        buffering = true;
        _wasActive = true;
        break;
      case 'STOPPED':
      case 'NO_MEDIA_PRESENT':
        playing = false;
        // The renderer stopped on its own (finished, stopped from the TV, or
        // taken over by another source) — hand playback back to the phone.
        if (_wasActive) {
          _signalEnded('renderer reported $transportState');
          return;
        }
        break;
    }

    // Apply a pending resume seek as soon as the renderer is playing.
    if (transportState == 'PLAYING' && _pendingSeek != null) {
      final pending = _pendingSeek!;
      _pendingSeek = null;
      await seek(pending);
      return;
    }

    Duration? position;
    Duration? duration;
    if (positionInfo != null) {
      position = _parseTime(_tag(positionInfo, 'RelTime'));
      duration = _parseTime(_tag(positionInfo, 'TrackDuration'));
    }

    // While a just-issued local command settles, trust the optimistic state;
    // once it expires the renderer is authoritative again, so play/seek done on
    // the TV itself is reflected back here.
    final guard = _commandGuardUntil;
    if (guard != null && DateTime.now().isBefore(guard)) {
      position = null;
      playing = null;
    }

    lastState = lastState.update(
      playing: playing,
      buffering: buffering,
      position: position,
      duration: duration,
    );
    _stateController.add(lastState);
  }

  Future<String?> _soap(Uri controlUrl, String serviceType, String action, String innerXml) async {
    try {
      final envelope = '<?xml version="1.0" encoding="utf-8"?>'
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
          's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
          '<s:Body><u:$action xmlns:u="$serviceType">$innerXml</u:$action></s:Body></s:Envelope>';

      final request = await _http.postUrl(controlUrl);
      request.headers.set(HttpHeaders.contentTypeHeader, 'text/xml; charset="utf-8"');
      request.headers.set('SOAPACTION', '"$serviceType#$action"');
      request.add(utf8.encode(envelope));
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode >= 400) {
        final errorCode = _tag(text, 'errorCode');
        final errorDescription = _tag(text, 'errorDescription');
        _log.warning('$action failed (${response.statusCode}) on "${renderer.name}": '
            'UPnP error ${errorCode ?? '?'} ${errorDescription ?? ''}'.trim());
        return null;
      }
      return text;
    } catch (error) {
      _log.warning('$action request to "${renderer.name}" threw: $error');
      return null;
    }
  }

  static String _didlMetadata(String url, String mime) {
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>Fladder</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:$dlnaOrgContentFeatures">${_escape(url)}</res>'
        '</item></DIDL-Lite>';
  }

  /// Best-effort MIME from the Jellyfin stream URL's `container=` param (or HLS).
  static String _mimeFor(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8')) return 'application/vnd.apple.mpegurl';
    final container = Uri.tryParse(url)?.queryParameters['container']?.toLowerCase();
    return switch (container) {
      'mp4' || 'm4v' => 'video/mp4',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'ts' => 'video/mp2t',
      'avi' => 'video/x-msvideo',
      _ => 'video/mp4',
    };
  }

  static String _escape(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String? _tag(String xml, String tag) {
    final match = RegExp('<$tag>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return match?.group(1)?.trim();
  }

  static String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static Duration? _parseTime(String? value) {
    if (value == null || value.isEmpty || value == 'NOT_IMPLEMENTED') return null;
    final parts = value.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2].split('.').first);
    if (h == null || m == null || s == null) return null;
    return Duration(hours: h, minutes: m, seconds: s);
  }
}

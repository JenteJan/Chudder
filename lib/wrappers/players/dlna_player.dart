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

/// Builds the URL the renderer should fetch for the *current* item. Mirrors the
/// AirPlay builder: with no track overrides and no bitrate cap it resolves a
/// direct stream (the original file, which capable TVs play best); selecting a
/// subtitle/audio track or a lower quality switches it to a transcode (subtitle
/// burned in) so DLNA renderers — which can't switch embedded tracks themselves
/// — still honour the choice.
typedef DlnaStreamBuilder = Future<String?> Function({
  int? audioStreamIndex,
  int? subtitleStreamIndex,
  int? maxBitrate,
  Duration? startPosition,
});

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

  /// Builds the URL for the *current* item, on demand at load time (see
  /// [DlnaStreamBuilder]). Lazy so connect-before-play and item/track switching
  /// work — uniform with the other cast paths.
  final DlnaStreamBuilder _streamBuilder;

  // Track/quality overrides; changing one rebuilds the stream and reloads (the
  // renderer can't switch tracks itself). Null = use the source defaults, which
  // lets the original file direct-play.
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;
  int? _maxBitrate;

  /// True when the active selection forces a server-side transcode (a burned-in
  /// subtitle, an audio override, or a real quality cap). A transcode stream is
  /// generated from the requested start position and its renderer-reported
  /// duration is unreliable, so the timeline is handled differently from a
  /// direct stream (a complete, fully-seekable file).
  bool get _isTranscoding =>
      (_subtitleStreamIndex != null && _subtitleStreamIndex! >= 0) ||
      _audioStreamIndex != null ||
      (_maxBitrate != null && _maxBitrate! < 1000000000);

  /// Media position the current stream begins at. For a transcode the server
  /// starts encoding here, so the renderer's RelTime is relative to it and we
  /// add it back to report the true position. Zero for a direct stream (the
  /// whole file, where RelTime is already absolute).
  Duration _streamStartOffset = Duration.zero;

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

  /// Set while [loadVideo] is mid-flight (track/quality reload). The reload
  /// sends its own Stop, which the poll would otherwise read as an external
  /// stop and tear the whole session down — so we suppress that during a load.
  bool _loading = false;

  /// Whether a URI has ever been set on the renderer this session — Play
  /// before that only produces UPnP 701 errors.
  bool _hasMedia = false;

  /// Guards the resume-refused → rebuild-stream recovery from recursing
  /// (loadVideo calls play() again).
  bool _resumeRebuildInProgress = false;

  /// The item's real runtime, for transcodes: the renderer reports a bogus
  /// growing TrackDuration for a live transcode, and without a duration the
  /// UI has no end time and looks stuck loading.
  Duration? Function()? _knownDuration;

  /// Points the next load at the item's selected subtitle (called by the
  /// wrapper before loadVideo when the played item changes — the connect-time
  /// selection belongs to whatever was playing then, or to nothing at all
  /// when the cast started idle).
  void updateTrackSelection({int? subtitleStreamIndex}) {
    _subtitleStreamIndex = subtitleStreamIndex;
  }

  /// Resolves a text subtitle stream to an SRT URL on the Jellyfin server, or
  /// null when the selected track can't be served as a sidecar (image subs).
  /// With a sidecar the video direct-plays and the TV renders the subs itself
  /// (CaptionInfoEx) — instead of a burned-in live transcode webOS often
  /// refuses to start.
  Future<String?> Function(int subtitleStreamIndex)? _subtitleSidecarBuilder;

  /// Set in [dispose]. `loadVideo` awaits seconds of SOAP calls/retries, so the
  /// player can be torn down while a load is in flight; without this guard the
  /// trailing `_startStatusPoll()` spins a timer on a closed HTTP client and
  /// spams "Client is closed" forever.
  bool _disposed = false;

  /// Bumped on every [loadVideo]. A poll started for an earlier stream can still
  /// be awaiting its SOAP response when a reload swaps the stream out; comparing
  /// the generation lets that stale poll bail instead of, say, reading the old
  /// stream's STOPPED state and tearing the whole session down.
  int _loadGeneration = 0;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  /// Connects by issuing a no-op transport query so failures surface immediately.
  static Future<DlnaPlayer> connect(
    DlnaRenderer renderer, {
    required DlnaStreamBuilder streamBuilder,
    ImageProvider? image,
    String? castServerBase,
    VoidCallback? onSessionEnded,
    int? initialAudioStreamIndex,
    int? initialSubtitleStreamIndex,
    int? initialMaxBitrate,
    Duration? Function()? knownDuration,
    Future<String?> Function(int subtitleStreamIndex)? subtitleSidecarBuilder,
  }) async {
    _log.info('Connecting to DLNA renderer "${renderer.name}" @ ${renderer.avTransportControlUrl}');
    final player = DlnaPlayer(renderer, streamBuilder,
        image: image, castServerBase: castServerBase, onSessionEnded: onSessionEnded)
      .._knownDuration = knownDuration
      .._subtitleSidecarBuilder = subtitleSidecarBuilder
      // Start with the client's current track/quality selection so the first
      // stream matches what was playing locally.
      .._audioStreamIndex = initialAudioStreamIndex
      .._subtitleStreamIndex = initialSubtitleStreamIndex
      .._maxBitrate = initialMaxBitrate;
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
    final proxied = await _proxy.start(url, rendererHost: renderer.avTransportControlUrl.host);
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
    // Ignore the app's local URL; resolve the renderer's URL lazily for the
    // current item with the active track/quality overrides applied.
    final resolved = await _streamBuilder(
      audioStreamIndex: _audioStreamIndex,
      subtitleStreamIndex: _subtitleStreamIndex,
      maxBitrate: _maxBitrate,
      startPosition: startPosition,
    );
    if (resolved == null) {
      _log.warning('No DLNA stream available for the current item; nothing to load.');
      lastState = lastState.update(buffering: false, playing: false);
      _stateController.add(lastState);
      return;
    }
    _log.info('loadVideo on "${renderer.name}" (start ${startPosition.inSeconds}s, play=$play)');
    // Suspend polling and clear the "was playing" flag for the duration of the
    // (re)load: the Stop we send below makes the renderer report STOPPED, which
    // the poll would otherwise mistake for an external stop and tear down the
    // whole cast (dropping playback back to the phone).
    _loading = true;
    _loadGeneration++;
    _statusPoll?.cancel();
    _wasActive = false;
    lastState = lastState.update(buffering: true, playing: play, position: startPosition);
    _stateController.add(lastState);

    final mediaUrl = await _resolveMediaUrl(resolved);
    final mime = _proxy.isRunning ? _proxy.contentType : _mimeFor(mediaUrl);
    _log.fine('Renderer URL: $mediaUrl (mime $mime)');

    // Text subtitle selected: hand the TV an SRT sidecar next to the stream
    // (CaptionInfoEx) so the video can direct-play instead of burning subs
    // into a live transcode.
    String? subtitleUrl;
    _proxy.subtitleUpstreamUrl = null; // never carry the previous item's subs
    final subIndex = _subtitleStreamIndex;
    if (subIndex != null && subIndex >= 0 && _subtitleSidecarBuilder != null) {
      final upstreamSub = await _subtitleSidecarBuilder!(subIndex);
      if (upstreamSub != null) {
        subtitleUrl = _resolveSubtitleUrl(upstreamSub, mediaUrl);
        if (subtitleUrl != null) _log.info('Subtitle sidecar for renderer: $subtitleUrl');
      }
    }
    final metadata = _didlMetadata(mediaUrl, mime, subtitleUrl: subtitleUrl);

    // Stop before setting a new URI. When this is a reload (track/quality change
    // while already playing), the renderer is in the PLAYING state and rejects
    // SetAVTransportURI with UPnP 701 "Transition not available" — it only
    // accepts a new URI from STOPPED. Best-effort: on a fresh, idle connect the
    // Stop is a harmless no-op.
    await _soap(renderer.avTransportControlUrl, _avTransport, 'Stop', '<InstanceID>0</InstanceID>');

    await _soap(
      renderer.avTransportControlUrl,
      _avTransport,
      'SetAVTransportURI',
      '<InstanceID>0</InstanceID>'
          '<CurrentURI>${_escape(mediaUrl)}</CurrentURI>'
          '<CurrentURIMetaData>${_escape(metadata)}</CurrentURIMetaData>',
    );
    _hasMedia = true;

    if (play) await this.play();

    _loading = false;
    // The player may have been torn down during the awaits above (target switch
    // / disconnect) — don't start a poll on a closed client.
    if (_disposed) return;

    if (_isTranscoding) {
      // The transcode is generated starting at this position, so the renderer
      // plays from its start — no UPnP seek (those fail on a non-seekable live
      // transcode: 710/711). RelTime is relative to here; the poll adds it back.
      _streamStartOffset = startPosition;
      _pendingSeek = null;
    } else {
      // Direct stream is the whole file: seek to the resume point once the
      // renderer reports PLAYING (seeking before it's prepared is rejected).
      _streamStartOffset = Duration.zero;
      _pendingSeek = startPosition > Duration.zero ? startPosition : null;
    }

    _startStatusPoll();
  }

  @override
  Future<void> play() async {
    // Nothing was ever loaded (stream resolution failed) — a Play would only
    // draw UPnP 701s from the renderer, and the retry loop would hammer it.
    if (!_hasMedia) {
      _log.warning('play() with no media loaded on "${renderer.name}" — ignoring');
      return;
    }
    // Reflect the action immediately so the UI is responsive, then guard against
    // the poll snapping it back before the renderer reports the transition.
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _commandGuardUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    // A freshly-set live transcode needs a moment to start producing bytes
    // before the renderer will leave the transitioning state, so retry Play a
    // few times. A complete file accepts the first attempt instantly.
    var resumed = false;
    const innerXml = '<InstanceID>0</InstanceID><Speed>1</Speed>';
    for (var attempt = 1; attempt <= 4 && !_disposed; attempt++) {
      final result = await _soap(renderer.avTransportControlUrl, _avTransport, 'Play', innerXml);
      if (result != null) {
        resumed = true;
        break;
      }
      if (attempt < 4) await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
    }

    // A live transcode that sat paused often can't restart at all — webOS
    // answers 501/701 forever because the stream it half-buffered is gone.
    // Rebuild the stream at the paused position instead (a pending paused-seek
    // wins as the resume point).
    if (!resumed && _isTranscoding && !_disposed && !_resumeRebuildInProgress) {
      final resumeAt = _pendingSeek ?? lastState.position;
      _pendingSeek = null;
      _log.info('Resume refused on live transcode — rebuilding stream at ${resumeAt.inSeconds}s');
      _resumeRebuildInProgress = true;
      try {
        await loadVideo('', true, startPosition: resumeAt);
      } finally {
        _resumeRebuildInProgress = false;
      }
      return;
    }

    // A seek parked while paused lands as soon as playback resumes; if the
    // renderer still refuses (not fully in PLAYING yet), the status poll
    // retries it on the next PLAYING report.
    final pending = _pendingSeek;
    if (pending != null && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (await _trySeek(pending)) {
        _pendingSeek = null;
        _commandGuardUntil = DateTime.now().add(const Duration(seconds: 3));
      }
    }
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
    // Renderers refuse Seek while paused (LG answers 501): park it as the
    // pending seek — the status poll fires it the moment the renderer reports
    // PLAYING again — and show the target position optimistically meanwhile.
    if (!lastState.playing) {
      _log.info('Seek to ${position.inSeconds}s while paused — deferring until resume');
      _pendingSeek = position;
      lastState = lastState.update(position: position);
      _stateController.add(lastState);
      return;
    }
    var seeked = await _trySeek(position);
    // Renderers also reject seeks while still transitioning from a previous
    // seek/load (LG answers 501) — one settle-and-retry makes back-to-back
    // scrubs land instead of silently dropping.
    if (!seeked && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      seeked = await _trySeek(position);
    }
    if (seeked) {
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

  // The renderer doesn't push volume reports over the status poll we run.
  @override
  int? get remoteVolumeLevel => null;

  // The renderer owns playback rate; leave as a no-op for v1.
  @override
  bool get supportsPlaybackRate => false;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  // Switching a track rebuilds the stream with the new track baked in (the
  // renderer can't switch embedded tracks over UPnP) and reloads at the current
  // position — same model as the AirPlay player.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _audioStreamIndex ?? -1;
    _audioStreamIndex = model.index;
    await _reload();
    return model.index;
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _subtitleStreamIndex ?? -1;
    _subtitleStreamIndex = model.index;
    await _reload();
    return model.index;
  }

  /// Applies a quality cap from the in-player quality control. A null/very-high
  /// cap keeps the original file direct-playing; a real cap forces a transcode
  /// at that bitrate (see [_streamBuilder]).
  Future<void> setMaxBitrate(int? maxBitrate) async {
    if (_maxBitrate == maxBitrate) return;
    _maxBitrate = maxBitrate;
    await _reload();
  }

  /// Rebuilds the stream (current track/quality selection) and resumes at the
  /// current position.
  Future<void> _reload() async => loadVideo('', lastState.playing, startPosition: lastState.position);

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) => CastingPlaceholder(key: key, deviceName: deviceName, image: image);

  @override
  Future<void> dispose() async {
    _disposed = true;
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
    // A reload is in flight (it sends its own Stop) or the player is gone —
    // either way the renderer's reported state isn't meaningful right now.
    if (_loading || _disposed) return;
    final generation = _loadGeneration;

    final transport = await _soap(
        renderer.avTransportControlUrl, _avTransport, 'GetTransportInfo', '<InstanceID>0</InstanceID>');

    // A reload started (and possibly finished) while we awaited the response —
    // this status belongs to a stream that's no longer current; discard it.
    if (_loading || _disposed || generation != _loadGeneration) return;

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
    if (_loading || _disposed || generation != _loadGeneration) return;

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
      // The renderer is playing again — mark it so before seeking, else the
      // paused-seek deferral in seek() would just re-park the position.
      lastState = lastState.update(playing: true);
      await seek(pending);
      return;
    }

    Duration? position;
    Duration? duration;
    if (positionInfo != null) {
      final relTime = _parseTime(_tag(positionInfo, 'RelTime'));
      // For a transcode the renderer's RelTime is relative to the stream's
      // start position; add it back so the timeline shows the true position.
      position = relTime == null ? null : _streamStartOffset + relTime;
      // A transcode reports a bogus (tiny, growing) TrackDuration — use the
      // real duration we know from the item instead of collapsing the
      // timeline. A direct stream's duration is the real file length.
      duration = _isTranscoding ? _knownDuration?.call() : _parseTime(_tag(positionInfo, 'TrackDuration'));
    }

    // While a just-issued local command settles, trust the optimistic state;
    // once it expires the renderer is authoritative again, so play/seek done on
    // the TV itself is reflected back here.
    final guard = _commandGuardUntil;
    if (guard != null && DateTime.now().isBefore(guard)) {
      position = null;
      playing = null;
    }
    // A parked paused-seek owns the shown position until it's applied on
    // resume — the renderer still reports the pre-seek position while paused
    // and would snap the scrubber back.
    if (_pendingSeek != null) {
      position = null;
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

  /// Rewrites the Jellyfin subtitle URL the same way the media URL went out:
  /// via the configured cast server base, else through the local proxy's
  /// `/sub.srt` route on the same host:port the renderer is already fetching
  /// the media from. Falls back to the raw URL (may be HTTPS — some TVs cope).
  String? _resolveSubtitleUrl(String upstream, String resolvedMediaUrl) {
    final base = castServerBase;
    if (base != null && base.isNotEmpty) {
      final original = Uri.tryParse(upstream);
      final baseUri = Uri.tryParse(base);
      if (original != null && baseUri != null && baseUri.host.isNotEmpty) {
        return original.replace(scheme: baseUri.scheme, host: baseUri.host, port: baseUri.port).toString();
      }
    }
    if (_proxy.isRunning) {
      _proxy.subtitleUpstreamUrl = upstream;
      final media = Uri.tryParse(resolvedMediaUrl);
      if (media != null) return media.replace(path: '/sub.srt').toString();
    }
    return upstream;
  }

  static String _didlMetadata(String url, String mime, {String? subtitleUrl}) {
    // CaptionInfoEx is the Samsung/LG convention for pointing the TV at a
    // subtitle sidecar; the extra `res` entry covers renderers that discover
    // subs through resources instead. Ignored gracefully by everything else.
    final caption = subtitleUrl == null
        ? ''
        : '<sec:CaptionInfoEx sec:type="srt">${_escape(subtitleUrl)}</sec:CaptionInfoEx>'
            '<sec:CaptionInfo sec:type="srt">${_escape(subtitleUrl)}</sec:CaptionInfo>'
            '<res protocolInfo="http-get:*:text/srt:*">${_escape(subtitleUrl)}</res>';
    return '<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:sec="http://www.sec.co.kr/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="0" parentID="-1" restricted="1">'
        '<dc:title>Fladder</dc:title>'
        '<upnp:class>object.item.videoItem</upnp:class>'
        '<res protocolInfo="http-get:*:$mime:$dlnaOrgContentFeatures">${_escape(url)}</res>'
        '$caption'
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

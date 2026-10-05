import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:logging/logging.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/screens/video_player/components/casting_placeholder.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/cast/cast_message_transport.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/player_states.dart';
import 'package:chudder/wrappers/players/remote_device.dart';

final _log = Logger('Cast.jellyfin');

/// Drives the **Jellyfin Cast receiver** (app id `F007D354` or another the
/// server lists) over its custom protocol — the receiver fetches and plays the
/// item itself, so we only hand it credentials + the item. All receiver-control
/// logic lives here; the native, desktop and web senders subclass this and
/// provide only a [CastMessageTransport] (plus, on mobile, a few
/// platform-specific timing overrides).
abstract class JellyfinReceiverPlayer extends BasePlayer implements RemotePlayer {
  JellyfinReceiverPlayer(this.transport, this.context, this.deviceName, {required this.onSessionEnded}) {
    _itemStub = context.itemStub;
    _mediaSourceId = context.mediaSourceId;
    _audioStreamIndex = context.audioStreamIndex;
    _subtitleStreamIndex = context.subtitleStreamIndex;
    _image = context.image;
    _maxBitrate = context.maxBitrate;
    _subtitleAppearance = context.subtitleAppearance;
    _upcoming = context.upcoming;
  }

  @protected
  final CastMessageTransport transport;
  @protected
  final JellyfinCastContext context;

  /// Called when the receiver session ends out from under us — the device was
  /// turned off, another sender took it over, or the transport reports an
  /// explicit end. Lets the app restore local playback. Fired at most once.
  final void Function() onSessionEnded;

  /// Called when the receiver moves to another item by itself — the next in
  /// its queue after one ended, or a skip with the TV's remote — so the app
  /// can show what is really playing. The app answers by pointing the player
  /// at the new item ([updateItem]).
  Future<void> Function(String itemId)? onReceiverChangedItem;

  @override
  final String deviceName;

  // The receiver registers its own server session and reports start/progress/
  // stop itself; the phone must stay quiet to avoid a duplicate session.
  @override
  bool get reportsOwnProgress => true;

  // The receiver fetches from the server itself, so it plays on without us.
  @override
  bool get canLeavePlaying => true;

  final StreamController<PlayerState> _stateController = StreamController.broadcast();
  @protected
  final List<StreamSubscription> subs = [];

  /// Set once the receiver shows any sign of life, so the PlayNow retry loop
  /// stops (a live receiver restarts playback on every duplicate PlayNow).
  @protected
  bool acknowledged = false;

  Map<String, dynamic>? _playNowOptions;
  Timer? _playNowTimer;
  Timer? _positionTicker;

  // Wall-clock anchor for the position ticker: the receiver's last reported
  // position and when it arrived. Position is always computed as
  // anchor + elapsed wall time, so a frozen process (Android cached-app
  // freezer) wakes up with the position still correct instead of minutes
  // behind. Session loss is detected by each transport's authoritative signal
  // (Cast SDK session events / socket close / SESSION_ENDED) — there is
  // deliberately no message-staleness watchdog, matching the official clients.
  Duration _anchorPosition = Duration.zero;
  DateTime? _anchorTime;
  bool _sessionEnded = false;
  bool _completedSignaled = false;

  /// Set once [close] has run; everything after is a no-op.
  bool _closed = false;

  /// Until this instant, a receiver `playbackstop` is one we caused (a
  /// teardown, or the Stop half of a track/quality restart) rather than a
  /// natural end or an external takeover.
  ///
  /// A deadline rather than a bool: a progress report generated before the
  /// receiver processed our Stop must not clear the expectation early — that
  /// race made a mere track switch look like an external stop — and an
  /// expectation that never cleared would swallow the next item's real finish.
  DateTime? _expectStopUntil;

  /// Until this instant, a `playbackstop` answers our `Identify`. The receiver
  /// replies to Identify during playback with its full state under that very
  /// message type — the same type as a real stop, with the same body — so only
  /// the timing tells them apart. Read as a stop, the reply to the Identify
  /// sent whenever the app came back to the foreground ended the whole cast.
  DateTime? _identifyReplyUntil;

  /// Completed by the receiver confirming a stop: its `playbackstop`, or (on
  /// mobile) an idle media status.
  Completer<void>? _stopWaiter;

  /// Opens the stop-expectation window; call just before issuing a Stop the
  /// receiver will confirm with a `playbackstop`.
  @protected
  void expectReceiverStop() => _expectStopUntil = DateTime.now().add(const Duration(seconds: 12));

  bool get _stopExpected {
    final until = _expectStopUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _awaitingIdentifyReply {
    final until = _identifyReplyUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Ends the Identify-reply window early, as if its seconds had passed.
  @visibleForTesting
  void debugExpireIdentifyWindow() => _identifyReplyUntil = null;

  // Item/tracks currently playing — seeded from the connect-time context,
  // updated when media changes mid-cast.
  late Map<String, dynamic> _itemStub;
  String? _mediaSourceId;
  int? _audioStreamIndex;
  int? _subtitleStreamIndex;
  ImageProvider? _image;
  int? _maxBitrate;

  /// The app's subtitle look, carried to the receiver so the TV draws them the
  /// way the phone does. Applied by the receiver whenever it turns a subtitle
  /// track on.
  Map<String, dynamic>? _subtitleAppearance;

  /// The items queued behind the current one, for the next PlayNow.
  List<Map<String, dynamic>> _upcoming = const [];

  /// The ids the receiver was last given to play, in order. It works through
  /// these by itself; empty when the receiver's list is not known (a session
  /// rejoined from an earlier run of the app).
  List<String> _receiverPlaylist = const [];

  /// Items this player just moved on from, and when. The receiver keeps
  /// reporting the old one for a moment after a switch, and following those
  /// reports would drag the app back.
  final Map<String, DateTime> _recentlyLeft = {};

  /// While a PlayNow is on its way, the receiver may still report whatever it
  /// played before (a TV rejoined with an earlier cast on it). Until it has
  /// reported the item just sent — or this deadline passes — other items are
  /// not something it moved on to.
  DateTime? _ignoreOtherItemsUntil;

  /// The item the app is being pointed at after the receiver moved on to it,
  /// until that is done — so the reports that keep coming meanwhile do not
  /// start it again.
  String? _followingId;
  Timer? _followRetryTimer;

  /// Waits for the receiver to start the next queued item after one ended.
  /// If it does not, the app carries on from its own queue.
  Timer? _advanceWatchdog;

  /// How long the receiver gets to start the next queued item.
  @visibleForTesting
  Duration advanceWait = const Duration(seconds: 20);

  String? _nowPlayingItemId;
  Completer<String>? _nowPlayingWaiter;

  /// Latest device volume the receiver reported (0–100).
  int? _volumeLevel;

  @override
  int? get remoteVolumeLevel => _volumeLevel;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    subs.add(transport.messages.listen(_onMessage));
    subs.add(transport.linkEvents.listen(_onLinkEvent));
    await onInit();
    // Handshake — a playing receiver replies with its state, an idle one
    // shows its waiting screen.
    await identify();
  }

  /// Subclass-specific init (e.g. the native media-status subscription).
  @protected
  Future<void> onInit() async {}

  /// Asks the receiver for its state. The reply to this is not a stop; see
  /// [_identifyReplyUntil].
  @protected
  Future<void> identify() async {
    _identifyReplyUntil = DateTime.now().add(const Duration(seconds: 5));
    await sendCommand('Identify', {});
  }

  void _onLinkEvent(CastLinkEvent event) {
    switch (event) {
      case CastLinkEvent.suspended:
        onConnectionSuspended();
      case CastLinkEvent.resumed:
        unawaited(onConnectionResumed());
      case CastLinkEvent.ended:
        signalSessionEnded('the transport reported the session over');
    }
  }

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    // Connected without active playback (remote-control mode) — nothing to play
    // until the user starts an item (which updates the stub first).
    if (_itemStub['Id'] == null) {
      _log.info('Cast session idle — waiting for an item to play');
      return;
    }
    // The receiver fetches the item itself; `url` is ignored.
    acknowledged = false;
    // New item: re-arm end-of-item detection and drop the previous item's
    // completion, so a stale flag can't re-trigger the auto-advance.
    _completedSignaled = false;
    _ignoreOtherItemsUntil = DateTime.now().add(const Duration(seconds: 30));
    _playNowOptions = _buildPlayNowOptions(startPosition);
    _setAnchor(startPosition);
    lastState = lastState.update(buffering: true, playing: play, position: startPosition, completed: false, error: false);
    _stateController.add(lastState);
    await beginPlayback();
  }

  /// How to deliver the first PlayNow. Default retries until acknowledged; the
  /// native player overrides to stop a live (rejoined) receiver first.
  @protected
  Future<void> beginPlayback() async => startPlayNowAttempts();

  @protected
  Map<String, dynamic>? get playNowOptions => _playNowOptions;

  /// Sends PlayNow, retrying on a wide schedule until the receiver acknowledges
  /// (its web app registers its listener a beat after connect, so the first
  /// sends can be silently dropped). Retries are spaced wide because a landed
  /// PlayNow's first ack only arrives after the receiver's PlaybackInfo
  /// round-trip — retrying inside that window stacks duplicate loads.
  @protected
  void startPlayNowAttempts() {
    _playNowTimer?.cancel();
    const retryDelays = [Duration(seconds: 5), Duration(seconds: 12), Duration(seconds: 18)];
    var attempts = 0;

    Future<void> attempt() async {
      final options = _playNowOptions;
      if (acknowledged || options == null) return;
      attempts++;
      _log.info('PlayNow → "$deviceName" (attempt $attempts, item ${_itemStub['Id']})');
      await sendCommand('PlayNow', options);
    }

    void scheduleNext(int index) {
      if (index >= retryDelays.length) return;
      _playNowTimer = Timer(retryDelays[index], () {
        if (acknowledged) return;
        if (index == retryDelays.length - 1) {
          _log.warning('Receiver still silent — final PlayNow attempt');
        }
        attempt();
        scheduleNext(index + 1);
      });
    }

    attempt();
    scheduleNext(0);
  }

  /// Marks the receiver acknowledged (stops the retry loop). Idempotent; the
  /// native player overrides to also flag the receiver as live.
  @protected
  void markAcknowledged(String via) {
    if (acknowledged) return;
    acknowledged = true;
    _playNowTimer?.cancel();
    _log.info('Receiver acknowledged ($via) — playback handed off');
  }

  @override
  Future<void> play() async {
    // Optimistic; the receiver confirms via playstatechange.
    _setAnchor(lastState.position);
    lastState = lastState.update(playing: true);
    _stateController.add(lastState);
    _syncPositionTicker(true);
    await sendCommand('Unpause', {});
  }

  @override
  Future<void> pause() async {
    _setAnchor(lastState.position);
    lastState = lastState.update(playing: false);
    _stateController.add(lastState);
    _syncPositionTicker(false);
    await sendCommand('Pause', {});
  }

  @override
  Future<void> playOrPause() async => lastState.playing ? pause() : play();

  /// Stops what the receiver is playing but stays connected (the app's stop
  /// button while casting). Ending the session is [dispose] / [leave].
  @override
  Future<void> stop() async {
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _playNowOptions = null;
    // We are tearing down — the resulting playbackstop is ours, not an
    // end-of-item.
    expectReceiverStop();
    await sendCommand('Stop', {});
  }

  @override
  Future<void> seek(Duration position) async {
    // A seek restarts the stream on the receiver (transcodes begin again at the
    // new position), and it reports the old one stopped. That stop is ours.
    expectReceiverStop();
    await sendCommand('Seek', {'position': position.inSeconds});
    _setAnchor(position);
    lastState = lastState.update(position: position);
    _stateController.add(lastState);
  }

  Map<String, dynamic> _buildPlayNowOptions(Duration startPosition) {
    final options = buildPlayNowOptions(
      itemStub: _itemStub,
      startPosition: startPosition,
      upcoming: _upcoming,
      mediaSourceId: _mediaSourceId,
      audioStreamIndex: _audioStreamIndex,
      subtitleStreamIndex: _subtitleStreamIndex,
    );
    _receiverPlaylist = [for (final item in options['items'] as List) (item as Map)['Id'] as String];
    return options;
  }

  // Track switching restarts playback via PlayNow at the current position
  // rather than SetAudio/SetSubtitleStreamIndex — the receiver's in-place
  // changeStream has a display race that flips it to the idle splash, and it
  // leaves a burned-in subtitle on screen when switching away from one.
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _audioStreamIndex ?? -1;
    _audioStreamIndex = model.index;
    await _restartAtCurrentPosition('audio track ${model.index}');
    return model.index;
  }

  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async {
    if (model == null) return _subtitleStreamIndex ?? -1;
    _subtitleStreamIndex = model.index;
    await _restartAtCurrentPosition('subtitle track ${model.index}');
    return model.index;
  }

  /// Carries the app's subtitle look to the receiver. It takes effect the next
  /// time the receiver turns a subtitle on (every load and track switch);
  /// restyling mid-item would mean restarting the stream.
  @override
  void applySubtitleSettings(SubtitleSettingsModel settings) {
    _subtitleAppearance = receiverSubtitleAppearance(settings);
  }

  /// Caps the receiver's stream quality (bits/s; null = auto) and restarts so it
  /// takes effect.
  Future<void> setMaxBitrate(int? bitrate) async {
    _maxBitrate = bitrate;
    await _restartAtCurrentPosition('quality ${bitrate == null ? 'auto' : '${(bitrate / 1000000).round()}Mbps'}');
  }

  /// Points the player at a new item: the user started different media
  /// mid-cast, or the receiver moved on and the app is catching up. The
  /// [upcoming] queue is what the next PlayNow (a track or quality change, or
  /// the next item started from here) hands the receiver to carry on with.
  void updateItem({
    required Map<String, dynamic> itemStub,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    ImageProvider? image,
    List<Map<String, dynamic>> upcoming = const [],
  }) {
    final leaving = _itemStub['Id'];
    if (leaving is String && leaving != itemStub['Id']) _recentlyLeft[leaving] = DateTime.now();
    _followingId = null;
    _followRetryTimer?.cancel();
    _advanceWatchdog?.cancel();
    _upcoming = upcoming;
    _itemStub = itemStub;
    _mediaSourceId = mediaSourceId;
    _audioStreamIndex = audioStreamIndex;
    _subtitleStreamIndex = subtitleStreamIndex;
    _image = image;
  }

  Future<void> _restartAtCurrentPosition(String reason) async {
    final resumeAt = lastState.position;
    // This restart's Stop is ours; don't read its playbackstop as an
    // end-of-item.
    expectReceiverStop();
    _ignoreOtherItemsUntil = DateTime.now().add(const Duration(seconds: 30));
    _playNowOptions = _buildPlayNowOptions(resumeAt);
    _setAnchor(resumeAt);
    lastState = lastState.update(buffering: true, completed: false, error: false);
    _stateController.add(lastState);
    _log.info('Restarting on "$deviceName" ($reason, resume at ${resumeAt.inSeconds}s)');
    // Stop and let the receiver settle before PlayNow, else the old stream's
    // late stop event flips the receiver UI onto the new video.
    await stopReceiverAndWait(const Duration(seconds: 5));
    await sendCommand('PlayNow', _playNowOptions!);
  }

  /// Sends Stop and waits until the receiver confirms the stream stopped, or
  /// [timeout], then gives its stop UI a moment to land before anything new is
  /// loaded on top. The resulting `playbackstop` is ours, not an end-of-item.
  @protected
  Future<void> stopReceiverAndWait(Duration timeout) async {
    if (_closed) return;
    await _stopAndWait(timeout);
  }

  Future<void> _stopAndWait(Duration timeout) async {
    // Armed before the Stop goes out: a quick confirmation must not arrive
    // before anything is listening for it.
    final waiter = _stopWaiter = Completer<void>();
    expectReceiverStop();
    await _send('Stop', {});
    try {
      await waiter.future.timeout(timeout);
    } on TimeoutException {
      _log.fine('Receiver did not confirm the stop within ${timeout.inSeconds}s — continuing');
    } finally {
      if (identical(_stopWaiter, waiter)) _stopWaiter = null;
    }
    await Future.delayed(const Duration(milliseconds: 400));
  }

  /// For subclasses with another signal that the receiver stopped (the Cast
  /// SDK's idle media status).
  @protected
  void confirmReceiverStopped() {
    final waiter = _stopWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  /// The item the receiver reports it's playing — null while idle (used by
  /// remote-control adopt).
  Future<String?> waitForNowPlayingItem(Duration timeout) async {
    if (_nowPlayingItemId != null) return _nowPlayingItemId;
    final waiter = _nowPlayingWaiter = Completer<String>();
    try {
      return await waiter.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      _nowPlayingWaiter = null;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalized = (volume > 1 ? volume / 100 : volume).clamp(0.0, 1.0);
    try {
      await transport.setVolume(normalized);
    } catch (error) {
      _log.fine('Failed to set device volume: $error');
    }
  }

  // The receiver owns playback rate (no protocol command exists).
  @override
  bool get supportsPlaybackRate => false;

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> loop(bool loop) async {}

  @override
  Future<Uint8List?> takeScreenshot() async => null;

  @override
  Widget? subtitles(bool showOverlay, {GlobalKey? controlsKey}) => null;

  @override
  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) =>
      CastingPlaceholder(key: key, deviceName: deviceName, image: _image);

  /// Ends the cast: the user stopped casting, or switched to another device.
  /// A session that already ended elsewhere is only left — the receiver may
  /// be someone else's by now.
  @override
  Future<void> dispose() => close(stopReceiver: !_sessionEnded);

  /// Disconnects and leaves the TV playing (the app is closing, or the user
  /// chose to keep watching there).
  @override
  Future<void> leave() => close(stopReceiver: false);

  /// Tears the session down, stopping the receiver first when [stopReceiver].
  ///
  /// The Stop goes out and is confirmed before the session closes: the
  /// receiver reports its playback stopped to the server only from its own
  /// stop handling, so closing the app under it left a "playing" session on
  /// the server for minutes.
  @protected
  Future<void> close({required bool stopReceiver}) async {
    _resumeWatchdog?.cancel();
    if (_closed) return;
    _closed = true;
    _playNowTimer?.cancel();
    _positionTicker?.cancel();
    _advanceWatchdog?.cancel();
    _followRetryTimer?.cancel();
    if (stopReceiver) await _stopAndWait(const Duration(seconds: 2));
    for (final sub in subs) {
      await sub.cancel();
    }
    subs.clear();
    await transport.close(stopReceiver: stopReceiver);
    if (!_stateController.isClosed) await _stateController.close();
    _log.info(stopReceiver ? 'Stopped casting to "$deviceName"' : 'Left "$deviceName" playing');
  }

  /// Builds the credentials+command envelope and sends it on the Jellyfin
  /// namespace via the [transport].
  @protected
  Future<void> sendCommand(String command, Map<String, dynamic> options) async {
    // A left or stopped session takes no more commands: a late Stop would
    // otherwise reach a TV that was deliberately left playing.
    if (_closed) return;
    await _send(command, options);
  }

  Future<void> _send(String command, Map<String, dynamic> options) async {
    final message = buildJellyfinEnvelope(
      command: command,
      options: options,
      context: context,
      receiverName: deviceName,
      maxBitrate: _maxBitrate,
      subtitleAppearance: _subtitleAppearance,
    );
    // Commands are user/group actions (a few per session) — log them all so
    // the cast log shows both sides of the conversation.
    _log.info('→ $command${command == 'Seek' ? ' ${options['position']}s' : ''}');
    try {
      await transport.sendMessage(message);
    } catch (error) {
      _log.warning('Failed to send $command: $error');
    }
  }

  /// Subclass hook to react to each parsed report.
  @protected
  void onReport(ReceiverReport report) {}

  void _onMessage(String raw) {
    // Any message is a sign of life — stop the retry loop.
    _log.finer('Receiver raw: ${raw.length > 700 ? raw.substring(0, 700) : raw}');
    markAcknowledged('receiver message');
    _lastMessageAt = DateTime.now();
    _linkSuspended = false;
    final report = parseReceiverMessage(raw);
    if (report == null) return;
    onReport(report);

    if (report.isError) {
      _log.warning('Receiver reports ${report.type}${report.message != null ? ': ${report.message}' : ''}');
      // A connection error means the TV cannot reach the server; a playback
      // error that the item cannot be played. Either way nothing is coming,
      // so stop showing a spinner.
      if (report.type != 'error') {
        lastState = lastState.update(buffering: false, playing: false, error: true);
        _stateController.add(lastState);
        _syncPositionTicker(false);
      }
      return;
    }

    final identifyReply = report.type == 'playbackstop' && _awaitingIdentifyReply;
    if (identifyReply) {
      _identifyReplyUntil = null;
      _log.info('Receiver state after Identify: pos=${report.position?.inSeconds}s playing=${report.playing}');
    }
    final stopped = report.type == 'playbackstop' && !identifyReply;
    if (stopped) confirmReceiverStopped();

    final reportedItem = report.itemId;
    if (reportedItem != null) {
      _nowPlayingItemId = reportedItem;
      if (_nowPlayingWaiter?.isCompleted == false) _nowPlayingWaiter!.complete(reportedItem);
      // A stop names the item that just ended, not the one that comes next.
      if (!stopped) _followReceiverTo(reportedItem);
    }
    if (report.audioStreamIndex != null) _audioStreamIndex = report.audioStreamIndex;
    if (report.subtitleStreamIndex != null) _subtitleStreamIndex = report.subtitleStreamIndex;
    if (report.volumeLevel != null) _volumeLevel = report.volumeLevel;

    // The receiver's report is the authoritative position — re-anchor to it.
    // Except in a stop: that one carries no position (zero), and taking it
    // made the end of every episode look like someone stopping the TV halfway.
    final position = stopped && (report.position ?? Duration.zero) <= Duration.zero ? null : report.position;
    if (position != null) _setAnchor(position);
    // `playbackstop` carries no live state, so without this the ticker keeps
    // dead-reckoning a stream that no longer exists — the phone "finishes"
    // the episode on its own clock and auto-advance then queues the next one
    // onto a receiver someone else may be using (ghost playback).
    if (stopped) _log.info('Receiver reports playback stopped — halting local clock');
    lastState = lastState.update(
      playing: stopped ? false : report.playing,
      buffering: false,
      position: position,
      duration: report.duration,
      error: false,
    );
    _stateController.add(lastState);
    // Resync the local ticker to the receiver's authoritative position/state.
    _syncPositionTicker(stopped ? false : (report.playing ?? lastState.playing));
    _log.fine('Receiver ${report.type}: pos=${report.position?.inSeconds}s playing=${report.playing} '
        'audio=${report.audioStreamIndex} sub=${report.subtitleStreamIndex} '
        'media=${report.mediaPlayerState} t=${report.mediaCurrentTime?.inSeconds}');

    // The receiver stopped. Inside the expectation window it is confirming a
    // Stop we sent (teardown / track-quality restart) — ignore it. Otherwise,
    // near the end it is a natural finish → advance; anywhere else someone
    // stopped it from the TV or another sender took over → restore local
    // playback. Watched-state needs no client action either way: the receiver
    // reports its own stop position and the server applies its resume rules.
    if (stopped && !_stopExpected && !_completedSignaled && !_sessionEnded) {
      if (!_reachedEnd()) {
        signalSessionEnded('receiver stopped playback before the end');
      } else if (_receiverHasQueuedNext) {
        _awaitReceiverAdvance();
      } else {
        _signalCompleted();
      }
    }
  }

  /// Whether the receiver has another item lined up behind the current one.
  bool get _receiverHasQueuedNext {
    final index = _receiverPlaylist.indexOf('${_itemStub['Id']}');
    if (index >= 0) return index < _receiverPlaylist.length - 1;
    // A list this player did not send (a rejoined session): the receiver
    // built its own, which follows the same order as the app's queue.
    return _upcoming.isNotEmpty;
  }

  /// The current item ended and the receiver has a next one queued: it starts
  /// that by itself, so this player must not — starting it from here as well
  /// restarted it. If it does not begin within a while (the queue was not what
  /// was thought), the app carries on from its own queue.
  void _awaitReceiverAdvance() {
    _log.info('Receiver finished an item and has more queued — waiting for it to move on');
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _advanceWatchdog?.cancel();
    _advanceWatchdog = Timer(advanceWait, () {
      if (_closed || _sessionEnded || _completedSignaled) return;
      _log.warning('Receiver did not move on to the next item — continuing from the app\'s queue');
      _signalCompleted();
    });
  }

  /// The receiver reports [itemId] as playing. When that is not what the app
  /// thinks is playing, the receiver moved on by itself — the next in its
  /// queue, or a skip on the TV's remote — and the app follows.
  void _followReceiverTo(String itemId) {
    final current = _itemStub['Id'];
    if (itemId == current) {
      // The item just sent is playing: whatever comes next is the receiver's.
      _ignoreOtherItemsUntil = null;
      return;
    }
    if (current == null || _followingId == itemId) return;
    final ignoreUntil = _ignoreOtherItemsUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) return;
    final left = _recentlyLeft[itemId];
    if (left != null && DateTime.now().difference(left) < const Duration(seconds: 8)) return;
    final follow = onReceiverChangedItem;
    if (follow == null) return;

    _log.info('Receiver moved on to item $itemId — following');
    _followingId = itemId;
    _advanceWatchdog?.cancel();
    _completedSignaled = false;
    follow(itemId).catchError((Object error) {
      _log.warning('Could not follow the receiver to $itemId: $error');
    }).whenComplete(() {
      // Done means the app now points at the item ([updateItem] clears this).
      // Failed: try again, but not on every report that arrives meanwhile.
      if (_followingId != itemId || _closed) return;
      _followRetryTimer?.cancel();
      _followRetryTimer = Timer(const Duration(seconds: 10), () => _followingId = null);
    });
  }

  /// True when the receiver's last known position is at (or very near) the end
  /// of the item — used to tell a natural finish from an external stop.
  ///
  /// Deliberately a tight absolute window (matching the local player's ~30s
  /// next-up window) with no percentage branch: someone stopping the TV at,
  /// say, 92% must get local playback back, not the next episode pushed onto
  /// the TV they just stopped — and watched-state does not depend on this
  /// either way, since the receiver reports its own stop position and the
  /// server applies its resume threshold.
  bool _reachedEnd() {
    final total = lastState.duration;
    if (total <= Duration.zero) return false;
    final position = lastState.position;
    if (position <= Duration.zero) return false;
    return (total - position) <= const Duration(seconds: 30);
  }

  /// Signals a natural end of the item once, so the wrapper rolls on to the
  /// next episode. Mutually exclusive with [signalSessionEnded] — a finish must
  /// never look like an external takeover.
  void _signalCompleted() {
    if (_completedSignaled || _sessionEnded) return;
    _completedSignaled = true;
    _positionTicker?.cancel();
    _log.info('Receiver reached the end of the item — signaling completion');
    lastState = lastState.update(playing: false, buffering: false, completed: true);
    _stateController.add(lastState);
  }

  /// Fires [onSessionEnded] once, on an authoritative session end (transport
  /// link event, or the receiver stopped by someone else). A completion
  /// deliberately does not latch this out: after a natural finish, an explicit
  /// session end (the TV powering off) must still tear the cast state down.
  @protected
  void signalSessionEnded(String why) {
    if (_sessionEnded || _closed) return;
    _sessionEnded = true;
    _log.info('Receiver session ended ($why)');
    onSessionEnded();
  }

  /// The link dropped for a moment and the transport is getting it back.
  /// Freeze the position clock and show buffering; nothing is torn down.
  void onConnectionSuspended() {
    _linkSuspended = true;
    _positionTicker?.cancel();
    _setAnchor(lastState.position);
    lastState = lastState.update(buffering: true);
    _stateController.add(lastState);
    _log.info('Cast link suspended — waiting for it to come back');
  }

  /// The link is back (or the app returned from the background). Ask the
  /// receiver where it is — its reply re-anchors position, clears buffering,
  /// and restarts the ticker via [_onMessage].
  Future<void> onConnectionResumed() async {
    if (_closed || _sessionEnded) return;
    _log.info('Cast link resumed — resyncing with the receiver');
    final resumedAt = DateTime.now();
    _resumeWatchdog?.cancel();
    // A receiver that went idle while the link was down never answers. Without
    // this the phone shows a spinner, or counts on past the end, forever.
    _resumeWatchdog = Timer(resumeAnswerWait, () {
      if (_closed || _sessionEnded) return;
      final last = _lastMessageAt;
      if (last != null && !last.isBefore(resumedAt)) return;
      lastState = lastState.update(buffering: false, playing: false);
      _stateController.add(lastState);
      _syncPositionTicker(false);
      signalSessionEnded('the receiver did not answer after the link came back');
    });
    await identify();
  }

  /// Whether the link to the receiver is down right now. The receiver itself
  /// is not stalled then, so this must not read as buffering to a SyncPlay
  /// group - the group would pause for a phone that merely changed network.
  bool get linkSuspended => _linkSuspended;
  bool _linkSuspended = false;
  DateTime? _lastMessageAt;
  Timer? _resumeWatchdog;

  /// How long the receiver gets to answer the Identify sent when the link
  /// came back.
  @visibleForTesting
  Duration resumeAnswerWait = const Duration(seconds: 8);

  void _setAnchor(Duration position) {
    _anchorPosition = position;
    _anchorTime = DateTime.now();
  }

  /// Runs a 1s UI clock while playing, so the scrubber moves smoothly between
  /// the receiver's periodic reports. Position is computed from the wall-clock
  /// anchor rather than incremented, so frozen timers can't make it drift.
  void _syncPositionTicker(bool playing) {
    _positionTicker?.cancel();
    if (!playing || _closed) return;
    _positionTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final anchorTime = _anchorTime;
      if (anchorTime == null) return;
      lastState = lastState.update(position: _anchorPosition + DateTime.now().difference(anchorTime));
      _stateController.add(lastState);
    });
  }
}

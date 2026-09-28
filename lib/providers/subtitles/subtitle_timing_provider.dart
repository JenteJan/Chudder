import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/offline_playback_model.dart';
import 'package:chudder/models/subtitles/subtitle_cues.dart';
import 'package:chudder/models/subtitles/subtitle_line_match.dart';
import 'package:chudder/models/subtitles/subtitle_text_tools.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/players/lib_mpv.dart' show isBitmapSubtitleCodec;

final _log = Logger('SubtitleTiming');

/// How the subtitles of what is playing can be moved in time.
enum SubtitleTimingMode {
  /// The player moves them itself (mpv).
  player,

  /// The app draws them, from the subtitle file, moved - for players that
  /// cannot (the web player, MDK, the Android player).
  app,

  /// A picture subtitle on a player that cannot move it.
  picture,

  /// Playing on another device.
  casting,

  /// No subtitle is on.
  none,
}

/// Lining the subtitles up by a line just heard: the video is paused at
/// [heardAt] while the viewer finds the line in the file.
class SubtitleLineMatch {
  const SubtitleLineMatch({
    required this.heardAt,
    required this.wasPlaying,
    this.cues,
    this.failed = false,
    this.picked,
  });

  final Duration heardAt;

  /// Whether to play on when the match is given up.
  final bool wasPlaying;

  /// The file's lines; null while they load.
  final SubtitleCueList? cues;
  final bool failed;

  /// The line chosen, being played again for the viewer to tap as it is
  /// said; null while it is being looked for.
  final SubtitleLineCandidate? picked;

  SubtitleLineMatch withPicked(SubtitleLineCandidate? picked) =>
      SubtitleLineMatch(heardAt: heardAt, wasPlaying: wasPlaying, cues: cues, failed: failed, picked: picked);
}

/// The subtitle timing being tried out in the player: how far the lines are
/// moved from what the file says, and whether the timing bar is up.
class SubtitleTiming {
  const SubtitleTiming({
    this.delay = Duration.zero,
    this.open = false,
    this.pinned = false,
    this.busy,
    this.trackKey,
    this.cues,
    this.loadingCues = false,
    this.match,
  });

  final Duration delay;
  final bool open;

  /// Opened on purpose, from the subtitle menu: stays until closed. A nudge
  /// from the keyboard only shows it for a moment.
  final bool pinned;

  /// What is being done to the file right now, if anything.
  final String? busy;

  /// The video and track [delay] belongs to.
  final String? trackKey;

  /// The cues the app draws itself while it moves the subtitles for a
  /// player that cannot; null while the player draws them.
  final SubtitleCueList? cues;
  final bool loadingCues;

  /// A line being looked up to set the timing from, if one is.
  final SubtitleLineMatch? match;

  bool get moved => delay != Duration.zero;

  SubtitleTiming copyWith({
    Duration? delay,
    bool? open,
    bool? pinned,
    String? Function()? busy,
    String? Function()? trackKey,
    SubtitleCueList? Function()? cues,
    bool? loadingCues,
    SubtitleLineMatch? Function()? match,
  }) =>
      SubtitleTiming(
        delay: delay ?? this.delay,
        open: open ?? this.open,
        pinned: pinned ?? this.pinned,
        busy: busy != null ? busy() : this.busy,
        trackKey: trackKey != null ? trackKey() : this.trackKey,
        cues: cues != null ? cues() : this.cues,
        loadingCues: loadingCues ?? this.loadingCues,
        match: match != null ? match() : this.match,
      );
}

final subtitleTimingProvider =
    StateNotifierProvider<SubtitleTimingNotifier, SubtitleTiming>((ref) => SubtitleTimingNotifier(ref));

class SubtitleTimingNotifier extends StateNotifier<SubtitleTiming> {
  SubtitleTimingNotifier(this.ref) : super(const SubtitleTiming()) {
    // Another video or another track is another file with its own timing:
    // start it at what its file says. The picker has already put the new
    // track on in the player, so the app's own drawing just stops.
    ref.listen(playBackModel.select((p) => p == null ? null : '${p.item.id}|${p.mediaStreams?.defaultSubStreamIndex}'),
        (previous, next) {
      if (previous == next || state.trackKey == next) return;
      if (state.moved && mode == SubtitleTimingMode.player) {
        unawaited(ref.read(videoPlayerProvider).setSubtitleDelay(Duration.zero));
      }
      state = SubtitleTiming(open: state.open && next != null, pinned: state.pinned, trackKey: next);
    });
  }

  final Ref ref;
  Timer? _hide;
  int _load = 0;

  static const limit = Duration(minutes: 10);

  Duration get step => Duration(milliseconds: ref.read(videoPlayerSettingsProvider).subtitleDelayStepMs);

  SubtitleStreamRef? get _current {
    final playback = ref.read(playBackModel);
    final sub = playback?.mediaStreams?.currentSubStream;
    if (playback == null || sub == null || sub.index == SubStreamModel.no().index) return null;
    return SubtitleStreamRef(playback.item.id, playback.mediaStreams?.currentVersionStream?.id, sub);
  }

  SubtitleTimingMode get mode {
    final player = ref.read(videoPlayerProvider);
    if (player.isCasting) return SubtitleTimingMode.casting;
    final current = _current;
    if (current == null) return SubtitleTimingMode.none;
    if (player.supportsSubtitleDelay) return SubtitleTimingMode.player;
    if (!_hasText(current)) return SubtitleTimingMode.picture;
    return SubtitleTimingMode.app;
  }

  bool get canMove => mode == SubtitleTimingMode.player || mode == SubtitleTimingMode.app;

  /// Whether the lines of the track that is on can be read, to find one
  /// that was heard - a text subtitle, from the server or, for a download,
  /// from the file saved next to it.
  bool get canMatchLine {
    final current = _current;
    return current != null && canMove && _hasText(current);
  }

  bool _hasText(SubtitleStreamRef current) {
    if (isBitmapSubtitleCodec(current.sub.codec)) return false;
    // A downloaded film's subtitle is a file on this device the server cannot
    // hand out: readable when it was saved as text.
    if (ref.read(playBackModel) is OfflinePlaybackModel) return _localFile(current.sub) != null;
    return true;
  }

  static File? _localFile(SubStreamModel sub) {
    final url = sub.url;
    if (url == null || url.isEmpty || url.contains('://')) return null;
    final dot = url.lastIndexOf('.');
    if (dot == -1 || subtitleTextFormatOf(url.substring(dot + 1)) == null) return null;
    final file = File(url);
    return file.existsSync() ? file : null;
  }

  /// [steps] presses of the timing keys: negative shows the lines earlier.
  Future<void> nudge(int steps) => set(state.delay + step * steps);

  Future<void> set(Duration delay) async {
    final how = mode;
    if (how != SubtitleTimingMode.player && how != SubtitleTimingMode.app) {
      // Nothing to move, but say why rather than ignore the key.
      show(pinned: false);
      return;
    }
    final clamped = delay > limit ? limit : (delay < -limit ? -limit : delay);
    state = state.copyWith(delay: clamped, open: true);
    _scheduleHide();
    if (how == SubtitleTimingMode.player) {
      await ref.read(videoPlayerProvider).setSubtitleDelay(clamped);
    } else {
      await _drawInApp(clamped != Duration.zero);
    }
  }

  /// The app takes over drawing the subtitles while they are moved, and
  /// hands them back to the player when they are not.
  Future<void> _drawInApp(bool moved) async {
    final current = _current;
    final player = ref.read(videoPlayerProvider);
    if (!moved) {
      if (state.cues == null && !state.loadingCues) return;
      _load++;
      state = state.copyWith(cues: () => null, loadingCues: false);
      await player.setNativeSubtitlesHidden(false);
      return;
    }
    if (state.cues != null || state.loadingCues || current == null) return;
    final load = ++_load;
    state = state.copyWith(loadingCues: true);
    try {
      final cues = await _loadCues(current);
      if (load != _load || !mounted) return;
      await player.setNativeSubtitlesHidden(true);
      state = state.copyWith(cues: () => cues, loadingCues: false);
    } catch (error) {
      _log.warning('Loading the subtitle to move it failed: $error');
      if (load != _load || !mounted) return;
      state = state.copyWith(loadingCues: false, delay: Duration.zero);
    }
  }

  (String, SubtitleCueList)? _cached;

  /// The lines of [current], read once for drawing and matching alike.
  Future<SubtitleCueList> _loadCues(SubtitleStreamRef current) async {
    final key = '${current.itemId}|${current.mediaSourceId}|${current.sub.index}|${current.sub.path}|${current.sub.url}';
    final cached = _cached;
    if (cached != null && cached.$1 == key) return cached.$2;
    final local = ref.read(playBackModel) is OfflinePlaybackModel ? _localFile(current.sub) : null;
    final cues = local != null
        ? SubtitleCueList.parse(utf8.decode(await local.readAsBytes(), allowMalformed: true))
        : await _fetchCues(current);
    _cached = (key, cues);
    return cues;
  }

  /// The track as text, which the server makes of any text subtitle - one
  /// inside the video as well as a file next to it.
  Future<SubtitleCueList> _fetchCues(SubtitleStreamRef current) async {
    final url = buildServerUrl(
      ref,
      pathSegments: [
        'Videos',
        current.itemId,
        current.mediaSourceId ?? current.itemId,
        'Subtitles',
        '${current.sub.index}',
        '0',
        'Stream.srt',
      ],
      queryParameters: authQueryParameters(ref.read(userProvider)?.credentials.token),
    );
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');
    return SubtitleCueList.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  Future<void> reset() => set(Duration.zero);

  /// Pauses on the line just heard and reads the file to find it in.
  Future<void> startLineMatch() async {
    final current = _current;
    if (current == null || !canMatchLine || state.match != null) return;
    final player = ref.read(videoPlayerProvider);
    final playerState = player.lastState;
    final wasPlaying = playerState?.playing ?? false;
    final heardAt = playerState?.position ?? Duration.zero;
    _hide?.cancel();
    state = state.copyWith(
      open: true,
      pinned: true,
      match: () => SubtitleLineMatch(heardAt: heardAt, wasPlaying: wasPlaying),
    );
    if (wasPlaying) await player.pause();
    try {
      final cues = await _loadCues(current);
      final match = state.match;
      if (!mounted || match == null || match.heardAt != heardAt) return;
      state = state.copyWith(
          match: () => SubtitleLineMatch(heardAt: heardAt, wasPlaying: wasPlaying, cues: cues, failed: cues.cues.isEmpty));
    } catch (error) {
      _log.warning('Loading the subtitle to find a line failed: $error');
      final match = state.match;
      if (!mounted || match == null || match.heardAt != heardAt) return;
      state = state.copyWith(match: () => SubtitleLineMatch(heardAt: heardAt, wasPlaying: wasPlaying, failed: true));
    }
  }

  /// Gives the lookup up and plays on as before.
  Future<void> cancelLineMatch() async {
    final match = state.match;
    if (match == null) return;
    state = state.copyWith(match: () => null);
    if (match.picked != null) {
      // Played again from before the line: it plays on from there.
      await _showNativeAgain();
      return;
    }
    if (match.wasPlaying) await ref.read(videoPlayerProvider).play();
  }

  /// How long before the first guess of the line to start playing it again.
  /// The guess runs late by however long the button took to press, so
  /// there is room for that.
  static const tapLead = Duration(seconds: 8);

  /// Between hearing a line start and the tap landing, for a line the
  /// viewer is waiting for.
  static const tapReaction = Duration(milliseconds: 200);

  /// The typed search only says which line it was; when it was said is
  /// timed by ear: the line plays again, with the subtitles out of sight so
  /// they do not lead the tap, and [tapLine] sets the timing from the tap.
  Future<void> pickLine(SubtitleLineCandidate candidate) async {
    final match = state.match;
    if (match == null) return;
    state = state.copyWith(match: () => match.withPicked(candidate));
    // The app hides its own drawing of the lines while one is being tapped;
    // a player drawing them itself is told to stop.
    if (mode == SubtitleTimingMode.app && state.cues == null) {
      await ref.read(videoPlayerProvider).setNativeSubtitlesHidden(true);
    }
    await replayLine();
  }

  /// Plays the picked line again from a little before its first guess.
  Future<void> replayLine() async {
    final picked = state.match?.picked;
    if (picked == null) return;
    final player = ref.read(videoPlayerProvider);
    final guess = picked.cue.start + picked.delay - tapLead;
    await player.seek(guess.isNegative ? Duration.zero : guess);
    await player.play();
  }

  /// The picked line started at [position] in the video, by the viewer's
  /// tap: time the subtitles by it and play on.
  Future<void> tapLine(Duration position) async {
    final picked = state.match?.picked;
    if (picked == null) return;
    final exact = position - tapReaction - picked.cue.start;
    state = state.copyWith(match: () => null);
    await _showNativeAgain();
    // A hundredth of a second is finer than any tap.
    await set(Duration(milliseconds: (exact.inMilliseconds / 10).round() * 10));
  }

  /// Takes the first guess instead of a tap.
  Future<void> useGuess() async {
    final picked = state.match?.picked;
    if (picked == null) return;
    state = state.copyWith(match: () => null);
    await _showNativeAgain();
    await set(picked.delay);
  }

  /// Back to the list of lines, paused where the line was heard.
  Future<void> unpickLine() async {
    final match = state.match;
    if (match?.picked == null) return;
    state = state.copyWith(match: () => match!.withPicked(null));
    await _showNativeAgain();
    final player = ref.read(videoPlayerProvider);
    await player.pause();
    await player.seek(match!.heardAt);
  }

  Future<void> _showNativeAgain() async {
    if (mode == SubtitleTimingMode.app && state.cues == null) {
      await ref.read(videoPlayerProvider).setNativeSubtitlesHidden(false);
    }
  }

  void show({bool pinned = true}) {
    state = state.copyWith(open: true, pinned: pinned || state.pinned);
    _scheduleHide();
  }

  void close() {
    _hide?.cancel();
    if (state.match != null) unawaited(cancelLineMatch());
    state = state.copyWith(open: false, pinned: false);
  }

  /// The file behind the track changed on the server: read it again the
  /// next time its lines are needed.
  void fileChanged() => _cached = null;

  /// The timing is now in the file: play it as the file says.
  Future<void> baked() async {
    final how = mode;
    state = state.copyWith(delay: Duration.zero, busy: () => null);
    if (how == SubtitleTimingMode.player) {
      await ref.read(videoPlayerProvider).setSubtitleDelay(Duration.zero);
    } else {
      await _drawInApp(false);
    }
  }

  void setBusy(String? message) {
    state = state.copyWith(busy: () => message, open: message != null ? true : null);
    _scheduleHide();
  }

  /// Keeps the bar up while the pointer is over it.
  void hold() => _hide?.cancel();
  void release() => _scheduleHide();

  void _scheduleHide() {
    _hide?.cancel();
    if (state.pinned || state.busy != null) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted && !state.pinned && state.busy == null) state = state.copyWith(open: false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }
}

/// A timing typed by the viewer: seconds ("1.5", "-2", "+0,25 s") or
/// minutes and seconds ("-1:05.5"). Positive shows the subtitles later.
/// Null when it is not a timing.
Duration? parseSubtitleDelay(String input) {
  var text = input.trim().replaceAll(',', '.').replaceAll(RegExp(r'\s+'), '');
  if (text.endsWith('s')) text = text.substring(0, text.length - 1);
  if (text.isEmpty) return null;
  var sign = 1;
  if (text.startsWith('-') || text.startsWith('+')) {
    sign = text.startsWith('-') ? -1 : 1;
    text = text.substring(1);
  }
  final match = RegExp(r'^(?:(\d+):)?(\d+(?:\.\d*)?|\.\d+)$').firstMatch(text);
  if (match == null) return null;
  final minutes = int.parse(match[1] ?? '0');
  final seconds = double.parse(match[2]!);
  if (match[1] != null && seconds >= 60) return null;
  final ms = ((minutes * 60 + seconds) * 1000).round();
  return Duration(milliseconds: sign * ms);
}

class SubtitleStreamRef {
  const SubtitleStreamRef(this.itemId, this.mediaSourceId, this.sub);
  final String itemId;
  final String? mediaSourceId;
  final SubStreamModel sub;
}

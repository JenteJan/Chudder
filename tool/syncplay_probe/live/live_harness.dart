// Headless SyncPlay members for tests against a real server: the app's own
// notifier, media wrapper, controller, HTTP client and websocket, with only
// mpv replaced by a simulated clock. No window, no audio, no media session.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chopper/chopper.dart' show Response;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/video_stream_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/player_states.dart';

const liveHost = 'https://jellyfin-demo.jentejan.uk';

class SimEvent {
  SimEvent(this.at, this.what, this.position);
  final DateTime at;
  final String what;
  final Duration position;
  @override
  String toString() => '${at.toIso8601String().substring(11, 23)} $what @${position.inMilliseconds / 1000}';
}

/// mpv as far as SyncPlay can tell: a position that runs on a clock, a load
/// and a seek that take time, buffering, and an end of file that leaves
/// `playing` true the way the real wrapper does.
class SimPlayer extends BasePlayer {
  SimPlayer(this.name);
  final String name;

  Duration loadTime = const Duration(milliseconds: 300);
  Duration seekTime = const Duration(milliseconds: 60);
  Duration startLatency = const Duration(milliseconds: 50);

  /// How far the file runs past the length the server has for it.
  Duration fileOverrun = const Duration(milliseconds: 2700);
  Duration Function(String url) lengthOf = (_) => const Duration(hours: 1);

  final events = <SimEvent>[];
  final _states = StreamController<PlayerState>.broadcast();
  Timer? _clock;
  DateTime _lastTick = DateTime.now();
  double _rate = 1;
  bool _running = false;
  bool _stalled = false;
  Duration _fileEnd = const Duration(hours: 1);
  int _load = 0;

  void _note(String what) => events.add(SimEvent(DateTime.now(), what, lastState.position));

  Duration get position => lastState.position;
  bool get running => _running;

  void _emit() {
    if (!_closed) _states.add(lastState);
  }

  bool _closed = false;

  void shutdown() {
    _closed = true;
    _clock?.cancel();
    _running = false;
  }

  void _tick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTick);
    _lastTick = now;
    if (_running && !_stalled && !lastState.completed) {
      var next = lastState.position + elapsed * _rate;
      if (next >= _fileEnd) {
        next = _fileEnd;
        lastState = lastState.update(position: next, completed: true);
        _note('eof');
      } else {
        lastState = lastState.update(position: next);
      }
      _emit();
    }
  }

  /// A network stall of [length] while playing.
  void stall(Duration length) {
    _note('stall');
    _stalled = true;
    lastState = lastState.update(buffering: true);
    _emit();
    Timer(length, () {
      _stalled = false;
      lastState = lastState.update(buffering: false);
      _note('stall over');
      _emit();
    });
  }

  @override
  Stream<PlayerState> get stateStream => _states.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _clock ??= Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    final load = ++_load;
    _running = false;
    final length = lengthOf(url);
    _fileEnd = length + fileOverrun;
    lastState = lastState.update(
      position: startPosition,
      buffering: true,
      completed: false,
      duration: length,
      playing: false,
    );
    _note('load $url');
    _emit();
    Timer(loadTime, () {
      if (load != _load) return;
      lastState = lastState.update(buffering: false);
      _note('loaded');
      _emit();
      if (play) this.play();
    });
  }

  @override
  Future<void> seek(Duration position) async {
    lastState = lastState.update(position: position, buffering: true, completed: false);
    _note('seek');
    _emit();
    Timer(seekTime, () {
      lastState = lastState.update(buffering: false);
      _emit();
    });
  }

  @override
  Future<void> play() async {
    _note('play');
    lastState = lastState.update(playing: true);
    _emit();
    Timer(startLatency, () {
      _lastTick = DateTime.now();
      _running = true;
    });
  }

  @override
  Future<void> pause() async {
    _tick();
    _running = false;
    _note('pause');
    lastState = lastState.update(playing: false);
    _emit();
  }

  @override
  Future<void> stop() async {
    _running = false;
    _load++;
  }

  @override
  Future<void> setSpeed(double speed) async => _rate = speed;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> playOrPause() async => _running ? pause() : play();
  @override
  Future<void> loop(bool loop) async {}
  @override
  Future<Uint8List?> takeScreenshot() async => null;
  @override
  Future<int> setSubtitleTrack(SubStreamModel? model, PlaybackModel playbackModel) async => -1;
  @override
  Future<int> setAudioTrack(AudioStreamModel? model, PlaybackModel playbackModel) async => 0;
  @override
  Widget? subtitles(bool showOverlay, {GlobalKey<State<StatefulWidget>>? controlsKey}) => null;
  @override
  Widget? videoWidget(Key key, BoxFit fit, {FilterQuality filterQuality = FilterQuality.low}) => null;
}

class _Controls extends MediaControlsWrapper {
  _Controls({required super.ref, required this.sim});
  final SimPlayer sim;

  @override
  Future<void> init() async {
    if (!hasPlayer) await setup(sim);
  }

  @override
  Future<void> dispose({bool releasePlayer = true}) async {}

  @override
  bool get canReusePlayer => true;

  /// As mpv: not before the file has loaded or the seek has landed, four
  /// seconds at the most.
  @override
  Future<void> waitUntilPlayable() async {
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (sim.lastState.buffering && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }
}

class _Notifier extends VideoPlayerNotifier {
  _Notifier(super.ref, SimPlayer sim) {
    state = _Controls(ref: ref, sim: sim);
    init();
  }
}

class _User extends User {
  _User(this.account);
  final AccountModel account;
  @override
  AccountModel? build() => account;

  // Reads a provider that depends on this one, which only a debug build objects
  // to, and it is not what is under test.
  @override
  Future<Response<UserData>?> markAsPlayed(bool enable, String itemId) async => null;
}

/// The real helper, except that a model does not ask the server for stream
/// info it has no use for here, and the database of downloads stays shut.
class _Helper extends PlaybackModelHelper {
  const _Helper({required super.ref});

  @override
  Future<void> completeWithFullItem(PlaybackModel model) async {}

  @override
  Future<PlaybackModel?> createPlaybackModel(
    BuildContext? context,
    ItemBaseModel? item, {
    PlaybackModel? oldModel,
    List<ItemBaseModel>? libraryQueue,
    PlaybackQueueSource? queueSource,
    bool showPlaybackOptions = false,
    PlaybackType? forcedPlaybackType,
    Duration? startPosition,
    bool itemIsFresh = false,
    bool startAheadOfFullItem = false,
    bool preferDownloaded = false,
  }) async {
    if (item == null) return null;
    final queue = libraryQueue ?? await collectQueue(item);
    final target = item is SeriesModel || item is SeasonModel ? queue.whereType<EpisodeModel>().toList().nextUp : item;
    if (target == null) return null;
    return DirectPlaybackModel(item: target, media: Media(url: 'sim://${target.id}'), queue: queue);
  }
}

class Member {
  Member(this.name, this.container, this.sim);
  final String name;
  final ProviderContainer container;
  final SimPlayer sim;

  SyncPlay get sync => container.read(syncPlayProvider.notifier);
  SyncPlayState get group => sync.controller.state;
  VideoPlayerNotifier get player => container.read(videoPlayerProvider.notifier);
  PlaybackModelHelper get helper => container.read(playbackModelHelper);
  PlaybackModel? get model => container.read(playBackModel);

  static Future<Member> create(String name, Map<String, Duration> lengths) async {
    final deviceId = 'live-$name-${DateTime.now().millisecondsSinceEpoch}';
    final response = await http.post(
      Uri.parse('$liveHost/Users/AuthenticateByName'),
      headers: {
        'Authorization': 'MediaBrowser Client="ChudderLive", Device="$name", DeviceId="$deviceId", Version="1"',
        'Content-Type': 'application/json',
      },
      body: json.encode({'Username': 'demo', 'Pw': 'demo'}),
    );
    final body = json.decode(response.body) as Map<String, dynamic>;
    final account = AccountModel(
      name: 'demo',
      id: (body['User'] as Map<String, dynamic>)['Id'] as String,
      avatar: '',
      lastUsed: DateTime.now(),
      credentials: CredentialsModel.internal(token: body['AccessToken'] as String, url: liveHost, deviceId: deviceId),
      policy: const UserPolicy(authenticationProviderId: '', passwordResetProviderId: ''),
    );
    final prefs = await SharedPreferences.getInstance();
    final sim = SimPlayer(name)..lengthOf = (url) => lengths[url.replaceFirst('sim://', '')] ?? const Duration(hours: 1);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        userProvider.overrideWith(() => _User(account)),
        videoPlayerProvider.overrideWith((ref) => _Notifier(ref, sim)),
        playbackModelHelper.overrideWith((ref) => _Helper(ref: ref)),
      ],
    );
    final member = Member(name, container, sim);
    container.read(isVideoPlayerRouteOpenProvider.notifier).state = true;
    member.player;
    await member.sync.connect();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return member;
  }

  /// Play [item] outside any group, the way the app does.
  Future<void> playSolo(ItemBaseModel item, Duration from) async {
    final built = await helper.createPlaybackModel(null, item);
    await player.loadPlaybackItem(built!, from, waitForSyncPlayCommand: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  Future<void> dispose() async {
    // The container stays: timers in the app outlive a scenario, and the
    // process ending takes the sockets with it.
    sim.shutdown();
    try {
      await sync.disconnect();
    } catch (_) {}
  }
}

void stubConnectivity() {
  ConnectivityStatus.readOsConnectivity = () async => [ConnectivityResult.wifi];
  ConnectivityStatus.osConnectivityEvents = () => const Stream.empty();
  ConnectivityStatus.probeServer = (_) async => true;
  ConnectivityStatus.recycleConnections = () {};
}

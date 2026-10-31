// A SyncPlay group on a virtual clock: the app's own notifier, media wrapper
// and SyncPlay code for each member, the ported server, and a network between
// them that delays, reorders and drops. Everything here runs in a FakeAsync.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:chopper/chopper.dart' show Response;
import 'package:clock/clock.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/jellyfin/jellyfin_json_converter.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/models/video_stream_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/providers/websocket/jellyfin_websocket.dart';
import 'package:chudder/providers/websocket/jellyfin_websocket_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';
import 'package:chudder/wrappers/players/base_player.dart';
import 'package:chudder/wrappers/players/player_states.dart';

import 'sim_server.dart';

List<String>? debugRoutes;

const episodeLength = Duration(minutes: 30);
const episodeCount = 6;

/// mpv as SyncPlay sees it: see tool/syncplay_probe/live for the real timings
/// these stand for. `playing` stays true at the end of the file, as it does
/// in the real wrapper.
class SimPlayer extends BasePlayer {
  SimPlayer(this._random);
  final Random _random;

  // Measured on libmpv over a LAN; see tool/syncplay_probe/live.
  Duration loadTime = const Duration(milliseconds: 400);
  Duration startLatency = const Duration(milliseconds: 18);
  Duration fileOverrun = Duration.zero;

  /// Out of the cache, mpv's seeks take up to 175 ms; in it, about 30.
  Duration get seekTime => Duration(milliseconds: 15 + _random.nextInt(160));

  final _states = StreamController<PlayerState>.broadcast(sync: true);
  Timer? _clock;
  DateTime _lastTick = clock.now();
  double _rate = 1;
  bool _running = false;
  bool _stalled = false;
  Duration _fileEnd = episodeLength;
  int _load = 0;
  int _seeks = 0;

  bool get running => _running && !_stalled && !lastState.completed;
  Duration get position => lastState.position;
  bool get atEnd => lastState.completed;

  void _emit() => _states.add(lastState);

  void _tick() {
    final now = clock.now();
    final elapsed = now.difference(_lastTick);
    _lastTick = now;
    if (!running) return;
    var next = lastState.position + elapsed * _rate;
    // mpv says so a little ahead of the last frame.
    if (next >= _fileEnd - const Duration(milliseconds: 150)) {
      next = _fileEnd;
      lastState = lastState.update(position: next, completed: true);
    } else {
      lastState = lastState.update(position: next);
    }
    _emit();
  }

  void stall(Duration length) {
    _stalled = true;
    lastState = lastState.update(buffering: true);
    _emit();
    Timer(length, () {
      _stalled = false;
      lastState = lastState.update(buffering: false);
      _emit();
    });
  }

  @override
  Stream<PlayerState> get stateStream => _states.stream;

  @override
  Future<void> init(VideoPlayerSettingsModel settings) async {
    _clock ??= Timer.periodic(const Duration(milliseconds: 50), (_) => _tick());
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> open(BuildContext context) async {}

  @override
  Future<void> loadVideo(String url, bool play, {Duration startPosition = Duration.zero}) async {
    final load = ++_load;
    _seeks++;
    _running = false;
    _fileEnd = episodeLength + fileOverrun;
    lastState = lastState.update(
      position: startPosition,
      buffering: true,
      completed: false,
      duration: episodeLength,
      playing: false,
    );
    _emit();
    Timer(loadTime, () {
      if (load != _load) return;
      lastState = lastState.update(buffering: false);
      _emit();
      if (play) this.play();
    });
  }

  @override
  Future<void> seek(Duration position) async {
    // The call returns before anything has moved, and the buffering flag
    // never comes up for a seek on a good link.
    final seek = ++_seeks;
    Timer(seekTime, () {
      if (seek != _seeks) return;
      final target = position > _fileEnd ? _fileEnd : position;
      lastState = lastState.update(position: target, completed: false);
      _emit();
    });
  }

  @override
  Future<void> play() async {
    lastState = lastState.update(playing: true);
    _emit();
    Timer(startLatency, () {
      _lastTick = clock.now();
      _running = lastState.playing;
    });
  }

  @override
  Future<void> pause() async {
    _tick();
    _running = false;
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

  @override
  Future<void> waitUntilPlayable() async {
    final end = clock.now().add(const Duration(seconds: 4));
    while (sim.lastState.buffering && clock.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
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
  @override
  Future<Response<UserData>?> markAsPlayed(bool enable, String itemId) async => null;
}

class _Connectivity extends ConnectivityStatus {
  @override
  ConnectionState build() => ConnectionState.wifi;
}

class _Helper extends PlaybackModelHelper {
  const _Helper({required super.ref, required this.member});
  final SimMember member;

  @override
  Future<void> completeWithFullItem(PlaybackModel model) async {}

  @override
  Future<List<ItemBaseModel>> collectQueue(ItemBaseModel model) async => member.episodes(ref);

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
    await Future<void>.delayed(member.world.upLatency(member));
    final queue = libraryQueue ?? await collectQueue(item);
    final target = item is SeriesModel || item is SeasonModel ? queue.whereType<EpisodeModel>().toList().nextUp : item;
    if (target == null) return null;
    return DirectPlaybackModel(item: target, media: Media(url: 'sim://${target.id}'), queue: queue);
  }
}

class _Api extends JellyApi {
  _Api(this.member);
  final SimMember member;
  @override
  JellyService build() => JellyService(
        ref,
        JellyfinOpenApi.create(
          baseUrl: Uri.parse('http://sim'),
          httpClient: MockClient(member.handle),
          converter: const FladderJsonConverter(),
        ),
      );
}

class SimSocket extends JellyfinWebSocketController {
  SimSocket(this.member);
  final SimMember member;

  final _stateOut = StreamController<WebSocketConnectionState>.broadcast();
  final _messagesOut = StreamController<Map<String, dynamic>>.broadcast();

  @override
  WebSocketConnectionState build() {
    member.socket = this;
    return WebSocketConnectionState.connected;
  }

  @override
  Stream<WebSocketConnectionState> get connectionState => _stateOut.stream;
  @override
  Stream<Map<String, dynamic>> get messages => _messagesOut.stream;
  @override
  WebSocketConnectionState get currentState =>
      member.online ? WebSocketConnectionState.connected : WebSocketConnectionState.disconnected;
  @override
  Future<void> ensureConnected() async {}

  void announce() => _stateOut.add(currentState);
  void deliver(Map<String, dynamic> frame) => _messagesOut.add(frame);
}

/// How a member reaches the server.
class Link {
  const Link(this.name, this.baseMs, this.jitterMs);
  final String name;
  final int baseMs;
  final int jitterMs;

  static const lan = Link('lan', 3, 2);
  static const wan = Link('wan', 40, 30);
  static const bad = Link('bad', 150, 150);
}

/// For what needs a Ref from outside a provider.
class _RefOwner {
  _RefOwner(this.ref, this.member);
  final Ref ref;
  final SimMember member;
  List<ItemBaseModel> get episodes => member.episodes(ref);
  Future<void> report(PlaybackModel model, Duration position) async => model.playbackStarted(position, ref);
}

final _refOwnerProvider = Provider.family<_RefOwner, SimMember>((ref, member) => _RefOwner(ref, member));

class SimMember {
  SimMember(this.world, this.name, this.link, SharedPreferences prefs) : sim = SimPlayer(world.random) {
    final account = AccountModel(
      name: name,
      id: 'user-$name',
      avatar: '',
      lastUsed: DateTime(2026),
      credentials: CredentialsModel.internal(token: 't', url: 'http://sim', deviceId: 'device-$name'),
      policy: const UserPolicy(authenticationProviderId: '', passwordResetProviderId: ''),
    );
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      userProvider.overrideWith(() => _User(account)),
      connectivityStatusProvider.overrideWith(_Connectivity.new),
      jellyApiProvider.overrideWith(() => _Api(this)),
      jellyfinWebSocketControllerProvider.overrideWith(() => SimSocket(this)),
      videoPlayerProvider.overrideWith((ref) => _Notifier(ref, sim)),
      playbackModelHelper.overrideWith((ref) => _Helper(ref: ref, member: this)),
    ]);
    session = _newSession();
    container.read(isVideoPlayerRouteOpenProvider.notifier).state = true;
    container.read(jellyfinWebSocketControllerProvider);
    container.read(jellyfinWebSocketControllerProvider.notifier);
    player;
  }

  final SimWorld world;
  final String name;
  final Link link;
  final SimPlayer sim;
  late final ProviderContainer container;
  late SimSession session;
  _RefOwner get _refOwner => container.read(_refOwnerProvider(this));
  SimSocket? socket;
  bool online = true;

  /// Closed its player and stayed in the group, so it has nothing to be in
  /// step with.
  bool closed = false;

  /// Not meant to be in the group just now.
  bool outside = false;
  int _connection = 0;
  DateTime _lastDelivery = clock.now();

  /// A Series or Season reported by the group, for the checks.
  List<ItemBaseModel>? _episodes;

  SimSession _newSession() {
    final id = 'session-$name';
    final s = SimSession(id, name, _push);
    world.server.sessions[id] = s;
    return s;
  }

  SyncPlay get sync => container.read(syncPlayProvider.notifier);
  SyncPlayState get group => sync.controller.state;
  VideoPlayerNotifier get player => container.read(videoPlayerProvider.notifier);
  PlaybackModelHelper get helper => container.read(playbackModelHelper);
  PlaybackModel? get model => container.read(playBackModel);

  List<ItemBaseModel> episodes(Ref ref) => _episodes ??= [
        for (var i = 0; i < episodeCount; i++)
          EpisodeModel.fromBaseDto(BaseItemDto.fromJson(world.episodeJson(i)), ref),
      ];

  List<ItemBaseModel> get firstEpisodes => _refOwner.episodes;
  /// A model that knows only its own item, the way a film or a single
  /// episode played from outside any queue does.
  PlaybackModel lonelyModel(ItemBaseModel item) =>
      DirectPlaybackModel(item: item, media: Media(url: 'sim://${item.id}'), queue: [item]);

  Future<void> reportStarted(PlaybackModel model) async {
    await _refOwner.report(model, sim.position);
  }

  void _push(Map<String, dynamic> frame) {
    final connection = _connection;
    if (!online) return;
    final encoded = json.encode(frame);
    var at = clock.now().add(world.downLatency(this));
    if (at.isBefore(_lastDelivery)) at = _lastDelivery;
    _lastDelivery = at;
    Timer(at.difference(clock.now()), () {
      if (connection != _connection || !online) return;
      socket?.deliver(json.decode(encoded) as Map<String, dynamic>);
    });
  }

  /// The socket goes for [length]: the server takes that as the session
  /// leaving, and the client comes back and rejoins by itself.
  void dropSocket(Duration length) {
    if (!online) return;
    online = false;
    _connection++;
    socket?.announce();
    world.server.leaveIfIn(session);
    Timer(length, () {
      online = true;
      _lastDelivery = clock.now();
      session = _newSession();
      socket?.announce();
    });
  }

  Future<http.Response> handle(http.Request request) async {
    await Future<void>.delayed(world.upLatency(this));
    if (!online) throw http.ClientException('offline');
    final answer = world.route(this, request);
    await Future<void>.delayed(world.downLatency(this));
    return answer;
  }
}

class SimWorld {
  SimWorld(this.random, this.prefs, {Duration clockSkew = Duration.zero})
      : server = SimServer(clockSkew: clockSkew, runTimeOf: (_) => episodeLength.inMicroseconds * 10);

  final Random random;
  final SharedPreferences prefs;
  final SimServer server;
  final members = <SimMember>[];

  Duration upLatency(SimMember m) =>
      Duration(milliseconds: m.link.baseMs + (m.link.jitterMs == 0 ? 0 : random.nextInt(m.link.jitterMs)));
  Duration downLatency(SimMember m) => upLatency(m);

  Map<String, dynamic> episodeJson(int i) => {
        'Id': 'ep$i',
        'Name': 'Episode $i',
        'Type': 'Episode',
        'MediaType': 'Video',
        'LocationType': 'FileSystem',
        'SeriesId': 'show',
        'SeriesName': 'Show',
        'SeasonId': 'season',
        'ParentId': 'season',
        'IndexNumber': i + 1,
        'ParentIndexNumber': 1,
        'RunTimeTicks': episodeLength.inMicroseconds * 10,
        'UserData': {'PlaybackPositionTicks': 0, 'Played': false, 'PlayCount': 0, 'IsFavorite': false},
      };

  http.Response route(SimMember m, http.Request request) {
    final path = request.url.path;
    debugRoutes?.add('${m.name} ${request.method} ${request.url}');
    final Map<String, dynamic> body = request.body.isEmpty ? {} : json.decode(request.body) as Map<String, dynamic>;
    final s = m.session;
    http.Response ok([Object? value]) => value == null
        ? http.Response('', 204)
        : http.Response(json.encode(value), 200, headers: {'content-type': 'application/json'});

    if (path == '/GetUtcTime') {
      final now = server.now.toIso8601String();
      return ok({'RequestReceptionTime': now, 'ResponseTransmissionTime': now});
    }
    final byId = RegExp(r'^/SyncPlay/([0-9a-f]{32})$').firstMatch(path);
    if (byId != null) {
      final group = server.groups[byId[1]];
      return group == null ? http.Response('', 404) : ok(group.info());
    }
    if (path == '/SyncPlay/List') return ok(server.groups.values.map((g) => g.info()).toList());
    if (path == '/SyncPlay/New') return ok(server.newGroup(s, body['GroupName'] as String));
    if (path == '/SyncPlay/Join') {
      server.join(s, body['GroupId'] as String);
      return ok();
    }
    if (path == '/SyncPlay/Leave') {
      server.leave(s);
      return ok();
    }
    if (path.startsWith('/SyncPlay/')) {
      server.inGroup(s, (g) {
        switch (path.substring('/SyncPlay/'.length)) {
          case 'SetNewQueue':
            g.play(s, (body['PlayingQueue'] as List).cast<String>(), body['PlayingItemPosition'] as int? ?? 0,
                body['StartPositionTicks'] as int? ?? 0);
          case 'Pause':
            g.pause(s);
          case 'Unpause':
            g.unpause(s);
          case 'Stop':
            g.stop(s);
          case 'Seek':
            g.seek(s, body['PositionTicks'] as int);
          case 'Buffering':
            g.buffering(s, body);
          case 'Ready':
            g.ready(s, body);
          case 'NextItem':
            g.stepItem(s, 1, body['PlaylistItemId'] as String?, 'NextItem');
          case 'PreviousItem':
            g.stepItem(s, -1, body['PlaylistItemId'] as String?, 'PreviousItem');
          case 'Ping':
            g.updatePing(s, (body['Ping'] as num).toInt());
          case 'Queue':
            g.queueItems(s, (body['ItemIds'] as List).cast<String>());
        }
      });
      return ok();
    }
    if (path == '/Sessions/Playing' || path == '/Sessions/Playing/Progress') {
      s.nowPlayingItem = body['ItemId'] as String?;
      s.nowPlayingTicks = body['PositionTicks'] as int? ?? s.nowPlayingTicks;
      s.nowPlayingPaused = body['IsPaused'] as bool? ?? false;
      return ok();
    }
    if (path == '/Sessions/Playing/Stopped') {
      s.nowPlayingItem = null;
      return ok();
    }
    if (path == '/Sessions') return ok(<Object>[]);
    if (path == '/Items' || path.endsWith('/Items')) {
      final ids = [for (final value in request.url.queryParametersAll['ids'] ?? const <String>[]) ...value.split(',')];
      final items = [
        for (final id in ids)
          if (RegExp(r'^ep\d+$').hasMatch(id)) episodeJson(int.parse(id.substring(2))),
      ];
      return ok({'Items': items, 'TotalRecordCount': items.length, 'StartIndex': 0});
    }
    final item = RegExp(r'/Items/ep(\d+)$').firstMatch(path);
    if (item != null) return ok(episodeJson(int.parse(item[1]!)));
    if (path == '/Items/show' || path == '/Items/season') {
      return ok({'Id': path.substring(7), 'Name': 'Show', 'Type': path.endsWith('show') ? 'Series' : 'Season'});
    }
    return ok(<String, Object>{});
  }
}

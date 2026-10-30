// Two real members on the demo server. Copy this folder to test/syncplay_live in a throwaway worktree,
// add `&& !const bool.fromEnvironment('HEADLESS_SYNCPLAY')` to the Windows media session check in
// media_control_wrapper.dart there (a media session here would take the media keys), then run:
//   flutter test test/syncplay_live/live_test.dart --dart-define=HEADLESS_SYNCPLAY=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/api_provider.dart';

import 'live_harness.dart';

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

/// Every SyncPlay line, kept so a failure can be read.
final trace = <String>[];

Future<bool> until(bool Function() what, {num seconds = 10}) async {
  final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(end)) {
    if (what()) return true;
    await wait(0.03);
  }
  return what();
}

double apart(Member a, Member b) => (a.sim.position - b.sim.position).inMilliseconds.abs().toDouble();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  stubConnectivity();

  // Plugins with nothing behind them here: answered, and forgotten.
  for (final name in ['dev.fluttercommunity.plus/package_info', 'wakelock_plus', 'plugins.flutter.io/path_provider']) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
  );
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync')) {
      trace.add('${r.time.toIso8601String().substring(11, 23)} ${r.message}');
    }
  });

  late List<String> episodes;
  late Map<String, Duration> lengths;
  late String seriesId;
  late Member a;
  late Member b;

  setUpAll(() async {
    final probe = await http.post(
      Uri.parse('$liveHost/Users/AuthenticateByName'),
      headers: {
        'Authorization': 'MediaBrowser Client="ChudderLive", Device="setup", DeviceId="live-setup", Version="1"',
        'Content-Type': 'application/json',
      },
      body: json.encode({'Username': 'demo', 'Pw': 'demo'}),
    );
    final auth = json.decode(probe.body) as Map<String, dynamic>;
    final headers = {'Authorization': 'MediaBrowser Token="${auth['AccessToken']}"'};
    final userId = (auth['User'] as Map<String, dynamic>)['Id'];
    final shows = json.decode((await http.get(
      Uri.parse('$liveHost/Users/$userId/Items?IncludeItemTypes=Series&Recursive=true&SortBy=SortName&Limit=1'),
      headers: headers,
    ))
        .body) as Map<String, dynamic>;
    seriesId = (shows['Items'] as List).first['Id'] as String;
    final list = json.decode((await http.get(
      Uri.parse('$liveHost/Shows/$seriesId/Episodes?UserId=$userId'),
      headers: headers,
    ))
        .body) as Map<String, dynamic>;
    final items = (list['Items'] as List).cast<Map<String, dynamic>>();
    episodes = [for (final e in items) e['Id'] as String];
    lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 36000000000) ~/ 10)
    };
    // ignore: avoid_print
    print('show $seriesId: ${episodes.length} episodes, first ${lengths[episodes.first]}');
  });

  setUp(() async {
    trace.clear();
    a = await Member.create('A', lengths);
    b = await Member.create('B', lengths);
  });

  tearDown(() async {
    // ignore: avoid_print
    File('live_trace.txt').writeAsStringSync('${trace.join('\n')}\n\n', mode: FileMode.append);
    await a.dispose();
    await b.dispose();
  });

  Future<EpisodeModel> episode(Member m, int index) async {
    final response = await m.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: episodes[index]);
    return response.body! as EpisodeModel;
  }

  /// A group with both members in it, playing [index] at [from].
  Future<void> running(int index, Duration from) async {
    await a.sync.createGroup('live');
    expect(await until(() => a.group.isInGroup), isTrue, reason: 'A in the group');
    final groupId = a.group.groupId!;
    await a.sync.setNewQueue(
      itemIds: episodes,
      playingItemPosition: index,
      startPositionTicks: from.inMicroseconds * 10,
    );
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing), isTrue, reason: 'A alone playing');
    expect(await b.sync.joinGroup(groupId), isTrue, reason: 'B joins');
    expect(await until(() => b.sim.running && a.sim.running, seconds: 8), isTrue, reason: 'both running');
    await wait(3);
  }

  test('a group made while a film plays starts at once, where it is', () async {
    await a.playSolo(await episode(a, 0), const Duration(seconds: 60));
    final before = a.sim.position;
    final started = DateTime.now();
    await a.sync.createGroup('live');
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 6), isTrue,
        reason: 'waited on its own creator');
    final took = DateTime.now().difference(started);
    expect(took, lessThan(const Duration(seconds: 4)));
    expect(a.group.playingItemId, episodes[0]);
    expect(await until(() => a.sim.running, seconds: 3), isTrue);
    await wait(2);
    final moved = a.sim.position - before;
    // ignore: avoid_print
    print('created in ${took.inMilliseconds} ms; position moved $moved over ${DateTime.now().difference(started)}');
    expect(moved, greaterThan(Duration.zero), reason: 'jumped back');
    expect(moved, lessThan(const Duration(seconds: 12)), reason: 'jumped forward');
  });

  test('a group made while paused stays paused, and is not left waiting', () async {
    await a.playSolo(await episode(a, 0), const Duration(seconds: 60));
    await a.sim.pause();
    await wait(0.3);
    await a.sync.createGroup('live');
    expect(await until(() => a.group.groupState == SyncPlayGroupState.paused, seconds: 6), isTrue);
    await wait(2);
    expect(a.sim.running, isFalse);
  });

  test('a joiner loads the same item and lands in step', () async {
    await running(1, const Duration(seconds: 100));
    expect(b.group.playingItemId, a.group.playingItemId);
    final gap = apart(a, b);
    // ignore: avoid_print
    print('apart after join: $gap ms');
    expect(gap, lessThan(400));
  });

  test('pause during a wait stops the picture at once and nothing jumps', () async {
    await a.playSolo(await episode(a, 0), const Duration(seconds: 60));
    await a.sync.createGroup('live');
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 6), isTrue);
    expect(await until(() => a.sim.running, seconds: 3), isTrue);
    b.sim.loadTime = const Duration(seconds: 6);
    final join = b.sync.joinGroup(a.group.groupId!);
    expect(await until(() => a.group.groupState == SyncPlayGroupState.waiting || a.group.participants.length > 1), isTrue);
    await wait(0.4);
    await a.player.userPause();
    final at = a.sim.position;
    expect(a.sim.running, isFalse, reason: 'ran on through the wait');
    await join;
    await until(() => a.group.groupState == SyncPlayGroupState.paused, seconds: 10);
    await wait(1);
    expect((a.sim.position - at).inMilliseconds.abs(), lessThan(1100), reason: 'pulled somewhere else');
  });

  test('a seek settles the group in a second with one Seek per member', () async {
    await running(1, const Duration(seconds: 100));
    trace.clear();
    final started = DateTime.now();
    await b.player.userSeek(const Duration(seconds: 400));
    expect(await until(() => a.sim.position > const Duration(seconds: 399) && a.sim.running && b.sim.running, seconds: 6),
        isTrue);
    final took = DateTime.now().difference(started);
    await wait(1);
    final seeks = trace.where((l) => l.contains('Received SyncPlayCommand: Seek')).length;
    final overtaken = trace.where((l) => l.contains('Ignoring duplicate command: Seek') || l.contains('the Seek again')).length;
    // ignore: avoid_print
    print('seek settled in ${took.inMilliseconds} ms; $seeks Seek frames, $overtaken refused; apart ${apart(a, b)} ms');
    expect(seeks, 2, reason: 'one each; more means a Ready was refused');
    expect(took, lessThan(const Duration(seconds: 3)));
    expect(apart(a, b), lessThan(400));
  });

  test('a run of seeks ends with one Ready', () async {
    await running(1, const Duration(seconds: 100));
    trace.clear();
    for (final to in [200, 230, 260]) {
      await a.player.userSeek(Duration(seconds: to));
      await wait(0.08);
    }
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 6), isTrue);
    await wait(2);
    expect(apart(a, b), lessThan(400));
    expect(a.sim.position, greaterThan(const Duration(seconds: 260)));
  });

  test('the end of a file moves the group on, once', () async {
    final length = lengths[episodes[1]]!;
    await running(1, length - const Duration(seconds: 8));
    trace.clear();
    expect(await until(() => a.group.playingItemId == episodes[2], seconds: 18), isTrue, reason: 'stuck at the end');
    expect(await until(() => a.sim.running && b.sim.running, seconds: 8), isTrue, reason: 'next episode did not start');
    await wait(2);
    final steps = trace.where((l) => l.contains('PlayQueue update') && l.contains('reason: NextItem')).length;
    // ignore: avoid_print
    print('stepped: $steps NextItem frames across both; apart ${apart(a, b)} ms');
    expect(steps, 2, reason: 'one per member; more means it stepped twice');
    expect(a.model?.item.id, episodes[2]);
    expect(b.model?.item.id, episodes[2]);
  });

  test('the end of the queue stops there, with nothing new started', () async {
    final last = episodes.length - 1;
    final length = lengths[episodes[last]]!;
    await running(last, length - const Duration(seconds: 5));
    await wait(14);
    expect(a.group.playingItemId, episodes[last]);
    expect(b.group.playingItemId, episodes[last]);
    expect(trace.where((l) => l.contains('Setting new queue')).length, 1, reason: 'only the one that started it');
  });

  test('a step from a member is followed by the other', () async {
    await running(1, const Duration(seconds: 100));
    final next = a.model!.nextVideo!;
    final started = DateTime.now();
    await a.helper.loadNewVideo(next, finishedCurrent: false);
    expect(await until(() => a.sim.running && b.sim.running && b.model?.item.id == episodes[2], seconds: 8), isTrue);
    // ignore: avoid_print
    print('stepped together in ${DateTime.now().difference(started).inMilliseconds} ms');
  });

  test('a stall holds the group and the group resumes in step', () async {
    await running(1, const Duration(seconds: 100));
    trace.clear();
    b.sim.stall(const Duration(seconds: 4));
    expect(await until(() => a.group.groupState == SyncPlayGroupState.waiting, seconds: 3), isTrue, reason: 'nobody told');
    expect(await until(() => !a.sim.running, seconds: 2), isTrue, reason: 'A played on');
    final held = DateTime.now();
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 10), isTrue, reason: 'held on');
    final took = DateTime.now().difference(held);
    expect(await until(() => a.sim.running, seconds: 3), isTrue);
    await wait(8);
    // ignore: avoid_print
    print('held ${took.inMilliseconds} ms for a 4 s stall; apart ${apart(a, b)} ms after settling');
    expect(took, lessThan(const Duration(seconds: 7)), reason: 'the Ready after the stall went missing');
    expect(apart(a, b), lessThan(400));
  });

  test('a stall right after a resume still reaches the group', () async {
    await running(1, const Duration(seconds: 100));
    await a.player.userPause();
    expect(await until(() => b.group.groupState == SyncPlayGroupState.paused), isTrue);
    await wait(0.5);
    await a.player.userPlay();
    expect(await until(() => b.sim.running, seconds: 3), isTrue);
    b.sim.stall(const Duration(seconds: 5));
    expect(await until(() => a.group.groupState == SyncPlayGroupState.waiting, seconds: 4), isTrue, reason: 'went unreported');
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 10), isTrue);
    await wait(8);
    expect(apart(a, b), lessThan(400));
  });

  test('a lone episode and a show reach the group as a queue', () async {
    await a.sync.createGroup('live');
    expect(await until(() => a.group.isInGroup), isTrue);
    await a.sync.setNewQueue(itemIds: [episodes[1]]);
    expect(await until(() => a.group.playingItemId == episodes[1], seconds: 5), isTrue);
    expect(a.sync.groupQueue.length, episodes.length);
    await wait(1);
    await a.sync.setNewQueue(itemIds: [seriesId]);
    expect(await until(() => a.sync.groupQueue.itemIds.contains(a.group.playingItemId), seconds: 5), isTrue);
    expect(episodes, contains(a.group.playingItemId), reason: 'a show as the playing item');
  });
}

// The app's own LibMPV, silent, on real footage. Run with HEADLESS_SYNCPLAY,
// HEADLESS_MPV and HEADLESS_LIBMPV defined.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'live_harness.dart';

const bigBuckBunny = '539919504441e564fe9563205e5bb302';
const elephantsDream = '958e77cce70d3615c7844c09fc7c4e64';
const granDillama = '2c0f4fe4fe2e95fe86a2dca6a634f407';

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

Future<bool> until(bool Function() what, {num seconds = 10}) async {
  final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(end)) {
    if (what()) return true;
    await wait(0.01);
  }
  return what();
}

final trace = <String>[];

int count(String what) => trace.where((l) => l.contains(what)).length;

// ignore: avoid_print
void say(String text) => print(text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  MediaControlsWrapper.useSystemMediaSession = false;
  HttpOverrides.global = null;
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  SharedPreferences.setMockInitialValues({});
  stubConnectivity();
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

  late String token;
  late Map<String, Duration> lengths;

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
    token = auth['AccessToken'] as String;
    lengths = {};
    for (final id in [bigBuckBunny, elephantsDream, granDillama]) {
      final item = json.decode((await http.get(
        Uri.parse('$liveHost/Users/${(auth['User'] as Map)['Id']}/Items/$id'),
        headers: {'Authorization': 'MediaBrowser Token="$token"'},
      ))
          .body) as Map<String, dynamic>;
      lengths[id] = Duration(microseconds: (item['RunTimeTicks'] as int) ~/ 10);
    }
  });

  setUp(trace.clear);

  String url(String id) => '$liveHost/Videos/$id/stream?Static=true&mediaSourceId=$id&ApiKey=$token';

  Future<double> pos(RealMpv m) async => double.tryParse(await m.headlessProperty('time-pos')) ?? -1;

  String sumUp(List<int> ms) {
    if (ms.isEmpty) return 'none';
    final s = [...ms]..sort();
    return '${s.first}/${s[s.length ~/ 2]}/${s.last} ms (min/median/max, n=${s.length})';
  }

  test('what real mpv does, in numbers', () async {
    final a = await Member.create('A', lengths);
    final m = a.sim as RealMpv;
    say('silence: ${await m.headlessProperty('ao')} / ${await m.headlessProperty('vo')} / mute ${await m.headlessProperty('mute')}');
    final runtime = lengths[bigBuckBunny]!;

    // Load, paused, part way in.
    final loads = <int>[], playable = <int>[];
    for (final at in [120, 260, 400]) {
      final t = Stopwatch()..start();
      await m.loadVideo(url(bigBuckBunny), false, startPosition: Duration(seconds: at));
      loads.add(t.elapsedMilliseconds);
      await m.waitUntilPlayable();
      playable.add(t.elapsedMilliseconds);
      await wait(1);
      await m.pause();
    }
    say('loadVideo returns: ${sumUp(loads)}; playable: ${sumUp(playable)}');
    say('in use after load: ${await m.silenceInUse()}');
    say('duration: mpv ${await m.headlessProperty('duration')} s, server ${runtime.inMilliseconds / 1000} s');

    // Start latency: told to play until time-pos moves, and until the state does.
    m.instantTransport = true;
    final moved = <int>[], stateMoved = <int>[];
    for (var i = 0; i < 6; i++) {
      await m.pause();
      await wait(0.7);
      final before = await pos(m);
      final stateBefore = m.lastState.position;
      final t = Stopwatch()..start();
      await m.play();
      final seen = until(() => m.lastState.position != stateBefore, seconds: 2).then((_) => stateMoved.add(t.elapsedMilliseconds));
      while ((await pos(m)) <= before + 0.001 && t.elapsedMilliseconds < 2000) {}
      moved.add(t.elapsedMilliseconds);
      await seen;
      await wait(0.5);
    }
    say('start: state moved ${sumUp(stateMoved)}; time-pos moved ${sumUp(moved)}');

    // How often the state's position changes, and how far behind time-pos.
    final gaps = <int>[], behind = <int>[];
    var last = m.lastState.position;
    var lastAt = DateTime.now();
    final sub = m.stateStream.listen((s) {
      if (s.position != last) {
        last = s.position;
        final now = DateTime.now();
        gaps.add(now.difference(lastAt).inMilliseconds);
        lastAt = now;
      }
    });
    for (var i = 0; i < 40; i++) {
      final mine = m.lastState.position;
      final real = await pos(m);
      behind.add(((real * 1000) - mine.inMilliseconds).round());
      await wait(0.1);
    }
    await sub.cancel();
    say('position events every ${sumUp(gaps.sublist(1))}; time-pos ahead of state by ${sumUp(behind)}');

    // Seek inside what is cached, and out of it, running and paused.
    Future<void> seekRun(String label, Duration Function(int i) to, {required bool paused}) async {
      final calls = <int>[], landed = <int>[], flagUp = <int>[], flagDown = <int>[];
      for (var i = 0; i < 5; i++) {
        if (paused) {
          await m.pause();
        } else {
          await m.play();
        }
        await wait(1.5);
        final target = to(i);
        final t = Stopwatch()..start();
        int? up, down;
        final sub = m.stateStream.listen((s) {
          if (s.buffering && up == null) up = t.elapsedMilliseconds;
          if (!s.buffering && up != null && down == null) down = t.elapsedMilliseconds;
        });
        await m.seek(target);
        calls.add(t.elapsedMilliseconds);
        while (t.elapsedMilliseconds < 4000) {
          final p = await pos(m);
          if ((p - target.inMilliseconds / 1000).abs() < 1 && await m.headlessProperty('seeking') == 'no') break;
        }
        landed.add(t.elapsedMilliseconds);
        await wait(0.8);
        await sub.cancel();
        if (up != null) flagUp.add(up!);
        if (down != null) flagDown.add(down!);
      }
      say('seek $label: call returns ${sumUp(calls)}; landed ${sumUp(landed)}; '
          'buffering up ${sumUp(flagUp)}; down ${sumUp(flagDown)}');
    }

    await seekRun('running, in cache', (i) => m.lastState.position - const Duration(seconds: 1), paused: false);
    await seekRun('running, out of cache', (i) => Duration(seconds: 40 + 90 * i), paused: false);
    await seekRun('paused, in cache', (i) => m.lastState.position - const Duration(seconds: 1), paused: true);
    await seekRun('paused, out of cache', (i) => Duration(seconds: 80 + 90 * i), paused: true);

    // The end, as mpv has it.
    for (final id in [bigBuckBunny, granDillama]) {
      await m.loadVideo(url(id), false, startPosition: lengths[id]! - const Duration(seconds: 5));
      await m.waitUntilPlayable();
      await m.play();
      final log = <String>[];
      final t = Stopwatch()..start();
      String? last;
      final sub = m.stateStream.listen((s) {
        final line = 'playing=${s.playing} buffering=${s.buffering} completed=${s.completed}';
        if (line != last) {
          last = line;
          log.add('${t.elapsedMilliseconds}ms @${s.position.inMilliseconds / 1000}: $line');
        }
      });
      await until(() => m.lastState.completed, seconds: 12);
      final endAt = t.elapsedMilliseconds;
      await wait(2);
      await sub.cancel();
      say('EOF of $id: runtime ${lengths[id]!.inMilliseconds / 1000}, mpv duration ${await m.headlessProperty('duration')}, '
          'final state ${m.lastState.position.inMilliseconds / 1000}, time-pos ${await m.headlessProperty('time-pos')}, '
          'eof-reached ${await m.headlessProperty('eof-reached')}, core-idle ${await m.headlessProperty('core-idle')}, '
          'pause ${await m.headlessProperty('pause')}, completed after ${endAt}ms');
      for (final l in log) {
        say('   $l');
      }
    }

    // Asked to seek past the end while paused.
    await m.pause();
    await wait(0.3);
    await m.seek(lengths[granDillama]! + const Duration(seconds: 2));
    await wait(1.5);
    say('seek past end: state ${m.lastState.position.inMilliseconds / 1000} buffering=${m.lastState.buffering} '
        'completed=${m.lastState.completed} time-pos ${await m.headlessProperty('time-pos')}');
    await a.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  /// Two members, a queue of real films, both running.
  Future<(Member, Member)> running({Duration from = const Duration(seconds: 60)}) async {
    final a = await Member.create('A', lengths);
    final b = await Member.create('B', lengths);
    await a.sync.createGroup('mpv');
    expect(await until(() => a.group.isInGroup), isTrue);
    final groupId = a.group.groupId!;
    await a.sync.setNewQueue(
      itemIds: [bigBuckBunny, elephantsDream, granDillama],
      startPositionTicks: from.inMicroseconds * 10,
    );
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 10), isTrue, reason: 'A alone');
    expect(await b.sync.joinGroup(groupId), isTrue);
    expect(await until(() => b.sim.running && a.sim.running, seconds: 12), isTrue, reason: 'both running');
    await wait(4);
    return (a, b);
  }

  Future<void> done(Member a, Member b) async {
    await a.dispose();
    await b.dispose();
  }

  double apart(Member a, Member b) => (a.sim.position - b.sim.position).inMilliseconds.abs().toDouble();

  void seekStats(String label, DateTime started) {
    say('$label: ${DateTime.now().difference(started).inMilliseconds} ms; Seek frames ${count('Received SyncPlayCommand: Seek')}, '
        'Pause frames ${count('Received SyncPlayCommand: Pause')}, Ready ${count('Reporting Ready')}, '
        'refused ${count('the Seek again')}, duplicates ${count('Ignoring duplicate command: Seek')}, '
        'overtaken ${count('overtaken')}');
  }

  test('one seek out of the cache, on real footage', () async {
    final (a, b) = await running();
    trace.clear();
    final started = DateTime.now();
    await b.player.userSeek(const Duration(seconds: 300));
    await until(() => a.sim.position > const Duration(seconds: 299) && a.sim.running && b.sim.running, seconds: 8);
    seekStats('one seek', started);
    await wait(2);
    say('apart ${apart(a, b)} ms');
    await File('storm1_trace.txt').writeAsString('${trace.join('\n')}\n');
    await done(a, b);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('two seeks 100 ms apart, as on the night', () async {
    final (a, b) = await running();
    trace.clear();
    final started = DateTime.now();
    await b.player.userSeek(const Duration(seconds: 300));
    await wait(0.1);
    await b.player.userSeek(const Duration(seconds: 333));
    await until(() => a.sim.position > const Duration(seconds: 332) && a.sim.running && b.sim.running, seconds: 8);
    seekStats('two seeks', started);
    await wait(2);
    say('apart ${apart(a, b)} ms');
    await File('storm2_trace.txt').writeAsString('${trace.join('\n')}\n');
    await done(a, b);
  }, timeout: const Timeout(Duration(minutes: 2)));

  Future<void> stallRun({required bool pausedSinceJoin}) async {
    final proxy = await StreamProxy.start();
    final (a, b) = await running(from: const Duration(seconds: 200));
    final mine = b.sim as RealMpv;
    if (pausedSinceJoin) {
      await a.player.userPause();
      await until(() => b.group.groupState == SyncPlayGroupState.paused);
      await wait(0.5);
      await a.player.userPlay();
      await until(() => a.sim.running && b.sim.running);
    }
    await wait(3);
    await File('stall_join_$pausedSinceJoin.txt').writeAsString(trace.join(String.fromCharCode(10)));
    say('before the stall, B: processing=${b.group.isProcessingCommand} type=${b.group.processingCommandType} '
        'groupState=${b.group.groupState.name} playerIsBuffering=${b.group.correctionState.playerIsBuffering} '
        'lastCommand=${b.group.lastCommandTime}');
    trace.clear();
    final who = b.container.read(userProvider)!.credentials.deviceId;
    final frozen = DateTime.now();
    proxy.freeze(who);
    final ran = await until(() => mine.reportsBuffering, seconds: 40);
    final dry = DateTime.now().difference(frozen);
    say('[pausedSinceJoin=$pausedSinceJoin] froze the stream: buffering=$ran after ${dry.inMilliseconds} ms');
    final told = await until(() => a.group.groupState == SyncPlayGroupState.waiting, seconds: 4);
    final hold = DateTime.now();
    say('group told: $told, ${hold.difference(frozen).inMilliseconds - dry.inMilliseconds} ms after mpv ran dry; A running ${a.sim.running}');
    say('at that point, B: processing=${b.group.isProcessingCommand} type=${b.group.processingCommandType} '
        'strategy=${b.group.correctionState.activeStrategy.name}; sent Buffering ${count('Reporting Buffering')}');
    await wait(3);
    final aheadWhile = apart(a, b);
    proxy.thaw(who);
    final out = await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 15);
    say('released: $out, hold ${DateTime.now().difference(hold).inMilliseconds} ms; apart during the freeze $aheadWhile ms');
    await wait(10);
    say('apart after settling ${apart(a, b)} ms; Ready ${count('Reporting Ready')}, watchdog ${count('still waiting')}, '
        'Buffer states ${count('Waiting (reason: Buffer')}, SkipToSync ${count('SkipToSync applied')}, SpeedToSync ${count('SpeedToSync applied')}');
    await File('stall_trace_$pausedSinceJoin.txt').writeAsString(trace.join(String.fromCharCode(10)));
    await done(a, b);
    await proxy.stop();
  }

  test('a real stall after a pause', () => stallRun(pausedSinceJoin: true), timeout: const Timeout(Duration(minutes: 3)));

  test('a real stall right after a join', () => stallRun(pausedSinceJoin: false), timeout: const Timeout(Duration(minutes: 3)));

  test('a queue handed to a player already on that item', () async {
    final a = await Member.create('A', lengths);
    final item = (await a.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: granDillama)).body!;
    await a.playSolo(item, lengths[granDillama]! - const Duration(seconds: 40));
    await a.sync.createGroup('mpv');
    expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 8), isTrue);
    await wait(1.5);
    await a.sync.setNewQueue(
      itemIds: [bigBuckBunny, granDillama, elephantsDream],
      playingItemPosition: 1,
      startPositionTicks: (lengths[granDillama]! - const Duration(seconds: 12)).inMicroseconds * 10,
    );
    await until(() => a.group.playingItemId == granDillama && a.sync.groupQueue.length == 3, seconds: 5);
    await wait(3);
    say('queue here ${a.model?.queue.length} items, next here ${a.model?.nextVideo?.id}, '
        'next in the group ${a.sync.nextQueuedItemId}');
    final stepped = await until(() => a.group.playingItemId == elephantsDream, seconds: 20);
    say('stepped at the end: $stepped; position ${a.sim.position}; on ${a.group.playingItemId}');
    await File('adopt_trace.txt').writeAsString(trace.join(String.fromCharCode(10)));
    await a.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the end of a real file moves the group on', () async {
    final length = lengths[bigBuckBunny]!;
    final (a, b) = await running(from: length - const Duration(seconds: 12));
    trace.clear();
    final ok = await until(() => a.group.playingItemId == elephantsDream, seconds: 25);
    final both = await until(() => a.sim.running && b.sim.running, seconds: 10);
    await wait(3);
    say('stepped=$ok both running=$both; NextItem frames ${count('reason: NextItem')}; '
        'requests ${count('Sending NextItem')}; apart ${apart(a, b)} ms; same item ${a.model?.item.id == b.model?.item.id}');
    await File('eof_trace.txt').writeAsString('${trace.join('\n')}\n');
    await done(a, b);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

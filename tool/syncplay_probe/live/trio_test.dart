// Two Chudders and a real jellyfin-web in one group: arriving late, leaving and
// coming back in each state, a group Stop from every angle, and two people
// acting at once. Judges itself at each check. WEB_DIR as in web_test.dart;
// LINK_MS and LINK_JITTER_MS put both Chudders on a bad connection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'chaos_proxy.dart';
import 'live_harness.dart';

const webDir = String.fromEnvironment('WEB_DIR');
const linkMs = int.fromEnvironment('LINK_MS');
const linkJitter = int.fromEnvironment('LINK_JITTER_MS');

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

/// What the page's video was last seen doing, or null when it has none.
Map<String, dynamic>? webVideo() {
  for (final line in File('$webDir/web_log.txt').readAsLinesSync().reversed.take(60)) {
    final at = line.indexOf(' VIDEO ');
    if (at < 0) continue;
    final text = line.substring(at + 7).trim();
    return text == 'none' ? null : json.decode(text) as Map<String, dynamic>;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  MediaControlsWrapper.useSystemMediaSession = false;
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
  final trace = File('$webDir/chudder_trace.txt').openWrite();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync') && !r.message.contains('Received WebSocket')) {
      trace.writeln('${r.time.millisecondsSinceEpoch / 1000} ${r.message}');
    }
  });

  test('two Chudders and web', () async {
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
    final items = await footage(headers, userId);
    final episodes = [for (final e in items) e['Id'] as String];
    final lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 0) ~/ 10)
    };

    final bad = linkMs > 0 || linkJitter > 0;
    final pa = ChaosProxy(liveHost, baseMs: linkMs, jitterMs: linkJitter);
    final pb = ChaosProxy(liveHost, baseMs: linkMs, jitterMs: linkJitter, seed: 2);
    if (bad) {
      await pa.start();
      await pb.start();
    }
    final a = await Member.create('A', lengths, host: bad ? pa.url : liveHost);
    final b = await Member.create('B', lengths, host: bad ? pb.url : liveHost);
    a.sim.fileOverrun = Duration.zero;
    b.sim.fileOverrun = Duration.zero;
    final tolerance = 1.0 + (linkMs + linkJitter) / 1000;

    final results = File('$webDir/chudder_log.txt').openWrite();
    final failures = <String>[];
    void note(String text) {
      results.writeln(text);
      // ignore: avoid_print
      print(text);
    }

    late String id;
    Future<String> serverState() async {
      final r = await http.get(Uri.parse('$liveHost/SyncPlay/$id'), headers: headers);
      return r.statusCode == 200 ? '${(json.decode(r.body) as Map<String, dynamic>)['State']}' : 'gone';
    }

    /// [want] is the group's state, or * for whatever two people acting at
    /// once came to; a group that went idle has nobody's player open.
    Future<void> check(String name, String want, {List<Member>? on, bool webOn = true}) async {
      final server = await serverState();
      final problems = <String>[];
      final idle = server.toLowerCase() == 'idle';
      final members = idle ? const <Member>[] : on ?? [a, b];
      final shut = idle ? [a, b] : [for (final m in [a, b]) if (!members.contains(m)) m];
      final video = webVideo();
      final gaps = <String>[];
      if (want != '*' && want.toLowerCase() != server.toLowerCase()) problems.add('want $want, server $server');
      if (server.toLowerCase() == 'waiting') problems.add('still waiting');
      for (final m in members) {
        if (m.group.groupState.name.toLowerCase() != server.toLowerCase()) {
          problems.add('${m.name} says ${m.group.groupState.name}');
        }
        if (m.sim.running != (server.toLowerCase() == 'playing')) problems.add('${m.name} running=${m.sim.running}');
        if (m.model?.item.id != m.group.playingItemId) problems.add('${m.name} on ${m.model?.item.id} of ${m.group.playingItemId}');
      }
      for (final m in shut.where((m) => idle || m.group.isInGroup)) {
        if (idle && m.sim.running) problems.add('${m.name} still running in a stopped group');
      }
      if (members.length == 2) {
        final gap = (a.sim.position - b.sim.position).inMilliseconds / 1000;
        gaps.add('A-B ${gap.toStringAsFixed(2)}');
        if (gap.abs() > tolerance) problems.add('A and B ${gap.toStringAsFixed(2)} s apart');
        if (a.model?.item.id != b.model?.item.id) problems.add('A and B on different items');
      }
      if (webOn && !idle) {
        if (video == null) {
          problems.add('web has no video');
        } else if (members.isNotEmpty) {
          final m = members.first;
          final gap = m.sim.position.inMilliseconds / 1000 - (video['t'] as num);
          gaps.add('${m.name}-web ${gap.toStringAsFixed(2)}');
          if (gap.abs() > tolerance) problems.add('${m.name} and web ${gap.toStringAsFixed(2)} s apart');
          if (video['s'] != m.model?.item.id) problems.add('web on another item');
          if ((video['p'] != true) != (server.toLowerCase() == 'playing')) problems.add('web paused=${video['p']}');
        }
      }
      if (idle && video != null && video['p'] != true) problems.add('web still running in a stopped group');
      note('${problems.isEmpty ? 'ok  ' : 'FAIL'} $name: $server ${gaps.join(' ')} ${problems.isEmpty ? '' : problems}');
      if (problems.isNotEmpty) failures.add('$name: $problems');
    }

    void web(String command) => File('$webDir/cmd.txt').writeAsStringSync(command);
    Future<void> webSays(String command) async {
      web(command);
      await wait(1);
    }

    Future<void> webReload() async {
      await webSays('Leave');
      web('JS location.reload()');
      await wait(7);
    }

    Future<void> webJoin() async {
      web('Join ${json.encode({'GroupId': id})}');
      await wait(10);
    }

    void webSeek(Duration to) => web('Seek ${json.encode({'PositionTicks': to.inMicroseconds * 10})}');

    Future<void> webPlays(String item) async {
      final all = json.decode((await http.get(Uri.parse('$liveHost/Sessions'), headers: headers)).body) as List;
      final mine = all.cast<Map<String, dynamic>>().where((s) => (s['DeviceId'] as String).startsWith('web-probe')).toList()
        ..sort((x, y) => (y['LastActivityDate'] as String).compareTo(x['LastActivityDate'] as String));
      await http.post(
        Uri.parse('$liveHost/Sessions/${mine.first['Id']}/Playing?playCommand=PlayNow&itemIds=$item'),
        headers: headers,
      );
    }

    Future<void> leave(Member m) async {
      if (m.group.isInGroup) await m.sync.leaveGroup();
      await m.container.read(videoPlayerProvider).stop();
      m.container.read(playBackModel.notifier).state = null;
    }

    Future<void> part() async {
      await leave(a);
      await leave(b);
      await webReload();
    }

    Future<dynamic> solo(int index) async =>
        (await a.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: episodes[index])).body!;

    Future<void> queueFrom(Member m, int index) async {
      await m.sync.setNewQueue(itemIds: episodes.take(8).toList(), playingItemPosition: index, startPositionTicks: 600000000);
      await wait(12);
    }

    /// A hosting with [playFor] seconds of play behind it, web and B in.
    Future<void> everyoneIn({num playFor = 3}) async {
      await a.sync.createGroup('trio-${DateTime.now().millisecondsSinceEpoch}');
      await wait(1);
      id = a.group.groupId!;
      await queueFrom(a, 2);
      await wait(playFor);
      await webJoin();
      await b.sync.joinGroup(id);
      await wait(10);
    }

    // 1. Arriving late, one by one, then everyone doing everything once.
    note('PHASE arrivals');
    await a.playSolo(await solo(3), const Duration(seconds: 120));
    await a.sync.createGroup('trio-solo');
    await wait(1);
    id = a.group.groupId!;
    await wait(20);
    await webJoin();
    await check('web joins a playing Chudder', 'Playing', on: [a]);
    await b.sync.joinGroup(id);
    await wait(10);
    await check('second Chudder joins web and Chudder', 'Playing');

    web('Pause');
    await wait(4);
    await check('web pauses both', 'Paused');
    await b.player.userPlay();
    await wait(6);
    await check('Chudder resumes web and Chudder', 'Playing');
    await a.player.userPause();
    await wait(4);
    await check('Chudder pauses web and Chudder', 'Paused');
    web('Unpause');
    await wait(6);
    await check('web resumes both', 'Playing');
    await a.player.userSeek(const Duration(seconds: 400));
    await wait(8);
    await check('Chudder seeks', 'Playing');
    webSeek(const Duration(seconds: 550));
    await wait(8);
    await check('web seeks', 'Playing');
    await b.player.userSeek(const Duration(seconds: 200));
    await wait(8);
    await check('other Chudder seeks', 'Playing');
    await a.player.userPause();
    await wait(3);
    await a.player.userSeek(const Duration(seconds: 500));
    await wait(34);
    await check('seek while paused, after web\'s hold', 'Paused');
    await b.player.userPlay();
    await wait(6);
    await check('play after a paused seek', 'Playing');

    await queueFrom(b, 2);
    await check('Chudder gives the group a queue', 'Playing');
    await a.helper.loadNewVideo(a.model!.nextVideo!);
    await wait(10);
    await check('Chudder next', 'Playing');
    web('NextItem ${json.encode({'PlaylistItemId': a.group.playlistItemId})}');
    await wait(10);
    await check('web next', 'Playing');
    await b.helper.loadNewVideo(b.model!.previousVideo!);
    await wait(10);
    await check('Chudder previous', 'Playing');
    await part();

    // 2. Going and coming back, in each state.
    note('PHASE partings');
    await everyoneIn();
    await check('everyone in', 'Playing');
    b.container.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    unawaited(b.container.read(videoPlayerProvider).stop());
    await wait(6);
    await check('Chudder closes its player, the rest go on', 'Playing', on: [a]);
    await a.player.userPause();
    await wait(4);
    await a.player.userPlay();
    await wait(6);
    await check('pause and play with a closed member', 'Playing', on: [a]);
    b.container.read(isVideoPlayerRouteOpenProvider.notifier).state = true;
    await b.sync.rejoinPlayback();
    await wait(12);
    await check('Chudder reopens its player', 'Playing');
    await a.player.userPause();
    await wait(3);
    b.container.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
    unawaited(b.container.read(videoPlayerProvider).stop());
    await wait(5);
    b.container.read(isVideoPlayerRouteOpenProvider.notifier).state = true;
    await b.sync.rejoinPlayback();
    await wait(12);
    await check('close and reopen while paused', 'Paused');
    await a.player.userPlay();
    await wait(6);
    await check('play after that', 'Playing');

    await leave(b);
    await wait(5);
    await check('Chudder leaves, the rest go on', 'Playing', on: [a]);
    await b.sync.joinGroup(id);
    await wait(10);
    await check('it joins again, playing', 'Playing');
    await a.player.userPause();
    await wait(3);
    await leave(b);
    await wait(3);
    await b.sync.joinGroup(id);
    await wait(10);
    await check('leave and join while paused', 'Paused');
    await b.player.userPlay();
    await wait(6);
    await check('the one who came back resumes', 'Playing');

    await webReload();
    await wait(4);
    await check('web leaves, Chudders go on', 'Playing', webOn: false);
    await a.player.userPause();
    await wait(3);
    await a.player.userPlay();
    await wait(5);
    await check('Chudders pause and play without web', 'Playing', webOn: false);
    await webJoin();
    await check('web comes back', 'Playing');

    await leave(a);
    await wait(5);
    await check('the host leaves, the rest go on', 'Playing', on: [b]);
    web('Pause');
    await wait(3);
    await b.player.userPlay();
    await wait(6);
    await check('pause and play after the host left', 'Playing', on: [b]);
    await a.sync.joinGroup(id);
    await wait(10);
    await check('the host comes back as a member', 'Playing');
    await part();

    // 3. A group Stop. Only web has a button for it.
    note('PHASE stops');
    await everyoneIn();
    await check('everyone in', 'Playing');
    web('Stop');
    await wait(4);
    await check('web stops the group', 'Idle');
    await queueFrom(b, 3);
    await check('Chudder starts after a Stop', 'Playing');
    web('Stop');
    await wait(4);
    await check('stopped again', 'Idle');
    await webPlays(episodes[1]);
    await wait(12);
    await check('web starts after a Stop', 'Playing');
    await a.player.userPause();
    await wait(4);
    web('Stop');
    await wait(4);
    await check('stopped while paused', 'Idle');
    await leave(b);
    await wait(2);
    await b.playSolo(await solo(5), const Duration(seconds: 90));
    await wait(2);
    await b.container.read(videoPlayerProvider).stop();
    b.container.read(playBackModel.notifier).state = null;
    await b.sync.joinGroup(id);
    await wait(6);
    await check('joining a stopped group', 'Idle');
    await queueFrom(a, 4);
    await check('starting after that join', 'Playing');
    await part();

    // 4. Two at once. Nobody can say who wins, only that everyone agrees.
    note('PHASE collisions');
    await everyoneIn();
    unawaited(a.player.userPause());
    web('Pause');
    await wait(5);
    await check('Chudder and web pause together', 'Paused');
    unawaited(a.player.userPlay());
    unawaited(b.player.userPlay());
    web('Unpause');
    await wait(7);
    await check('all three play together', 'Playing');
    unawaited(a.player.userSeek(const Duration(seconds: 300)));
    webSeek(const Duration(seconds: 600));
    await wait(10);
    await check('Chudder and web seek together', 'Playing');
    unawaited(a.player.userPause());
    unawaited(b.player.userSeek(const Duration(seconds: 450)));
    await wait(36);
    await check('a pause meets a seek', '*');
    await a.player.userPlay();
    await wait(7);
    await check('play after that', 'Playing');
    unawaited(a.helper.loadNewVideo(a.model!.nextVideo!));
    webSeek(const Duration(seconds: 200));
    await wait(12);
    await check('next meets a seek', '*');
    await a.player.userPlay();
    await wait(6);
    unawaited(leave(b));
    await a.player.userSeek(const Duration(seconds: 350));
    await wait(10);
    await check('a seek as someone leaves', 'Playing', on: [a]);
    unawaited(b.sync.joinGroup(id));
    await a.player.userSeek(const Duration(seconds: 500));
    await wait(12);
    await check('a seek as someone joins', 'Playing');
    unawaited(a.player.userPause());
    unawaited(leave(b));
    await wait(6);
    unawaited(b.sync.joinGroup(id));
    await a.player.userPlay();
    await wait(12);
    await check('play as someone joins', 'Playing');
    await part();

    note('PHASE stop-collisions');
    await everyoneIn();
    unawaited(a.player.userPause());
    web('Stop');
    await wait(6);
    await check('Stop meets a pause', 'Idle');
    await queueFrom(a, 2);
    unawaited(b.player.userSeek(const Duration(seconds: 300)));
    web('Stop');
    await wait(6);
    await check('Stop meets a seek', 'Idle');
    await queueFrom(b, 3);
    unawaited(leave(b));
    web('Stop');
    await wait(6);
    await check('Stop as someone leaves', 'Idle');
    await queueFrom(a, 2);
    web('Stop');
    await b.sync.joinGroup(id);
    await wait(6);
    await check('Stop as someone joins', '*', on: [a]);
    await wait(1);
    await queueFrom(a, 4);
    await check('starting after those', 'Playing');
    web('Stop');
    await wait(0.1);
    await a.sync.setNewQueue(itemIds: episodes.take(8).toList(), playingItemPosition: 3, startPositionTicks: 300000000);
    await wait(14);
    await check('a start right behind a Stop', '*');
    await part();

    // 5. Web closes its player but stays in the group, which it tells nobody.
    note('PHASE web-closed');
    await everyoneIn();
    web('JS history.back()');
    await wait(8);
    await check('web closes its player', 'Playing', webOn: false);
    await a.player.userSeek(const Duration(seconds: 300));
    await wait(36);
    await check('seek with web closed, after its hold', 'Playing', webOn: false);
    await webPlays(episodes[4]);
    await wait(14);
    await check('web opens something', 'Playing');
    await part();

    // 6. The film runs out with everyone watching: the group goes on together,
    // and after the last of the queue a new start still works.
    note('PHASE endings');
    await everyoneIn();
    await queueFrom(a, 2);
    final ending = a.model!.item.id;
    await a.player.userSeek(lengths[ending]! - const Duration(seconds: 8));
    await wait(28);
    await check('the film ends, everyone goes on', 'Playing');
    if (a.model?.item.id == ending) {
      note('FAIL the group stayed on the film that ended');
      failures.add('the group stayed on the film that ended');
    }
    final last = min(episodes.length, 8) - 1;
    await queueFrom(b, last);
    await a.player.userSeek(lengths[a.model!.item.id]! - const Duration(seconds: 8));
    await wait(20);
    note('end of the queue: server ${await serverState()} A ${a.group.groupState.name} B ${b.group.groupState.name}');
    await queueFrom(b, 2);
    await check('a new queue after the last film ended', 'Playing');
    await part();

    // 7. A member's stream stalls with the others watching. The simulated
    // player only: a real stall goes through StreamProxy in mpv_test.
    if (!useRealMpv) {
      note('PHASE stalls');
      await everyoneIn();
      b.sim.stall(const Duration(seconds: 4));
      await wait(10);
      await check('a stall holds the group and lets go', 'Playing');
      b.sim.stall(const Duration(seconds: 3));
      await a.player.userPause();
      await wait(9);
      await check('a pause during a stall', 'Paused');
      await a.player.userPlay();
      await wait(6);
      b.sim.stall(const Duration(seconds: 3));
      await leave(a);
      await wait(1);
      await a.sync.joinGroup(id);
      await wait(14);
      await check('a join during a stall', 'Playing');
      await part();
    }

    note('${failures.length} failed');
    await results.close();
    await trace.flush();
    await a.dispose();
    await b.dispose();
    if (bad) {
      await pa.stop();
      await pb.stop();
    }
    File('$webDir/stop.txt').writeAsStringSync('');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(minutes: 25)));
}

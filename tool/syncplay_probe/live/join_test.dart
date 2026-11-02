// Joining a group that is already going, with a real jellyfin-web: web hosting
// and Chudder coming in, and the other way round, in each state a group can
// be in and from each thing a member can be doing. Each CHECK line is judged
// by join_check.py; WEB_DIR as in web_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'live_harness.dart';

const webDir = String.fromEnvironment('WEB_DIR');

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

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

  test('joining a group already going', () async {
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

    final a = await Member.create('A', lengths);
    a.sim.fileOverrun = Duration.zero;

    final positions = File('$webDir/chudder_log.txt').openWrite();
    var stop = false;
    var serverState = '?';
    String? groupId;
    () async {
      while (!stop) {
        final now = DateTime.now().millisecondsSinceEpoch / 1000;
        positions.writeln('$now ${a.sim.position.inMilliseconds / 1000} ${a.sim.running} ${a.model?.item.id} '
            '${a.group.groupState.name} server=$serverState');
        await wait(0.1);
      }
    }();
    () async {
      while (!stop) {
        final id = groupId;
        if (id != null) {
          final r = await http.get(Uri.parse('$liveHost/SyncPlay/$id'), headers: headers);
          if (r.statusCode == 200) serverState = '${(json.decode(r.body) as Map<String, dynamic>)['State']}';
        }
        await wait(0.5);
      }
    }();
    void mark(String kind, String name) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      positions.writeln('$now $kind $name');
      // ignore: avoid_print
      print('$kind $now $name | chudder pos=${a.sim.position.inSeconds} running=${a.sim.running} '
          'item=${a.model?.item.id} says=${a.group.groupState.name} inGroup=${a.group.isInGroup} server=$serverState');
    }

    void web(String command) => File('$webDir/cmd.txt').writeAsStringSync(command);
    Future<void> webSays(String command) async {
      web(command);
      await wait(1);
    }

    Future<String?> webSession() async {
      final all = json.decode((await http.get(Uri.parse('$liveHost/Sessions'), headers: headers)).body) as List;
      final mine = all.cast<Map<String, dynamic>>().where((s) => (s['DeviceId'] as String).startsWith('web-probe')).toList()
        ..sort((x, y) => (y['LastActivityDate'] as String).compareTo(x['LastActivityDate'] as String));
      return mine.isEmpty ? null : mine.first['Id'] as String;
    }

    Future<void> webPlays(String item) async {
      final session = await webSession();
      await http.post(
        Uri.parse('$liveHost/Sessions/$session/Playing?playCommand=PlayNow&itemIds=$item'),
        headers: headers,
      );
    }

    Future<String> findGroup(String name) async {
      for (var i = 0; i < 40; i++) {
        final groups = json.decode((await http.get(Uri.parse('$liveHost/SyncPlay/List'), headers: headers)).body) as List;
        for (final g in groups.cast<Map<String, dynamic>>()) {
          if (g['GroupName'] == name) return g['GroupId'] as String;
        }
        await wait(0.25);
      }
      throw StateError('no group $name');
    }

    var round = 0;
    Future<String> webHosts(String item, {num playFor = 20}) async {
      final name = 'web-host-${++round}-${DateTime.now().millisecondsSinceEpoch}';
      web('New ${json.encode({'GroupName': name})}');
      final id = await findGroup(name);
      groupId = id;
      await wait(1);
      await webPlays(item);
      await wait(playFor);
      return id;
    }

    Future<void> part() async {
      if (a.group.isInGroup) await a.sync.leaveGroup();
      await a.container.read(videoPlayerProvider).stop();
      a.container.read(playBackModel.notifier).state = null;
      await webSays('Leave');
      // A fresh page: leaving and joining in one tab doubles web's own
      // listeners, and it then sends Readies twice and Pauses of its own.
      web('JS location.reload()');
      await wait(7);
    }

    Future<dynamic> soloItem(int index) async =>
        (await a.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: episodes[index])).body!;

    // 1. Web has been playing a while; Chudder comes in from nothing.
    mark('PHASE', 'web-hosts-playing-chudder-empty');
    var id = await webHosts(episodes[2]);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Playing join playing, nothing open');
    await a.player.userPause();
    await wait(3);
    mark('CHECK', 'Paused pause after that join');
    await a.player.userPlay();
    await wait(5);
    mark('CHECK', 'Playing play after that join');
    await part();

    // 2. Web playing; Chudder watching something else on its own.
    mark('PHASE', 'web-hosts-playing-chudder-on-other');
    id = await webHosts(episodes[3]);
    await a.playSolo(await soloItem(5), const Duration(seconds: 90));
    await wait(3);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Playing join playing, watching another item');
    await part();

    // 3. Web playing; Chudder already on the same item, elsewhere in it.
    mark('PHASE', 'web-hosts-playing-chudder-same-item');
    id = await webHosts(episodes[2]);
    await a.playSolo(await soloItem(2), const Duration(seconds: 300));
    await wait(3);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Playing join playing, same item elsewhere');
    await part();

    // 4. Web paused; Chudder from nothing and from another item.
    mark('PHASE', 'web-hosts-paused-chudder-empty');
    id = await webHosts(episodes[4]);
    await webSays('Pause');
    await wait(3);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Paused join paused, nothing open');
    await a.player.userPlay();
    await wait(6);
    mark('CHECK', 'Playing play after joining paused');
    await part();

    mark('PHASE', 'web-hosts-paused-chudder-on-other');
    id = await webHosts(episodes[4]);
    await webSays('Pause');
    await a.playSolo(await soloItem(6), const Duration(seconds: 90));
    await wait(3);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Paused join paused, watching another item');
    await webSays('Unpause');
    await wait(6);
    mark('CHECK', 'Playing web plays after joining paused');
    await part();

    // 5. A stopped group, kept by the server with its queue.
    mark('PHASE', 'web-hosts-stopped');
    id = await webHosts(episodes[2], playFor: 8);
    await webSays('Stop');
    await wait(2);
    await a.playSolo(await soloItem(5), const Duration(seconds: 90));
    await wait(2);
    mark('PHASE', 'join');
    await a.sync.joinGroup(id);
    await wait(6);
    mark('CHECK-SOLO', 'join stopped, own film goes on');
    await webPlays(episodes[3]);
    await wait(8);
    mark('CHECK', 'Playing web starts in the group joined stopped');
    await part();

    // 6. Joining at the moment things move.
    mark('PHASE', 'join-during-web-load');
    id = await webHosts(episodes[2], playFor: 8);
    await webPlays(episodes[7]);
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Playing join as web changes item');
    await part();

    mark('PHASE', 'join-during-web-seek');
    id = await webHosts(episodes[2], playFor: 8);
    web('Seek ${json.encode({'PositionTicks': 4000000000})}');
    await a.sync.joinGroup(id);
    await wait(10);
    mark('CHECK', 'Playing join as web seeks');
    await part();

    mark('PHASE', 'web-pauses-as-chudder-joins');
    id = await webHosts(episodes[2], playFor: 8);
    final join = a.sync.joinGroup(id);
    web('Pause');
    await join;
    await wait(10);
    mark('CHECK', 'Paused web pauses during the join');
    await part();

    // 7. Chudder hosts for a while and web comes in late.
    mark('PHASE', 'chudder-hosts-playing');
    await a.playSolo(await soloItem(3), const Duration(seconds: 120));
    await a.sync.createGroup('chudder-host');
    id = a.group.groupId!;
    groupId = id;
    await wait(25);
    mark('PHASE', 'web-joins');
    web('Join ${json.encode({'GroupId': id})}');
    await wait(10);
    mark('CHECK', 'Playing web joins Chudder playing');
    await webSays('Leave');
    web('JS location.reload()');
    await wait(7);
    await a.player.userPause();
    await wait(3);
    mark('PHASE', 'web-joins-paused');
    web('Join ${json.encode({'GroupId': id})}');
    await wait(10);
    mark('CHECK', 'Paused web joins Chudder paused');
    await wait(24);
    mark('CHECK', 'Paused web joins Chudder paused, after the deadline');
    await a.player.userPlay();
    await wait(6);
    mark('CHECK', 'Playing Chudder plays after web joined paused');

    mark('PHASE', 'end');
    stop = true;
    await wait(0.8);
    await positions.close();
    await trace.flush();
    await a.dispose();
    File('$webDir/stop.txt').writeAsStringSync('');
  }, timeout: const Timeout(Duration(minutes: 8)));
}

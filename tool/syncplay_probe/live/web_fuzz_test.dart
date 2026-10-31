// Random actions from both sides of a group of one headless Chudder and a real
// jellyfin-web driven by web_driver.py. After each round both must have come
// to rest together. WEB_DIR is where the driver reads and writes.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'live_harness.dart';

const webDir = String.fromEnvironment('WEB_DIR');
const rounds = int.fromEnvironment('ROUNDS', defaultValue: 30);
const firstSeed = int.fromEnvironment('SEED', defaultValue: 1);

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

Map<String, dynamic>? lastVideo() {
  final lines = File('$webDir/web_log.txt').readAsLinesSync().reversed;
  for (final line in lines.take(40)) {
    final at = line.indexOf('VIDEO {');
    if (at >= 0) return json.decode(line.substring(at + 6)) as Map<String, dynamic>;
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
  final trace = File('$webDir/fuzz_trace.txt').openWrite();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync') && !r.message.contains('Received WebSocket')) {
      trace.writeln('${r.time.millisecondsSinceEpoch / 1000} ${r.message}');
    }
  });

  test('random rounds with real web', () async {
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
    final seriesId = (shows['Items'] as List).first['Id'] as String;
    final list = json.decode((await http.get(Uri.parse('$liveHost/Shows/$seriesId/Episodes?UserId=$userId'), headers: headers)).body)
        as Map<String, dynamic>;
    final items = (list['Items'] as List).cast<Map<String, dynamic>>();
    final episodes = [for (final e in items) e['Id'] as String].take(8).toList();
    final lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 0) ~/ 10)
    };

    final a = await Member.create('A', lengths);
    a.sim.fileOverrun = Duration.zero;
    await a.sync.createGroup('live-web');
    await wait(1);
    await a.sync.setNewQueue(itemIds: episodes, playingItemPosition: 1, startPositionTicks: 600000000);
    await wait(8);

    void web(String command) => File('$webDir/cmd.txt').writeAsStringSync(command);
    final failures = <String>[];
    final log = File('$webDir/fuzz_rounds.txt').openWrite();
    for (var seed = firstSeed; seed < firstSeed + rounds; seed++) {
      final r = Random(seed);
      final actions = <String>[];
      for (var i = 0; i < 2 + r.nextInt(4); i++) {
        final choice = r.nextInt(9);
        final to = (120 + r.nextInt(1200)) * 10000000;
        actions.add(const ['c-pause', 'c-play', 'c-seek', 'c-next', 'c-prev', 'w-pause', 'w-play', 'w-seek', 'c-stall'][choice]);
        switch (choice) {
          case 0:
            await a.player.userPause();
          case 1:
            await a.player.userPlay();
          case 2:
            await a.player.userSeek(Duration(microseconds: to ~/ 10));
          case 3:
            final next = a.model?.nextVideo;
            if (next != null) await a.helper.loadNewVideo(next);
          case 4:
            final previous = a.model?.previousVideo;
            if (previous != null) await a.helper.loadNewVideo(previous);
          case 5:
            web('Pause');
          case 6:
            web('Unpause');
          case 7:
            web('Seek ${json.encode({'PositionTicks': to})}');
          case 8:
            if (a.sim.running) a.sim.stall(const Duration(seconds: 2));
        }
        await wait(0.15 + r.nextDouble() * 2.5);
      }
      await wait(9);
      final v = lastVideo();
      final problems = <String>[];
      final state = a.group.groupState;
      final item = a.group.playingItemId;
      if (state == SyncPlayGroupState.waiting) problems.add('still waiting');
      if (v == null) {
        problems.add('web has no video');
      } else {
        if (v['s'] != item) problems.add('web on ${v['s']}, group on $item');
        final gap = (a.sim.position.inMilliseconds / 1000 - (v['t'] as num)).abs();
        if (gap > 1.6) problems.add('apart ${gap.toStringAsFixed(2)} s');
        final webRunning = v['p'] != true;
        if (webRunning != (state == SyncPlayGroupState.playing)) problems.add('web running=$webRunning, group $state');
        if (a.sim.running != (state == SyncPlayGroupState.playing)) problems.add('chudder running=${a.sim.running}, group $state');
      }
      log.writeln('$seed ${actions.join(' ')} => ${state.name} ${problems.isEmpty ? 'ok' : problems}');
      await log.flush();
      if (problems.isNotEmpty) {
        failures.add('$seed $actions: $problems');
        // A fresh start, so one failure does not become all of them.
        await a.player.userPlay();
        await a.sync.setNewQueue(itemIds: episodes, playingItemPosition: 1, startPositionTicks: 600000000);
        await wait(10);
      } else if (state == SyncPlayGroupState.paused) {
        await a.player.userPlay();
        await wait(3);
      }
    }
    File('$webDir/stop.txt').writeAsStringSync('');
    await log.close();
    await trace.flush();
    // ignore: avoid_print
    print('${failures.length} of $rounds rounds failed');
    expect(failures, isEmpty, reason: failures.join('\n'));
  }, timeout: const Timeout(Duration(hours: 2)));
}

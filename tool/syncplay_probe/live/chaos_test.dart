// Headless members on a real server through a bad network. The player is the
// simulated one: what is being tested here is the real server, the real
// sockets and the app's own handling of delay and loss.
//   flutter test test/syncplay_live/chaos_test.dart --dart-define=HEADLESS_SYNCPLAY=true
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';

import 'chaos_proxy.dart';
import 'live_harness.dart';

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

Future<bool> until(bool Function() what, {num seconds = 10}) async {
  final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
  while (DateTime.now().isBefore(end)) {
    if (what()) return true;
    await wait(0.03);
  }
  return what();
}

double apart(Member a, Member b) => (a.sim.position - b.sim.position).inMilliseconds.abs().toDouble();

const profiles = {
  'home and a decent remote': (100, 60),
  'home and a bad remote': (250, 200),
  'both on bad links': (300, 300),
};

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
  final trace = <String>[];
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync')) trace.add(r.message);
  });

  late List<String> episodes;
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
    final headers = {'Authorization': 'MediaBrowser Token="${auth['AccessToken']}"'};
    final userId = (auth['User'] as Map<String, dynamic>)['Id'];
    final shows = json.decode((await http.get(
      Uri.parse('$liveHost/Users/$userId/Items?IncludeItemTypes=Series&Recursive=true&SortBy=SortName&Limit=1'),
      headers: headers,
    ))
        .body) as Map<String, dynamic>;
    final series = (shows['Items'] as List).first['Id'] as String;
    final list = json.decode((await http.get(Uri.parse('$liveHost/Shows/$series/Episodes?UserId=$userId'), headers: headers)).body)
        as Map<String, dynamic>;
    final items = (list['Items'] as List).cast<Map<String, dynamic>>();
    episodes = [for (final e in items) e['Id'] as String];
    lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 0) ~/ 10)
    };
  });

  for (final profile in profiles.entries) {
    test('a whole session over ${profile.key}', () async {
      trace.clear();
      final bad = profile.key.startsWith('both');
      final pa = ChaosProxy(liveHost, baseMs: bad ? profile.value.$1 : 2, jitterMs: bad ? profile.value.$2 : 2);
      final pb = ChaosProxy(liveHost, baseMs: profile.value.$1, jitterMs: profile.value.$2, seed: 2);
      await pa.start();
      await pb.start();
      final a = await Member.create('A', lengths, host: pa.url);
      final b = await Member.create('B', lengths, host: pb.url);
      final results = <String, Object>{};
      try {
        await a.sync.createGroup('chaos');
        expect(await until(() => a.group.isInGroup), isTrue);
        final groupId = a.group.groupId!;
        await a.sync.setNewQueue(itemIds: episodes.take(4).toList(), playingItemPosition: 1, startPositionTicks: 600000000);
        expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 8), isTrue, reason: 'start');
        expect(await b.sync.joinGroup(groupId), isTrue, reason: 'join');
        expect(await until(() => a.sim.running && b.sim.running, seconds: 12), isTrue, reason: 'both running');
        await wait(7);
        results['after join'] = apart(a, b);

        await b.player.userSeek(const Duration(seconds: 400));
        expect(await until(() => a.sim.position > const Duration(seconds: 399) && a.sim.running && b.sim.running, seconds: 10),
            isTrue, reason: 'seek');
        await wait(6);
        results['after seek'] = apart(a, b);

        await a.player.userPause();
        expect(await until(() => !b.sim.running, seconds: 4), isTrue, reason: 'pause reaches the other');
        await wait(1);
        results['paused'] = apart(a, b);
        await b.player.userPlay();
        expect(await until(() => a.sim.running && b.sim.running, seconds: 6), isTrue, reason: 'resume');
        await wait(6);
        results['after resume'] = apart(a, b);

        b.sim.stall(const Duration(seconds: 3));
        expect(await until(() => a.group.groupState == SyncPlayGroupState.waiting, seconds: 5), isTrue, reason: 'stall told');
        final held = DateTime.now();
        expect(await until(() => a.group.groupState == SyncPlayGroupState.playing, seconds: 12), isTrue, reason: 'stall over');
        results['stall hold ms'] = DateTime.now().difference(held).inMilliseconds;
        await wait(8);
        results['after stall'] = apart(a, b);

        // The socket goes for 2 s: the server takes the member out, and it
        // has to come back by itself and find the group again.
        await pb.cut(const Duration(seconds: 2));
        expect(await until(() => !b.group.isConnected, seconds: 4), isTrue, reason: 'cut noticed');
        expect(await until(() => b.group.isConnected && b.group.isInGroup && b.sim.running, seconds: 30), isTrue,
            reason: 'back after the cut');
        await wait(12);
        results['after socket cut'] = apart(a, b);
        expect(a.group.playingItemId, b.group.playingItemId);

        await a.helper.loadNewVideo(a.model!.nextVideo!);
        expect(await until(() => b.model?.item.id == a.model?.item.id && a.sim.running && b.sim.running, seconds: 12), isTrue,
            reason: 'next');
        await wait(7);
        results['after next'] = apart(a, b);
      } finally {
        // ignore: avoid_print
        print('${profile.key}: $results');
        File('chaos_trace.txt').writeAsStringSync('=== ${profile.key}\n${trace.join('\n')}\n', mode: FileMode.append);
        await a.dispose();
        await b.dispose();
        await pa.stop();
        await pb.stop();
      }
      for (final e in results.entries.where((e) => e.key != 'stall hold ms')) {
        expect((e.value as double), lessThan(profile.value.$1 + profile.value.$2 + 600.0), reason: e.key);
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

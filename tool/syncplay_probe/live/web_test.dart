// One headless Chudder and a real jellyfin-web, driven by web_driver.py, in
// one group on the demo server. WEB_DIR is where the driver reads and writes.
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

import 'live_harness.dart';

const webDir = String.fromEnvironment('WEB_DIR');

Future<void> wait(num seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
  final trace = File('$webDir/chudder_trace.txt').openWrite();
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync') && !r.message.contains('Received WebSocket')) {
      trace.writeln('${r.time.millisecondsSinceEpoch / 1000} ${r.message}');
    }
  });

  test('Chudder and jellyfin-web in one group', () async {
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
    final list = json.decode((await http.get(
      Uri.parse('$liveHost/Shows/$seriesId/Episodes?UserId=$userId'),
      headers: headers,
    ))
        .body) as Map<String, dynamic>;
    var items = (list['Items'] as List).cast<Map<String, dynamic>>();
    // Real footage with real mpv: the synthetic episodes run at one frame a
    // second, so a position there is only good to the second.
    if (useRealMpv) {
      const films = [
        'e677e7bf3ce1d956c1ce3837ebfc2301',
        '2c0f4fe4fe2e95fe86a2dca6a634f407',
        '601039d36dc5dffdb20fbafc697dd1e0',
        '539919504441e564fe9563205e5bb302',
        'cd44b8f4f147e958fb7e5a1508153bc5',
        '958e77cce70d3615c7844c09fc7c4e64',
      ];
      items = [
        for (final id in films)
          json.decode((await http.get(Uri.parse('$liveHost/Users/$userId/Items/$id'), headers: headers)).body)
              as Map<String, dynamic>,
      ];
    }
    final episodes = [for (final e in items) e['Id'] as String];
    final lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 0) ~/ 10)
    };

    final a = await Member.create('A', lengths);
    a.sim.fileOverrun = Duration.zero;

    final positions = File('$webDir/chudder_log.txt').openWrite();
    var stop = false;
    () async {
      while (!stop) {
        final now = DateTime.now().millisecondsSinceEpoch / 1000;
        positions.writeln('$now ${a.sim.position.inMilliseconds / 1000} ${a.sim.running} ${a.model?.item.id} '
            '${a.group.groupState.name}');
        await wait(0.1);
      }
    }();
    void phase(String name) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      positions.writeln('$now PHASE $name');
      // ignore: avoid_print
      print('PHASE $now $name');
    }

    void web(String command) => File('$webDir/cmd.txt').writeAsStringSync(command);
    final first = (await a.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: episodes[3])).body!;

    phase('solo');
    await a.playSolo(first, const Duration(seconds: 60));
    await wait(2);

    phase('create');
    await a.sync.createGroup('live-web');
    await wait(12);

    phase('chudder-seek');
    await a.player.userSeek(const Duration(seconds: 300));
    await wait(7);

    phase('chudder-pause');
    await a.player.userPause();
    await wait(3);
    phase('chudder-play');
    await a.player.userPlay();
    await wait(6);

    phase('web-pause');
    web('Pause');
    await wait(3);
    phase('web-play');
    web('Unpause');
    await wait(6);

    phase('web-seek');
    final to = (a.sim.position + const Duration(seconds: 200)).inMicroseconds * 10;
    web('Seek ${json.encode({'PositionTicks': to})}');
    await wait(7);

    phase('stall');
    if (!useRealMpv) a.sim.stall(const Duration(seconds: 3));
    await wait(useRealMpv ? 3 : 11);

    phase('lone-episode');
    if (useRealMpv) {
      await a.sync.setNewQueue(itemIds: episodes, playingItemPosition: 3);
    } else {
      await a.sync.setNewQueue(itemIds: [episodes[5]]);
    }
    await wait(10);

    phase('step');
    await a.sync.requestNextItem();
    await wait(10);

    phase('near-end');
    final length = lengths[a.model!.item.id]!;
    await a.player.userSeek(length - const Duration(seconds: 7));
    await wait(16);

    phase('end');
    stop = true;
    await wait(0.3);
    await positions.close();
    await trace.flush();
    await a.dispose();
    File('$webDir/stop.txt').writeAsStringSync('');
  }, timeout: const Timeout(Duration(minutes: 3)));
}

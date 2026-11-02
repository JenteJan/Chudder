// Stopping and starting again, with a real jellyfin-web beside one headless
// Chudder: each side closing its player, a group Stop, and each side starting
// something after it. Prints what the server and both sides do; WEB_DIR as in
// web_test.dart.
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

  test('stopping and starting', () async {
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
    final items = (list['Items'] as List).cast<Map<String, dynamic>>();
    final episodes = [for (final e in items) e['Id'] as String];
    final lengths = {
      for (final e in items) e['Id'] as String: Duration(microseconds: ((e['RunTimeTicks'] as int?) ?? 0) ~/ 10)
    };

    final a = await Member.create('A', lengths);
    a.sim.fileOverrun = Duration.zero;

    final positions = File('$webDir/chudder_log.txt').openWrite();
    var stop = false;
    var serverState = '?';
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
        final id = a.group.groupId;
        if (id != null) {
          final r = await http.get(Uri.parse('$liveHost/SyncPlay/$id'), headers: headers);
          final info = json.decode(r.body) as Map<String, dynamic>;
          serverState = '${info['State']}/${(info['Participants'] as List).length}';
        }
        await wait(0.5);
      }
    }();
    void phase(String name) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000;
      positions.writeln('$now PHASE $name');
      // ignore: avoid_print
      print('PHASE $now $name | chudder pos=${a.sim.position.inSeconds} running=${a.sim.running} '
          'item=${a.model?.item.id} says=${a.group.groupState.name} server=$serverState');
    }

    void web(String command) => File('$webDir/cmd.txt').writeAsStringSync(command);
    void closeChudder() {
      a.container.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
      unawaited(a.container.read(videoPlayerProvider).stop());
    }

    Future<String?> webSession() async {
      final all = json.decode((await http.get(Uri.parse('$liveHost/Sessions'), headers: headers)).body) as List;
      final mine = all.cast<Map<String, dynamic>>().where((s) => (s['DeviceId'] as String).startsWith('web-probe')).toList()
        ..sort((x, y) => (y['LastActivityDate'] as String).compareTo(x['LastActivityDate'] as String));
      return mine.isEmpty ? null : mine.first['Id'] as String;
    }

    Future<void> webPlays(String item) async {
      final session = await webSession();
      final r = await http.post(
        Uri.parse('$liveHost/Sessions/$session/Playing?playCommand=PlayNow&itemIds=$item'),
        headers: headers,
      );
      // ignore: avoid_print
      print('web asked to play $item: ${r.statusCode}');
    }

    final first = (await a.container.read(jellyApiProvider).usersUserIdItemsItemIdGet(itemId: episodes[3])).body!;

    phase('solo');
    await a.playSolo(first, const Duration(seconds: 60));
    await wait(2);
    phase('create');
    await a.sync.createGroup('live-web');
    await wait(12);

    phase('web-closes-its-player');
    web('JS history.back()');
    await wait(8);
    phase('chudder-seeks-with-web-closed');
    await a.player.userSeek(const Duration(seconds: 300));
    await wait(10);
    phase('chudder-pauses-with-web-closed');
    await a.player.userPause();
    await wait(4);
    phase('chudder-plays-with-web-closed');
    await a.player.userPlay();
    await wait(36);

    phase('web-starts-an-item');
    await webPlays(episodes[2]);
    await wait(14);

    phase('web-group-stop');
    web('Stop');
    await wait(8);
    phase('chudder-starts-an-item-after-stop');
    await a.sync.setNewQueue(itemIds: episodes, playingItemPosition: 4);
    await wait(14);

    phase('web-group-stop-3');
    web('Stop');
    await wait(6);
    phase('web-starts-an-item-after-stop');
    await webPlays(episodes[1]);
    await wait(14);

    phase('chudder-closes-its-player');
    closeChudder();
    await wait(6);
    phase('web-seeks-with-chudder-closed');
    final to = (const Duration(seconds: 500)).inMicroseconds * 10;
    web('Seek ${json.encode({'PositionTicks': to})}');
    await wait(36);
    phase('chudder-reopens');
    await a.sync.rejoinPlayback();
    await wait(12);

    phase('end');
    stop = true;
    await wait(0.8);
    await positions.close();
    await trace.flush();
    await a.dispose();
    File('$webDir/stop.txt').writeAsStringSync('');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

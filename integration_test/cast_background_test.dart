// A cast while the phone app is sent to the background: does the TV keep going,
// is the progress saved on the server, and is the app back in step when it
// returns?
//
// Run on the phone:
//   flutter test integration_test/cast_background_test.dart -d <phone> --flavor development \
//     --dart-define=CAST_TV=<part of the TV's name> --dart-define=CAST_EPISODE=<an episode title that plays on it> [--dart-define=SYNCPLAY=true]
//
// The test prints `[cast-bg] ACTION background` and `[cast-bg] ACTION foreground`;
// whoever drives the phone (adb) sends the app away at the first and brings it
// back at the second. Uses the saved login; leaves the TV stopped.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/main.dart' as app;
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/incognito_mode_provider.dart';
import 'package:chudder/providers/cast_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

const _tvName = String.fromEnvironment('CAST_TV');
const _episodeName = String.fromEnvironment('CAST_EPISODE');
const _syncPlay = bool.fromEnvironment('SYNCPLAY');
const _awaySeconds = int.fromEnvironment('AWAY_SECONDS', defaultValue: 150);
final _checks = <String>[];
final _logs = <String>[];

void _out(String line) => debugPrint('[cast-bg] $line');

void _check(String name, bool passed, [String detail = '']) {
  _checks.add('${passed ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
  _out(_checks.last);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a cast survives the app going to the background', (tester) async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName.startsWith('Cast')) _logs.add(record.message);
      if (record.loggerName.startsWith('Cast') && record.level >= Level.INFO) _out('log ${record.loggerName}: ${record.message}');
    });

    Future<void> wait(Duration duration) => tester.runAsync(() => Future<void>.delayed(duration));

    expect(_tvName, isNotEmpty, reason: 'pass --dart-define=CAST_TV=<part of the TV name>');
    expect(_episodeName, isNotEmpty, reason: 'pass --dart-define=CAST_EPISODE=<an episode title that plays on the TV>');
    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 90));
    await _settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBody).first), listen: false);
    final api = container.read(jellyApiProvider);
    // A debug build is incognito by default and reports nothing to the server.
    container.read(incognitoModeProvider.notifier).state = false;
    _out('incognito: ${container.read(incognitoProvider)}');

    final found = await api.itemsGet(includeItemTypes: [BaseItemKind.episode], recursive: true, searchTerm: _episodeName, limit: 10);
    final item = (await api.usersUserIdItemsItemIdGet(
      itemId: (found.body?.items ?? const []).firstWhere((e) => e.name == _episodeName).id,
    ))
        .body!;
    final model = await container.read(playbackModelHelper).createPlaybackModel(null, item);
    _out('episode "${item.name}", syncplay=$_syncPlay');

    if (_syncPlay) {
      // The SyncPlay screen connects the controller when it opens; do the same.
      await container.read(syncPlayProvider.notifier).connect();
      final syncPlay = container.read(syncPlayProvider.notifier);
      // Join the group another member keeps open, when there is one.
      final existing = (await syncPlay.listGroups()).where((g) => g.groupName == 'cast-test').toList();
      final group = existing.isNotEmpty ? existing.first : await syncPlay.createGroup('cast-test');
      if (existing.isNotEmpty) await syncPlay.joinGroup(existing.first.groupId!);
      _out('syncplay: ${existing.isNotEmpty ? 'joined the existing group' : 'created a new group'}');
      // The server confirms the join through its own event, a moment later.
      await _pumpUntil(tester, () => container.read(isSyncPlayActiveProvider), const Duration(seconds: 20));
      _out('syncplay group ${group?.groupName} created, active=${container.read(isSyncPlayActiveProvider)}');
      _check('in the SyncPlay group before casting', container.read(isSyncPlayActiveProvider));
      _out('participants: ${container.read(syncPlayProvider).participants}');
    }

    // The start of the episode, so that what the server saved afterwards is the
    // time spent away and nothing older.
    await container.read(videoPlayerProvider.notifier).loadPlaybackItem(model!, const Duration(minutes: 2));
    await _settle(tester, const Duration(seconds: 4));
    final cast = container.read(castProvider.notifier);
    await cast.discover(timeout: const Duration(seconds: 10));
    final tv = container.read(castProvider).devices.firstWhere((d) => d.name.contains(_tvName));
    final onChromecast = tv.kind.name == 'chromecast';
    await cast.connect(tv);
    await _pumpUntil(tester, () => container.read(castProvider).isConnected, const Duration(seconds: 45));
    _check('connected to the TV', container.read(castProvider).isConnected, container.read(castProvider).error ?? '');
    await _pumpUntil(
        tester,
        () => _logs.any((l) => l.contains('media=PLAYING')) || (!onChromecast && (container.read(videoPlayerProvider).lastState?.playing ?? false)),
        const Duration(seconds: 60));
    await _settle(tester, const Duration(seconds: 15));

    Future<Map<String, Object?>> serverView() async {
      final sessions = (await api.api.sessionsGet()).body ?? const <SessionInfoDto>[];
      final playing = sessions.where((s) => s.nowPlayingItem?.name == item.name).toList();
      final data = (await api.usersUserIdItemsItemIdGet(itemId: item.id)).body;
      return {
        'sessions': playing.map((s) => '${s.$Client}/${s.deviceName} paused=${s.playState?.isPaused} pos=${Duration(microseconds: (s.playState?.positionTicks ?? 0) ~/ 10).inSeconds}s').toList(),
        'saved': Duration(microseconds: (data?.userData.playbackPositionTicks ?? 0) ~/ 10).inSeconds,
      };
    }

    final before = await serverView();
    _out('server before leaving: $before');
    _check('the server sees the cast playing', (before['sessions'] as List).isNotEmpty);

    _out('ACTION background');
    final start = DateTime.now();
    var lastLog = <String, Object?>{};
    while (DateTime.now().difference(start) < const Duration(seconds: _awaySeconds)) {
      await wait(const Duration(seconds: 30));
      lastLog = await serverView();
      _out('while away (${DateTime.now().difference(start).inSeconds}s): $lastLog');
    }
    _out('ACTION foreground');
    await wait(const Duration(seconds: 25));
    await _settle(tester, const Duration(seconds: 5));

    final after = await serverView();
    _out('server after returning: $after');
    final sessionsAfter = after['sessions'] as List;
    _check('the TV kept playing while the app was away', sessionsAfter.isNotEmpty && !sessionsAfter.first.toString().contains('paused=true'),
        sessionsAfter.join('; '));
    _check('the app is still connected to the TV', container.read(castProvider).isConnected, container.read(castProvider).error ?? '');
    final appPosition = container.read(videoPlayerProvider).lastState?.position ?? Duration.zero;
    final advanced = appPosition >= const Duration(minutes: 2, seconds: _awaySeconds - 20);
    _check('the app shows where the TV has got to', advanced, 'app position ${appPosition.inSeconds}s');
    if (_syncPlay) {
      _check('still in the SyncPlay group', container.read(isSyncPlayActiveProvider));
      _out('participants after: ${container.read(syncPlayProvider).participants}');
    }

    await cast.disconnect();
    await _settle(tester, const Duration(seconds: 4));
    final saved = await serverView();
    _out('server after stopping: $saved');
    _check('the server saved the progress', (saved['saved'] as int) >= 2 * 60 + _awaySeconds - 40, 'saved ${saved['saved']}s');
    if (_syncPlay) await container.read(syncPlayProvider.notifier).leaveGroup();

    // What the server wrote down about this episode, whoever reported it.
    try {
      final logs = (await api.api.systemLogsGet()).body ?? const <LogFile>[];
      final main = logs.firstWhere((l) => (l.name ?? '').startsWith('log_'), orElse: () => logs.first);
      final text = (await api.api.systemLogsLogGet(name: main.name)).body ?? '';
      final lines = text.split('\n').where((l) => l.contains('playback of') && !l.contains('"Chromecast"')).toList();
      for (final line in lines.reversed.take(14).toList().reversed) {
        _out('server log> ${line.length > 260 ? line.substring(0, 260) : line}');
      }
    } catch (error) {
      _out('server log not available: ${error.toString().split('\n').first}');
    }

    _out('\n${_checks.join('\n')}');
    expect(_checks.where((check) => check.startsWith('FAIL')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) return;
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

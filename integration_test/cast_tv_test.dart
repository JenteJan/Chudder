// Casts a real episode from the real app to the TV on the network and
// checks that the TV carries the season on by itself, .
//
// Run: flutter test integration_test/cast_tv_test.dart -d windows --dart-define=CAST_TV=<part of the TV's name>
//
// Uses the login the app has saved, so watch progress of the episodes it plays
// is recorded on that account. Leaves the TV stopped.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/main.dart' as app;
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/cast_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:chudder/wrappers/players/remote_device.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

const _tvName = String.fromEnvironment('CAST_TV');
const _episodeName = String.fromEnvironment('CAST_EPISODE');
/// Set when the scan cannot find the Chromecast (adb holds the mDNS port), to talk to it by address.
const _castHost = String.fromEnvironment('CAST_HOST');

RemoteDevice _tv(List<RemoteDevice> devices) {
  for (final device in devices) {
    if (device.name.contains(_tvName)) return device;
  }
  if (_castHost.isEmpty) throw StateError('No TV matching CAST_TV="$_tvName" found; pass --dart-define=CAST_TV=<part of its name>');
  return RemoteDevice.desktopChromecast(const CastDeviceInfo(id: 'manual', name: _tvName, host: _castHost, port: 8009));
}

final _checks = <String>[];
final _logs = <String>[];

void _out(String line) => debugPrint('[cast-tv] $line');

void _check(String name, bool passed, [String detail = '']) {
  _checks.add('${passed ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
  _out(_checks.last);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the TV carries a season on, with and without the app', (tester) async {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName.startsWith('Cast')) _logs.add(record.message);
      if (record.loggerName.startsWith('Cast') || record.loggerName.startsWith('Jellyfin')) {
        _out('log ${record.loggerName}: ${record.message}');
      }
    });

    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 60));
    await _settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBody).first), listen: false);
    final api = container.read(jellyApiProvider);
    _out('logged in as ${container.read(userProvider)?.name}');

    // A season with enough episodes behind the one we start from.
    final series = await api.usersUserIdItemsGet(
      includeItemTypes: [BaseItemKind.series],
      recursive: true,
      limit: 40,
      sortBy: [ItemSortBy.datecreated],
      sortOrder: [SortOrder.descending],
    );
    List<BaseItemDto>? season;
    // A title known to play on the TV: its own season, starting just before it.
    if (_episodeName.isNotEmpty) {
      final found = await api.itemsGet(
        includeItemTypes: [BaseItemKind.episode],
        recursive: true,
        searchTerm: _episodeName,
        limit: 10,
      );
      final matches = (found.body?.items ?? const []).where((e) => e.name == _episodeName).toList();
      final match = matches.isEmpty ? null : matches.first;
      if (match?.parentId != null) {
        final all = await api.usersUserIdItemsGet(
          parentId: match!.parentId,
          includeItemTypes: [BaseItemKind.episode],
          recursive: true,
          sortBy: [ItemSortBy.indexnumber],
        );
        final list = all.body?.items ?? const <BaseItemDto>[];
        final at = list.indexWhere((e) => e.id == match.id);
        final from = (at - 1).clamp(0, list.length);
        season = list.sublist(from);
        _out('using the season of "$_episodeName", ${season.length} episodes from there');
      }
    }
    for (final show in season != null ? const <BaseItemDto>[] : series.body?.items ?? const <BaseItemDto>[]) {
      final episodes = await api.usersUserIdItemsGet(
        parentId: show.id,
        includeItemTypes: [BaseItemKind.episode],
        recursive: true,
        sortBy: [ItemSortBy.parentindexnumber, ItemSortBy.indexnumber],
      );
      final bySeason = <String, List<BaseItemDto>>{};
      for (final episode in episodes.body?.items ?? const <BaseItemDto>[]) {
        bySeason.putIfAbsent(episode.seasonId ?? '', () => []).add(episode);
      }
      season = bySeason.values.firstWhere((list) => list.length >= 6, orElse: () => const []);
      if (season.isNotEmpty) {
        _out('using "${show.name}", ${season.length} episodes in the season');
        break;
      }
      season = null;
    }
    expect(season != null && season.length >= 5, isTrue, reason: 'no season with enough episodes');
    final episodes = season!;
    String nameOf(String? id) => episodes.firstWhere((e) => e.id == id, orElse: () => const BaseItemDto(name: '?')).name ?? id ?? '?';

    String? shown() => container.read(playBackModel)?.item.id;
    Duration? position() => container.read(videoPlayerProvider).lastState?.position;
    final cast = container.read(castProvider.notifier);

    // Starts [episode] in the app, from 35 seconds before its end, and casts it.
    Future<void> castNearEnd(BaseItemDto episode) async {
      final item = (await api.usersUserIdItemsItemIdGet(itemId: episode.id)).body!;
      final model = await container.read(playbackModelHelper).createPlaybackModel(null, item);
      expect(model, isNotNull);
      final ticks = episode.runTimeTicks ?? 0;
      final start = Duration(microseconds: ticks ~/ 10) - const Duration(seconds: 35);
      _out('casting "${item.name}" from $start, ${model!.playbackQueue.queue.length} items behind it');
      await container.read(videoPlayerProvider.notifier).loadPlaybackItem(model, start);
      await _settle(tester, const Duration(seconds: 4));
      if (!container.read(castProvider).isConnected) {
        await cast.discover(timeout: const Duration(seconds: 8));
        final tv = _tv(container.read(castProvider).devices);
        await cast.connect(tv);
        await _pumpUntil(tester, () => container.read(castProvider).isConnected, const Duration(seconds: 40));
      }
    }

    // 1. The TV reaches the end of an episode with the app connected.
    await castNearEnd(episodes[1]);
    _check('connected to the TV', container.read(castProvider).isConnected, container.read(castProvider).error ?? '');
    await _pumpUntil(tester, () => (position() ?? Duration.zero) > const Duration(minutes: 40), const Duration(seconds: 60));
    final states = _logs.where((l) => l.contains('media=') && !l.contains('media=null')).toList();
    final playing = states.any((l) => l.contains('media=PLAYING'));
    _check('the TV is playing near the end of the first episode', shown() == episodes[1].id && playing,
        'position=${position()} receiver says ${states.isEmpty ? 'nothing' : states.last.split('media=').last}');

    final second = episodes[2].id;
    await _pumpUntil(tester, () => shown() == second, const Duration(seconds: 90));
    _check('the app follows the TV to the next episode', shown() == second, 'shown=${nameOf(shown())}');
    await _pumpUntil(
        tester,
        () => (position() ?? Duration.zero) > const Duration(seconds: 5) && (position() ?? Duration.zero) < const Duration(minutes: 5),
        const Duration(seconds: 40));
    _check('the next episode plays from its start, not restarted',
        (position() ?? Duration.zero) > Duration.zero && (position() ?? Duration.zero) < const Duration(minutes: 2),
        'position=${position()}');

    // 2. A seek in the middle of an episode keeps playing.
    await container.read(videoPlayerProvider).seek(const Duration(minutes: 10));
    await _settle(tester, const Duration(seconds: 25));
    _check('a seek on the TV keeps playing at the new position',
        container.read(castProvider).isConnected && (position() ?? Duration.zero) > const Duration(minutes: 9, seconds: 50),
        'connected=${container.read(castProvider).isConnected} position=${position()}');

    // Leave the TV stopped.
    await cast.disconnect();
    await _settle(tester, const Duration(seconds: 3));
    _out('\n${_checks.join('\n')}');
    expect(_checks.where((check) => check.startsWith('FAIL')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 12)));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done, Duration timeout) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      _out('timeout waiting; continuing anyway');
      return;
    }
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// Casts an episode that has subtitles to the TV on the network and switches
// between its tracks, checking that each one arrives.
//
// Run: flutter test integration_test/cast_tv_subtitles_test.dart -d windows --dart-define=CAST_TV=<part of the TV's name>
//
// CAST_TV is part of the TV's name in the picker. On a Chromecast the check is
// the subtitle index the receiver reports back; on a DLNA TV it is the TV
// fetching the subtitle file from the app. Uses the saved login and leaves the
// TV stopped.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/main.dart' as app;
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/cast_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:chudder/wrappers/players/remote_device.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

const _tvName = String.fromEnvironment('CAST_TV');
const _textCodecs = {'subrip', 'srt', 'ass', 'ssa', 'webvtt', 'vtt', 'mov_text', 'text'};
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

void _out(String line) => debugPrint('[cast-sub] $line');

void _check(String name, bool passed, [String detail = '']) {
  _checks.add('${passed ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}');
  _out(_checks.last);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every subtitle track reaches the TV', (tester) async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName.startsWith('Cast')) {
        _logs.add('${record.loggerName}: ${record.message}');
        if (record.level >= Level.INFO) _out('log ${record.loggerName}: ${record.message}');
      }
    });

    app.main([]);
    await _pumpUntil(tester, () => find.byType(NavigationBody).evaluate().isNotEmpty, const Duration(seconds: 60));
    await _settle(tester, const Duration(seconds: 3));
    final container = ProviderScope.containerOf(tester.element(find.byType(NavigationBody).first), listen: false);
    final api = container.read(jellyApiProvider);

    // An episode with subtitles, ideally an embedded and a downloaded one.
    final series = await api.usersUserIdItemsGet(
      includeItemTypes: [BaseItemKind.series],
      recursive: true,
      limit: 40,
      sortBy: [ItemSortBy.datecreated],
      sortOrder: [SortOrder.descending],
    );
    PlaybackModel? model;
    var bestScore = 0;
    // A title known to play on the TV, when one is named.
    if (_episodeName.isNotEmpty) {
      final found = await api.itemsGet(
        includeItemTypes: [BaseItemKind.episode],
        recursive: true,
        searchTerm: _episodeName,
        limit: 10,
      );
      final matches = (found.body?.items ?? const []).where((e) => e.name == _episodeName).toList();
      if (matches.isNotEmpty) {
        final item = (await api.usersUserIdItemsItemIdGet(itemId: matches.first.id)).body;
        model = await container.read(playbackModelHelper).createPlaybackModel(null, item);
      }
    }
    for (final show in model != null ? const <BaseItemDto>[] : series.body?.items ?? const <BaseItemDto>[]) {
      final episodes = await api.usersUserIdItemsGet(
        parentId: show.id,
        includeItemTypes: [BaseItemKind.episode],
        recursive: true,
        limit: 1,
        sortBy: [ItemSortBy.parentindexnumber, ItemSortBy.indexnumber],
      );
      final episode = episodes.body?.items?.firstOrNull;
      if (episode == null) continue;
      final item = (await api.usersUserIdItemsItemIdGet(itemId: episode.id)).body;
      final candidate = await container.read(playbackModelHelper).createPlaybackModel(null, item);
      final subs = _textSubs(candidate);
      // H.264 plays on every Chromecast; an HEVC file may not play on the TV at
      // all, which would say nothing about subtitles.
      final plain = candidate?.mediaStreams?.videoStreams.firstOrNull?.codec.toLowerCase() == 'h264';
      final score = subs.isEmpty ? 0 : 1 + (plain ? 4 : 0) + (subs.any((s) => s.isExternal) ? 2 : 0) + (subs.any((s) => !s.isExternal) ? 1 : 0);
      if (score > bestScore) {
        bestScore = score;
        model = candidate;
      }
      if (bestScore == 8) break;
    }
    expect(model, isNotNull, reason: 'no episode with a text subtitle');
    final subs = _textSubs(model);
    _out('using "${model!.item.name}" with subtitles: '
        '${subs.map((s) => '#${s.index} ${s.codec} ${s.language} ${s.isExternal ? 'external' : 'embedded'}').join('; ')}');

    await container.read(videoPlayerProvider.notifier).loadPlaybackItem(model, Duration.zero);
    await _settle(tester, const Duration(seconds: 4));

    final cast = container.read(castProvider.notifier);
    await cast.discover(timeout: const Duration(seconds: 8));
    final tv = _tv(container.read(castProvider).devices);
    final onChromecast = tv.kind.name == 'chromecast';
    _out('casting to "${tv.name}" (${tv.kind.name})');
    await cast.connect(tv);
    await _pumpUntil(tester, () => container.read(castProvider).isConnected, const Duration(seconds: 40));
    _check('connected to the TV', container.read(castProvider).isConnected, container.read(castProvider).error ?? '');
    for (final line in _logs.where((l) => l.contains('Connected to '))) {
      _out('receiver: $line');
    }
    await _settle(tester, const Duration(seconds: 15));
    if (onChromecast) {
      final playing = _logs.any((l) => l.contains('media=PLAYING'));
      _check('the TV is really playing', playing, playing ? '' : 'receiver states: ${_logs.where((l) => l.contains('media=') && !l.contains('media=null')).map((l) => l.split('media=').last).toSet().join(' ')}');
    }

    int servedCount() => _logs.where((l) => l.contains('Subtitle sidecar served')).length;
    String? reportedSub() {
      final line = _logs.lastWhere((l) => l.contains(' sub='), orElse: () => '');
      return RegExp(r'sub=(-?\d+|null)').firstMatch(line)?.group(1);
    }

    final wrapper = container.read(videoPlayerProvider);
    for (final sub in [...subs.where((s) => !s.isExternal).take(1), ...subs.where((s) => s.isExternal).take(1)]) {
      final before = servedCount();
      await wrapper.setSubtitleTrack(sub, container.read(playBackModel)!);
      await _settle(tester, const Duration(seconds: 20));
      final label = '${sub.isExternal ? 'external' : 'embedded'} ${sub.codec} subtitle #${sub.index}';
      if (onChromecast) {
        _check('the receiver shows $label', reportedSub() == '${sub.index}', 'receiver reports sub=${reportedSub()}');
      } else {
        _check('the TV fetched $label from the app', servedCount() > before, 'fetches=${servedCount() - before}');
      }
    }

    final before = servedCount();
    await wrapper.setSubtitleTrack(null, container.read(playBackModel)!);
    await _settle(tester, const Duration(seconds: 3));
    _out('subtitles off requested; fetches since: ${servedCount() - before}');

    for (final line in _logs.where((l) => l.contains('Receiver raw')).toList().reversed.take(8).toList().reversed) {
      _out(line);
    }
    await cast.disconnect();
    await _settle(tester, const Duration(seconds: 3));
    _out('\n${_checks.join('\n')}');
    expect(_checks.where((check) => check.startsWith('FAIL')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

List<SubStreamModel> _textSubs(PlaybackModel? model) =>
    (model?.mediaStreams?.subStreams ?? const <SubStreamModel>[]).where((s) => _textCodecs.contains(s.codec.toLowerCase())).toList();

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

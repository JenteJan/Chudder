// Drives the app's own DLNA player and media proxy against the television on
// the network, without the app: what the TV does with a stream is the one
// thing the fake renderer of the unit tests cannot say.
//
// Run through tool/cast_probe/run.py, which hands over the desktop app's
// login in the environment (never on a command line, never printed):
//
//   python tool/cast_probe/run.py <tv address> <item id> [image subtitle index]
//
// Plays a few minutes of the item on that TV, twice, and leaves it stopped.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:chudder/profiles/dlna_profile.dart';
import 'package:chudder/wrappers/players/dlna_discovery.dart';
import 'package:chudder/wrappers/players/dlna_player.dart';

final _env = Platform.environment;
final _base = _env['JF_BASE'] ?? '';
final _token = _env['JF_TOKEN'] ?? '';
final _user = _env['JF_USER'] ?? '';
final _item = _env['CAST_ITEM'] ?? '';
final _tvHost = _env['CAST_TV_HOST'] ?? '';
final _burnSubtitle = int.tryParse(_env['CAST_SUBTITLE'] ?? '');

/// An item with a text subtitle, and that subtitle's index, for the sidecar.
final _textItem = _env['CAST_TEXT_ITEM'] ?? '';
final _textSubtitle = int.tryParse(_env['CAST_TEXT_SUBTITLE'] ?? '');

final _http = HttpClient();
final _started = DateTime.now();
final _warnings = <String>[];

void _out(String line) {
  final t = (DateTime.now().difference(_started).inMilliseconds / 1000).toStringAsFixed(1).padLeft(6);
  // ignore: avoid_print
  print('[$t] ${line.replaceAll(_token, '***')}');
}

Future<Map<String, dynamic>> _server(String path, {Object? body}) async {
  final request = await (body == null ? _http.getUrl(Uri.parse('$_base$path')) : _http.postUrl(Uri.parse('$_base$path')));
  request.headers.set(
    'Authorization',
    'MediaBrowser Client="Chudder", Device="Windows", DeviceId="cast-probe", Version="0.12.0", Token="$_token"',
  );
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(json.encode(body)));
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  return text.isEmpty ? const {} : json.decode(text) as Map<String, dynamic>;
}

/// The television's AVTransport, by address: discovery needs the app's
/// multicast channel on Android and is not what is being tested here.
Future<DlnaRenderer> _renderer() async {
  // The LG picks new ports after a restart; CAST_TV_PORT names this boot's.
  final given = int.tryParse(_env['CAST_TV_PORT'] ?? '');
  for (final port in [?given, 1860, 1400, 9197, 7676, 8080]) {
    try {
      final request = await (HttpClient()..connectionTimeout = const Duration(seconds: 2))
          .getUrl(Uri.parse('http://$_tvHost:$port/'));
      final body = await (await request.close()).transform(utf8.decoder).join();
      final service = RegExp(r'<service>(?:(?!</service>).)*AVTransport(?:(?!</service>).)*</service>', dotAll: true)
          .firstMatch(body)
          ?.group(0);
      final control = service == null ? null : RegExp(r'<controlURL>(.*?)</controlURL>').firstMatch(service)?.group(1);
      if (control == null) continue;
      final name = RegExp(r'<friendlyName>(.*?)</friendlyName>').firstMatch(body)?.group(1) ?? _tvHost;
      return DlnaRenderer(
        id: _tvHost,
        name: name,
        avTransportControlUrl: Uri.parse('http://$_tvHost:$port').resolve(control),
      );
    } catch (_) {}
  }
  throw StateError('No AVTransport found on $_tvHost');
}

/// What `_dlnaStreamUrl` in the cast provider asks the server, with the same
/// device profile.
Future<DlnaStream?> _stream({
  required int? burnSubtitle,
  required int? sourceVideoBitrate,
  Duration? start,
  String? item,
}) async {
  item ??= _item;
  final force = burnSubtitle != null;
  final info = await _server('/Items/$item/PlaybackInfo', body: {
    'UserId': _user,
    'AutoOpenLiveStream': true,
    'EnableTranscoding': true,
    if (start != null && start > Duration.zero) 'StartTimeTicks': start.inMicroseconds * 10,
    'EnableDirectPlay': !force,
    'EnableDirectStream': !force,
    'MaxStreamingBitrate': force ? dlnaTranscodeBitrate(sourceVideoBitrate) : dlnaMaxBitrate,
    'DeviceProfile': dlnaProfile.toJson(),
    'MediaSourceId': item,
    'SubtitleStreamIndex': burnSubtitle ?? -1,
    'AlwaysBurnInSubtitleWhenTranscoding': force,
  });
  final source = (info['MediaSources'] as List).first as Map<String, dynamic>;
  if (!force && (source['SupportsDirectStream'] == true || source['SupportsDirectPlay'] == true)) {
    return DlnaStream(
      '$_base/Videos/${source['Id']}/stream?Static=true&mediaSourceId=${source['Id']}&api_key=$_token&ApiKey=$_token',
      transcoding: false,
    );
  }
  final url = source['TranscodingUrl'] as String?;
  if (url == null) return null;
  _out('server transcodes at ${Uri.parse(url).queryParameters['VideoBitrate']} b/s video');
  return DlnaStream('$_base$url', transcoding: true, startOffset: start ?? Duration.zero);
}

Future<void> _settle(int seconds) => Future<void>.delayed(Duration(seconds: seconds));

/// Waits for the television's clock to be past [from] and still moving.
Future<Duration?> _waitForPlayback(DlnaPlayer player, Duration from, {int seconds = 40}) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed.inSeconds < seconds) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final state = player.lastState;
    if (state.playing && !state.buffering && state.position > from) return watch.elapsed;
  }
  return null;
}

void main() {
  final configured = [_base, _token, _user, _item, _tvHost].every((value) => value.isNotEmpty);

  late DlnaPlayer player;
  late Duration runtime;
  late int? videoBitrate;

  setUpAll(() async {
    if (!configured) return;
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (!record.loggerName.startsWith('Cast')) return;
      if (record.level >= Level.WARNING) _warnings.add(record.message);
      if (record.level >= Level.INFO || record.loggerName == 'Cast.proxy') {
        _out('${record.level.name.toLowerCase()} ${record.loggerName}: ${record.message}');
      }
    });
    final item = await _server('/Users/$_user/Items/$_item');
    runtime = Duration(microseconds: (item['RunTimeTicks'] as int) ~/ 10);
    final streams = ((item['MediaSources'] as List).first as Map<String, dynamic>)['MediaStreams'] as List;
    videoBitrate = streams.cast<Map<String, dynamic>>().firstWhere((s) => s['Type'] == 'Video')['BitRate'] as int?;
    _out('${item['Name']}: ${runtime.inMinutes} min, video ${videoBitrate ?? '?'} b/s');
  });

  Future<void> connect({required int? burnSubtitle}) async {
    _warnings.clear();
    player = await DlnaPlayer.connect(
      await _renderer(),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) =>
          _stream(burnSubtitle: burnSubtitle, sourceVideoBitrate: videoBitrate, start: startPosition),
      knownDuration: () => runtime,
      title: () => 'Chudder cast probe',
    );
  }

  /// Start, pause, resume, skip ahead twice: what a viewer does in the first
  /// minute, and all of what went wrong on the LG.
  Future<void> walk({required bool transcode}) async {
    final load = Stopwatch()..start();
    await player.loadVideo('', true);
    _out('loadVideo returned after ${load.elapsedMilliseconds} ms');
    final moving = await _waitForPlayback(player, const Duration(seconds: 2));
    _out('TV clock moving ${moving == null ? 'NEVER' : 'after another ${moving.inMilliseconds} ms'}; '
        'duration ${player.lastState.duration}');
    expect(moving, isNotNull, reason: 'the TV never got going');
    expect(player.lastState.duration.inSeconds, runtime.inSeconds);

    await player.pause();
    await _settle(5);
    final pausedAt = player.lastState.position;
    await _settle(3);
    _out('paused: playing=${player.lastState.playing} at $pausedAt, 3 s later ${player.lastState.position}');
    expect(player.lastState.playing, isFalse, reason: 'the TV did not pause');
    expect(player.lastState.position, pausedAt, reason: 'the clock ran on through a pause');

    await player.play();
    final resumed = await _waitForPlayback(player, pausedAt + const Duration(seconds: 2));
    _out('resumed ${resumed == null ? 'NEVER' : 'after ${resumed.inMilliseconds} ms'} at ${player.lastState.position}');
    expect(resumed, isNotNull, reason: 'the TV did not resume');

    // Three quick skips, as on the +10 button, then one long jump.
    final skipFrom = player.lastState.position;
    for (var i = 1; i <= 3; i++) {
      await player.seek(skipFrom + Duration(seconds: 10 * i));
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final skipped = await _waitForPlayback(player, skipFrom + const Duration(seconds: 31));
    _out('skipped +30 s ${skipped == null ? 'NEVER' : 'in ${skipped.inMilliseconds} ms'}, at ${player.lastState.position}');
    expect(skipped, isNotNull, reason: 'the skips never landed');
    expect(player.lastState.position, lessThan(skipFrom + const Duration(seconds: 60)));

    const far = Duration(minutes: 50);
    await player.seek(far);
    final jumped = await _waitForPlayback(player, far + const Duration(seconds: 2));
    _out('jumped to 50:00 ${jumped == null ? 'NEVER' : 'in ${jumped.inMilliseconds} ms'}, at ${player.lastState.position}');
    expect(jumped, isNotNull, reason: 'the jump never landed');
    expect(player.lastState.position, lessThan(far + const Duration(seconds: 40)));
    expect(player.lastState.duration.inSeconds, runtime.inSeconds);

    _out('warnings: ${_warnings.isEmpty ? 'none' : _warnings.join(' | ')}');
    // The Stop ahead of a first load is refused by a TV with nothing on it;
    // anything else the TV refused is a command that did not work.
    final refused = _warnings.where((w) => !w.startsWith('Stop failed')).toList();
    expect(refused, isEmpty);
  }

  tearDown(() async {
    if (configured) await player.dispose();
  });

  test('a burned-in subtitle transcode starts, pauses, resumes and seeks on the TV', () async {
    await connect(burnSubtitle: _burnSubtitle);
    await walk(transcode: true);
  }, skip: !configured || _burnSubtitle == null, timeout: const Timeout(Duration(minutes: 5)));

  test('a text subtitle is fetched by the TV next to the file', () async {
    final info = await _server('/Users/$_user/Items/$_textItem');
    runtime = Duration(microseconds: (info['RunTimeTicks'] as int) ~/ 10);
    final lines = <String>[];
    final listening = Logger.root.onRecord.listen((record) => lines.add(record.message));
    _warnings.clear();
    player = await DlnaPlayer.connect(
      await _renderer(),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) =>
          _stream(burnSubtitle: null, sourceVideoBitrate: null, start: startPosition, item: _textItem),
      knownDuration: () => runtime,
      title: () => 'Chudder cast probe',
      initialSubtitleStreamIndex: _textSubtitle,
      subtitleSidecarBuilder: (index, offset) async =>
          '$_base/Videos/$_textItem/$_textItem/Subtitles/$index/${offset.inMicroseconds * 10}/Stream.srt'
          '?api_key=$_token&ApiKey=$_token',
    );
    // Somewhere with talking in it.
    await player.loadVideo('', true, startPosition: const Duration(minutes: 10));
    final moving = await _waitForPlayback(player, const Duration(minutes: 10, seconds: 3));
    _out('with a sidecar: clock moving ${moving == null ? 'NEVER' : 'after ${moving.inMilliseconds} ms'} '
        'at ${player.lastState.position}');
    await _settle(8);
    await listening.cancel();
    expect(moving, isNotNull, reason: 'the TV never got going');
    expect(lines.where((line) => line.startsWith('Subtitle sidecar served to $_tvHost')), isNotEmpty,
        reason: 'the TV never asked for the subtitle file');
  }, skip: !configured || _textItem.isEmpty || _textSubtitle == null, timeout: const Timeout(Duration(minutes: 3)));

  test('a TV that is given another stream is let go, at the position this one had', () async {
    var ended = 0;
    _warnings.clear();
    final item = await _server('/Users/$_user/Items/$_item');
    runtime = Duration(microseconds: (item['RunTimeTicks'] as int) ~/ 10);
    player = await DlnaPlayer.connect(
      await _renderer(),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) =>
          _stream(burnSubtitle: null, sourceVideoBitrate: null, start: startPosition),
      knownDuration: () => runtime,
      title: () => 'Chudder cast probe',
      onSessionEnded: () => ended++,
    );
    await player.loadVideo('', true, startPosition: const Duration(minutes: 20));
    final moving = await _waitForPlayback(player, const Duration(minutes: 20, seconds: 3));
    expect(moving, isNotNull, reason: 'the TV never got going');
    final before = player.lastState.position;

    // A second sender, with a proxy and so an address of its own, starts the
    // same film from the beginning on the same TV.
    final other = await DlnaPlayer.connect(
      await _renderer(),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) =>
          _stream(burnSubtitle: null, sourceVideoBitrate: null, start: startPosition),
      knownDuration: () => runtime,
      title: () => 'Chudder cast probe (other sender)',
    );
    await other.loadVideo('', true);
    await _settle(12);
    _out('taken over: first sender ended $ended time(s); it was at $before, now says ${player.lastState.position}; '
        'the other is at ${other.lastState.position}');
    await other.dispose();

    expect(ended, 1, reason: 'the first sender went on following a stream that was not its own');
    expect(player.lastState.position, greaterThanOrEqualTo(before));
    expect(player.lastState.position, lessThan(before + const Duration(seconds: 30)));
  }, skip: !configured, timeout: const Timeout(Duration(minutes: 3)));

  test('the file itself starts, pauses, resumes and seeks on the TV', () async {
    await connect(burnSubtitle: null);
    await walk(transcode: false);
  }, skip: !configured, timeout: const Timeout(Duration(minutes: 5)));
}

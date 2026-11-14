// Drives the app's own Jellyfin-receiver player against a Chromecast on the
// network, over the desktop sender's connection and without the app.
//
// Run through tool/cast_probe/run.py (the login goes in the environment):
//
//   python tool/cast_probe/run.py --chromecast <chromecast address> <item id> [subtitle index]
//
// The receiver plays the item under the account's own session, so its watch
// progress is recorded. Plays about a minute and leaves the Chromecast stopped.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/wrappers/players/cast/desktop/cast_mdns_discovery.dart';
import 'package:chudder/wrappers/players/cast/desktop/desktop_cast_player.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';

final _env = Platform.environment;
final _base = _env['JF_BASE'] ?? '';
final _token = _env['JF_TOKEN'] ?? '';
final _user = _env['JF_USER'] ?? '';
final _serverId = _env['JF_SERVER_ID'] ?? '';
final _item = _env['CAST_ITEM'] ?? '';
final _itemName = _env['CAST_ITEM_NAME'] ?? 'Cast probe';
final _host = _env['CAST_HOST'] ?? '';
final _appId = _env['CAST_APP_ID'] ?? jellyfinReceiverAppId;
final _subtitle = int.tryParse(_env['CAST_SUBTITLE'] ?? '');

/// Where to start and where to jump to; a short film needs both earlier.
final _start = Duration(seconds: int.tryParse(_env['CAST_START_SECONDS'] ?? '') ?? 1200);
final _far = Duration(seconds: int.tryParse(_env['CAST_SEEK_SECONDS'] ?? '') ?? 3000);

final _started = DateTime.now();
final _warnings = <String>[];

void _out(String line) {
  final t = (DateTime.now().difference(_started).inMilliseconds / 1000).toStringAsFixed(1).padLeft(6);
  // ignore: avoid_print
  print('[$t] ${line.replaceAll(_token, '***')}');
}

Future<void> _settle(double seconds) => Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

void main() {
  final configured = [_base, _token, _user, _item, _host].every((value) => value.isNotEmpty);

  test('the Chromecast plays, pauses, resumes, seeks and takes its volume from here', () async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (!record.loggerName.startsWith('Cast')) return;
      if (record.level >= Level.WARNING) _warnings.add(record.message);
      if (record.level >= Level.FINE) {
        final message = record.message.length > 330 ? '${record.message.substring(0, 330)}…' : record.message;
        _out('${record.level.name.toLowerCase()} ${record.loggerName}: $message');
      }
    });

    var ended = 0;
    final start = _start;
    final player = await DesktopJellyfinCastPlayer.connect(
      CastDeviceInfo(id: 'probe', name: 'Chromecast', host: _host, port: 8009),
      _appId,
      JellyfinCastContext(
        serverAddress: _base,
        accessToken: _token,
        userId: _user,
        deviceId: 'cast-probe',
        serverId: _serverId,
        serverVersion: '',
        itemStub: {
          'Id': _item,
          'ServerId': _serverId,
          'Name': _itemName,
          'Type': 'Movie',
          'MediaType': 'Video',
          'IsFolder': false,
        },
        startPosition: start,
        mediaSourceId: _item,
        subtitleStreamIndex: _subtitle,
      ),
      onSessionEnded: () => ended++,
    );
    addTearDown(player.dispose);
    await player.init(VideoPlayerSettingsModel());

    Future<Duration?> moving(Duration from, {int seconds = 60}) async {
      final watch = Stopwatch()..start();
      while (watch.elapsed.inSeconds < seconds) {
        await _settle(0.5);
        final state = player.lastState;
        if (state.playing && !state.buffering && state.position > from) return watch.elapsed;
      }
      return null;
    }

    final load = Stopwatch()..start();
    await player.loadVideo('', true, startPosition: start);
    final began = await moving(start + const Duration(seconds: 2));
    _out('playing ${began == null ? 'NEVER' : '${load.elapsedMilliseconds} ms after the load'}, at '
        '${player.lastState.position} of ${player.lastState.duration}; device volume ${player.remoteVolumeLevel}');
    expect(began, isNotNull, reason: 'the Chromecast never got going');

    // Volume: what the device says, a step down from here, and how long the
    // device takes to say so itself.
    final volume = player.remoteVolumeLevel;
    _out('device volume as reported: $volume');
    if (volume != null) {
      final target = volume >= 4 ? volume - 3 : volume + 3;
      await player.setVolume(target.toDouble());
      final told = Stopwatch()..start();
      while (player.remoteVolumeLevel != target && told.elapsed.inSeconds < 12) {
        await _settle(0.25);
      }
      _out('set $target: the device reported ${player.remoteVolumeLevel} after ${told.elapsedMilliseconds} ms');
      await player.setVolume(volume.toDouble());
      await _settle(2);
      _out('restored to $volume: reports ${player.remoteVolumeLevel}');
      expect(player.remoteVolumeLevel, volume, reason: 'the device did not take the volume back');
    }

    await player.pause();
    await _settle(4);
    final pausedAt = player.lastState.position;
    await _settle(3);
    _out('paused: playing=${player.lastState.playing} at $pausedAt, 3 s later ${player.lastState.position}');
    expect(player.lastState.playing, isFalse, reason: 'the Chromecast did not pause');
    expect((player.lastState.position - pausedAt).inSeconds.abs(), lessThanOrEqualTo(1));

    await player.play();
    final resumed = await moving(pausedAt + const Duration(seconds: 2), seconds: 20);
    _out('resumed ${resumed == null ? 'NEVER' : 'after ${resumed.inMilliseconds} ms'} at ${player.lastState.position}');
    expect(resumed, isNotNull, reason: 'the Chromecast did not resume');

    final far = _far;
    final seek = Stopwatch()..start();
    await player.seek(far);
    final jumped = await moving(far + const Duration(seconds: 2));
    _out('jumped to $far ${jumped == null ? 'NEVER' : 'in ${seek.elapsedMilliseconds} ms'}, at ${player.lastState.position}');
    expect(jumped, isNotNull, reason: 'the seek never landed');
    expect(player.lastState.position, lessThan(far + const Duration(seconds: 45)));

    _out('session ended by itself $ended time(s); warnings: ${_warnings.isEmpty ? 'none' : _warnings.join(' | ')}');
    expect(ended, 0);
  }, skip: !configured, timeout: const Timeout(Duration(minutes: 5)));
}

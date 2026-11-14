import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/profiles/dlna_profile.dart';
import 'package:chudder/wrappers/players/dlna_discovery.dart';
import 'package:chudder/wrappers/players/dlna_player.dart';

/// A television that takes every AVTransport call and remembers them.
class _FakeRenderer {
  late final HttpServer _server;
  final List<String> actions = [];
  final List<String> bodies = [];

  /// Actions the television never answers, like a webOS set that has hung.
  final Set<String> unanswered = {};

  String relTime = '00:00:05';

  /// The address the television says it is playing; none when null.
  String? trackUri;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final body = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      final text = String.fromCharCodes(body);
      final action = RegExp(r'<u:(\w+) ').firstMatch(text)?.group(1) ?? '?';
      if (action != 'GetTransportInfo' && action != 'GetPositionInfo') {
        actions.add(action);
        bodies.add(text);
      }
      if (unanswered.contains(action)) return;
      final reply = switch (action) {
        'GetTransportInfo' => '<CurrentTransportState>PLAYING</CurrentTransportState>',
        'GetPositionInfo' => '<RelTime>$relTime</RelTime><TrackDuration>01:50:00</TrackDuration>'
            '${trackUri == null ? '' : '<TrackURI>$trackUri</TrackURI>'}',
        _ => '',
      };
      request.response
        ..statusCode = 200
        ..write('<s:Envelope><s:Body>$reply</s:Body></s:Envelope>');
      await request.response.close();
    });
  }

  String get lastUri => bodies[actions.lastIndexOf('SetAVTransportURI')];

  Uri get control => Uri.parse('http://127.0.0.1:${_server.port}/control');
  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _FakeRenderer tv;
  late DlnaPlayer player;
  late List<Duration?> starts;
  late int sessionEnds;

  Future<void> connect({bool transcoding = true}) async {
    player = await DlnaPlayer.connect(
      DlnaRenderer(id: 'tv', name: 'TV', avTransportControlUrl: tv.control),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) async {
        starts.add(startPosition);
        return DlnaStream(
          'http://server/stream',
          transcoding: transcoding,
          startOffset: transcoding ? startPosition ?? Duration.zero : Duration.zero,
        );
      },
      castServerBase: 'http://127.0.0.1:1',
      onSessionEnded: () => sessionEnds++,
      knownDuration: () => const Duration(hours: 2),
    );
  }

  setUp(() async {
    tv = _FakeRenderer();
    await tv.start();
    starts = [];
    sessionEnds = 0;
  });

  tearDown(() async {
    await player.dispose();
    await tv.stop();
  });

  test('a transcode is handed over with the runtime it has left', () async {
    await connect();
    expect(player.transcoding, isNull);
    await player.loadVideo('', true, startPosition: const Duration(minutes: 10));

    expect(tv.lastUri, contains('duration=&quot;1:50:00.000&quot;'));
    // What the player's tag reads while casting.
    expect(player.transcoding, isTrue);
  });

  test('the file itself is handed over with its whole runtime', () async {
    await connect(transcoding: false);
    await player.loadVideo('', true, startPosition: const Duration(minutes: 10));

    expect(tv.lastUri, contains('duration=&quot;2:00:00.000&quot;'));
    expect(player.transcoding, isFalse);
  });

  test('a seek on a transcode restarts the stream there, once for a run of skips', () async {
    await connect();
    await player.loadVideo('', true);
    expect(starts, [Duration.zero]);

    for (final minute in [30, 31, 32]) {
      await player.seek(Duration(minutes: minute));
    }
    expect(player.lastState.position, const Duration(minutes: 32));
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(starts, [Duration.zero, const Duration(minutes: 32)]);
    expect(tv.actions, isNot(contains('Seek')));
    expect(tv.lastUri, contains('duration=&quot;1:28:00.000&quot;'));
    // The television counts from the start of the new stream.
    await Future<void>.delayed(const Duration(milliseconds: 3200));
    expect(player.lastState.position, const Duration(minutes: 32, seconds: 5));
  });

  test('a seek on a paused transcode lands when it is resumed', () async {
    await connect();
    await player.loadVideo('', true);
    await player.pause();
    await player.seek(const Duration(minutes: 40));
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(starts, [Duration.zero]);
    expect(player.lastState.position, const Duration(minutes: 40));

    await player.play();
    expect(starts, [Duration.zero, const Duration(minutes: 40)]);
    expect(tv.actions, isNot(contains('Seek')));
  });

  test('a seek on the file itself is still the television\'s own', () async {
    await connect(transcoding: false);
    await player.loadVideo('', true);
    await player.seek(const Duration(minutes: 30));

    expect(tv.actions, contains('Seek'));
    expect(starts, hasLength(1));
  });

  test('a television that stops answering does not hold a command for good', () async {
    await connect();
    await player.loadVideo('', true);
    tv.unanswered.add('Pause');

    // Returning at all is the point: the call used to wait on the television
    // for as long as it took, which for one that had hung was for ever.
    await player.pause().timeout(const Duration(seconds: 12));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a television given another stream is let go, where this one had got to', () async {
    await connect(transcoding: false);
    await player.loadVideo('', true);
    // Past the settling guard after Play, so the position is the TV's.
    await Future<void>.delayed(const Duration(milliseconds: 3800));
    expect(player.lastState.position, const Duration(seconds: 5));

    // Another phone casts to it: its own address, its own clock.
    tv.trackUri = 'http://192.168.0.9:8200/something-else.mkv';
    tv.relTime = '00:40:00';
    await Future<void>.delayed(const Duration(milliseconds: 1300));

    expect(sessionEnds, 1);
    expect(player.lastState.position, const Duration(seconds: 5));
  });

  test('a television that writes the address its own way is still playing this stream', () async {
    await connect(transcoding: false);
    tv.trackUri = 'http://127.0.0.1:1/stream?seen=1&amp;by=tv';
    await player.loadVideo('', true);
    await Future<void>.delayed(const Duration(milliseconds: 3800));

    expect(sessionEnds, 0);
    expect(player.lastState.position, const Duration(seconds: 5));
  });

  test('a forced transcode asks for what the source is worth', () {
    // A small HEVC film is not blown up to the ceiling.
    expect(dlnaTranscodeBitrate(2500000), 6000000);
    expect(dlnaTranscodeBitrate(5000000), 11000000);
    // A remux stays under it.
    expect(dlnaTranscodeBitrate(30000000), dlnaMaxBitrate);
    // Nothing known about the source: as before.
    expect(dlnaTranscodeBitrate(null), dlnaMaxBitrate);
  });
}

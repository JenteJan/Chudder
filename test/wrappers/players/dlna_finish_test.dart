import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/wrappers/players/dlna_discovery.dart';
import 'package:chudder/wrappers/players/dlna_player.dart';

/// A television that answers the AVTransport calls from a script.
class _FakeRenderer {
  late final HttpServer _server;
  String state = 'PLAYING';
  String relTime = '00:00:00';
  String trackDuration = 'NOT_IMPLEMENTED';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) async {
      final body = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      final text = String.fromCharCodes(body);
      final reply = text.contains('GetTransportInfo')
          ? '<CurrentTransportState>$state</CurrentTransportState>'
          : text.contains('GetPositionInfo')
              ? '<RelTime>$relTime</RelTime><TrackDuration>$trackDuration</TrackDuration>'
              : '';
      request.response
        ..statusCode = 200
        ..write('<s:Envelope><s:Body>$reply</s:Body></s:Envelope>');
      await request.response.close();
    });
  }

  Uri get control => Uri.parse('http://127.0.0.1:${_server.port}/control');
  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _FakeRenderer tv;
  late DlnaPlayer player;
  late int sessionEnds;
  var now = DateTime(2026);

  Future<void> loadWith({Duration? knownDuration}) async {
    player = await DlnaPlayer.connect(
      DlnaRenderer(id: 'tv', name: 'TV', avTransportControlUrl: tv.control),
      streamBuilder: ({audioStreamIndex, subtitleStreamIndex, maxBitrate, startPosition}) async =>
          const DlnaStream('http://server/stream', transcoding: false),
      castServerBase: 'http://127.0.0.1:1',
      onSessionEnded: () => sessionEnds++,
      knownDuration: () => knownDuration,
    );
    player.clock = () => now;
    await player.loadVideo('http://server/stream', true);
  }

  setUp(() async {
    tv = _FakeRenderer();
    await tv.start();
    sessionEnds = 0;
    now = DateTime(2026);
  });

  tearDown(() async {
    await player.dispose();
    await tv.stop();
  });

  Future<void> poll() => Future<void>.delayed(const Duration(milliseconds: 1300));

  test('a stop at the end the TV reports is the episode finishing', () async {
    tv.trackDuration = '00:50:00';
    tv.relTime = '00:30:00';
    await loadWith();
    await poll();

    tv.state = 'STOPPED';
    tv.relTime = '00:49:58';
    await poll();

    expect(player.lastState.completed, isTrue);
    expect(sessionEnds, 0);
  });

  test('a TV that never reports a duration is measured against the episode', () async {
    tv.relTime = '00:49:50';
    await loadWith(knownDuration: const Duration(minutes: 50));
    await poll();

    tv.state = 'STOPPED';
    await poll();

    expect(player.lastState.completed, isTrue);
    expect(sessionEnds, 0);
  });

  test('a TV that finished while the phone was asleep is not read as a stop', () async {
    tv.trackDuration = '00:50:00';
    tv.relTime = '00:44:00';
    await loadWith();
    // Past the settling guard after Play, so the position is the TV's.
    await Future<void>.delayed(const Duration(milliseconds: 3800));
    expect(player.lastState.position, const Duration(minutes: 44));

    // The phone was locked for seven minutes; the TV has since reset its clock.
    now = now.add(const Duration(minutes: 7));
    tv.state = 'STOPPED';
    tv.relTime = '00:00:00';
    await poll();

    expect(player.lastState.completed, isTrue);
    expect(sessionEnds, 0);
  });

  test('a stop in the middle still hands playback back to the phone', () async {
    tv.trackDuration = '00:50:00';
    tv.relTime = '00:20:00';
    await loadWith();
    await poll();

    tv.state = 'STOPPED';
    tv.relTime = '00:20:01';
    await poll();

    expect(player.lastState.completed, isFalse);
    expect(sessionEnds, 1);
  });
}

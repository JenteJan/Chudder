import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/wrappers/players/cast/cast_message_transport.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_cast_protocol.dart';
import 'package:chudder/wrappers/players/cast/jellyfin_receiver_player.dart';

/// A receiver on the other end of a fake link: records what is sent, and
/// answers Stop the way the Jellyfin receiver does.
class _FakeTransport implements CastMessageTransport {
  final sent = <Map<String, dynamic>>[];
  final closes = <bool>[];
  final _messages = StreamController<String>.broadcast();
  final _links = StreamController<CastLinkEvent>.broadcast();

  /// What the receiver answers Identify with; null for an idle receiver.
  String? identifyReply;

  List<String> get commands => sent.map((message) => message['command'] as String).toList();

  void receive(String message) => _messages.add(message);

  void link(CastLinkEvent event) => _links.add(event);

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Stream<CastLinkEvent> get linkEvents => _links.stream;

  @override
  Future<void> sendMessage(String json) async {
    final message = jsonDecode(json) as Map<String, dynamic>;
    sent.add(message);
    switch (message['command']) {
      case 'Identify':
        final reply = identifyReply;
        if (reply != null) scheduleMicrotask(() => receive(reply));
      case 'Stop':
        scheduleMicrotask(() => receive(_report('playbackstop', position: 600)));
    }
  }

  @override
  Future<void> setVolume(double level) async {}

  @override
  Future<void> close({required bool stopReceiver}) async => closes.add(stopReceiver);
}

class _Player extends JellyfinReceiverPlayer {
  _Player(CastMessageTransport transport, JellyfinCastContext context, {required void Function() onSessionEnded})
      : super(transport, context, 'Living room', onSessionEnded: onSessionEnded);
}

String _report(String type, {required int position, bool paused = false, int runtime = 3600, String item = 'item-1'}) =>
    jsonEncode({
      'type': type,
      'data': {
        'ItemId': item,
        'PlayState': {'IsPaused': paused, 'PositionTicks': position * 10000000},
        'NowPlayingItem': {'Id': item, 'RunTimeTicks': runtime * 10000000},
      },
    });

Map<String, dynamic> _stub(String id, {String type = 'Episode'}) =>
    {'Id': id, 'Name': id, 'Type': type, 'MediaType': 'Video', 'IsFolder': false};

JellyfinCastContext _contextWith({List<Map<String, dynamic>> upcoming = const []}) => JellyfinCastContext(
      serverAddress: 'https://server',
      accessToken: 'token',
      userId: 'user',
      deviceId: 'device',
      serverId: 'server',
      serverVersion: '',
      itemStub: _stub('item-1'),
      startPosition: Duration.zero,
      upcoming: upcoming,
    );

final _context = _contextWith();

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late _FakeTransport transport;
  late _Player player;
  late int sessionEnds;

  setUp(() {
    transport = _FakeTransport();
    sessionEnds = 0;
    player = _Player(transport, _context, onSessionEnded: () => sessionEnds++);
  });

  // Cancels the PlayNow retry timers of tests that loaded something.
  tearDown(() => player.leave());

  group('the reply to Identify', () {
    test('is the receiver\'s state, not a stop — the cast carries on', () async {
      transport.identifyReply = _report('playbackstop', position: 600);
      await player.init(VideoPlayerSettingsModel());
      await _settle();

      expect(sessionEnds, 0);
      expect(player.lastState.playing, isTrue);
      expect(player.lastState.position, const Duration(seconds: 600));
    });

    test('after the app comes back to the foreground does not end the cast either', () async {
      await player.init(VideoPlayerSettingsModel());
      transport.identifyReply = _report('playbackstop', position: 900, paused: true);
      await player.onConnectionResumed();
      await _settle();

      expect(sessionEnds, 0);
      expect(player.lastState.playing, isFalse);
      expect(player.lastState.position, const Duration(seconds: 900));
    });

    test('names the item playing, for adopting a running cast', () async {
      transport.identifyReply = _report('playbackstop', position: 60);
      await player.init(VideoPlayerSettingsModel());

      expect(await player.waitForNowPlayingItem(const Duration(seconds: 1)), 'item-1');
    });
  });

  test('a stop nobody here asked for ends the cast, and the receiver is then only left', () async {
    await player.init(VideoPlayerSettingsModel());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Outside the Identify window: someone stopped it on the TV.
    player.debugExpireIdentifyWindow();
    transport.receive(_report('playbackstop', position: 600));
    await _settle();

    expect(sessionEnds, 1);

    await player.dispose();
    expect(transport.closes, [false]);
    expect(transport.commands.where((command) => command == 'Stop'), isEmpty);
  });

  test('the stop that follows our own seek is the stream restarting, not someone taking over', () async {
    await player.init(VideoPlayerSettingsModel());
    player.debugExpireIdentifyWindow();
    await player.seek(const Duration(minutes: 50));
    transport.receive(_report('playbackstop', position: 0));
    await _settle();

    expect(sessionEnds, 0);
  });

  test('the stop at the end of an item carries no position, and still counts as the end', () async {
    await player.init(VideoPlayerSettingsModel());
    player.debugExpireIdentifyWindow();
    transport.receive(_report('playbackprogress', position: 3590));
    transport.receive(_report('playbackstop', position: 0));
    await _settle();

    expect(sessionEnds, 0);
    expect(player.lastState.completed, isTrue);
  });

  test('a stop near the end is the item finishing, not someone taking over', () async {
    await player.init(VideoPlayerSettingsModel());
    player.debugExpireIdentifyWindow();
    transport.receive(_report('playbackprogress', position: 3590));
    transport.receive(_report('playbackstop', position: 3590));
    await _settle();

    expect(sessionEnds, 0);
    expect(player.lastState.completed, isTrue);
  });

  test('stopping casting stops the receiver before closing the session', () async {
    await player.init(VideoPlayerSettingsModel());
    await player.dispose();

    expect(transport.commands.last, 'Stop');
    expect(transport.closes, [true]);
    expect(sessionEnds, 0);
  });

  test('leaving closes the session without stopping the TV, and sends nothing after', () async {
    await player.init(VideoPlayerSettingsModel());
    await player.leave();
    await player.stop();
    await player.dispose();

    expect(transport.commands, ['Identify']);
    expect(transport.closes, [false]);
  });

  test('the transport reporting the session over ends the cast', () async {
    await player.init(VideoPlayerSettingsModel());
    transport.link(CastLinkEvent.ended);
    await _settle();

    expect(sessionEnds, 1);
  });

  test('a dropped link is told apart from the TV stalling', () async {
    await player.init(VideoPlayerSettingsModel());
    expect(player.linkSuspended, isFalse);
    transport.link(CastLinkEvent.suspended);
    await _settle();
    expect(player.linkSuspended, isTrue);

    transport.receive(_report('playbackprogress', position: 10));
    await _settle();
    expect(player.linkSuspended, isFalse);
  });

  test('a receiver that never answers after the link is back ends the cast', () async {
    await player.init(VideoPlayerSettingsModel());
    player.resumeAnswerWait = const Duration(milliseconds: 60);
    transport.link(CastLinkEvent.suspended);
    transport.link(CastLinkEvent.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(sessionEnds, 1);
    expect(player.lastState.buffering, isFalse);
  });

  test('a receiver that answers after the link is back keeps the cast', () async {
    await player.init(VideoPlayerSettingsModel());
    player.resumeAnswerWait = const Duration(milliseconds: 120);
    transport.link(CastLinkEvent.suspended);
    transport.link(CastLinkEvent.resumed);
    await _settle();
    transport.receive(_report('playbackprogress', position: 30));
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(sessionEnds, 0);
  });

  test('a suspended link shows buffering until the receiver answers again', () async {
    await player.init(VideoPlayerSettingsModel());
    transport.link(CastLinkEvent.suspended);
    await _settle();
    expect(player.lastState.buffering, isTrue);

    transport.identifyReply = _report('playbackstop', position: 700);
    transport.link(CastLinkEvent.resumed);
    await _settle();
    expect(player.lastState.buffering, isFalse);
    expect(sessionEnds, 0);
  });

  test('PlayNow always says which subtitle, -1 for none', () async {
    await player.init(VideoPlayerSettingsModel());
    await player.loadVideo('', true);
    final playNow = transport.sent.firstWhere((message) => message['command'] == 'PlayNow');

    expect((playNow['options'] as Map)['subtitleStreamIndex'], -1);
    expect(playNow['receiverName'], 'Living room');
  });

  group('the queue', () {
    List<Map<String, dynamic>> playNowItems() => [
          for (final item in (transport.sent.firstWhere((m) => m['command'] == 'PlayNow')['options'] as Map)['items']
              as List)
            item as Map<String, dynamic>,
        ];

    test('goes to the receiver with the item, so it carries on when the app is gone', () async {
      player = _Player(transport, _contextWith(upcoming: [_stub('item-2'), _stub('item-3')]),
          onSessionEnded: () => sessionEnds++);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);

      expect(playNowItems().map((item) => item['Id']), ['item-1', 'item-2', 'item-3']);
      expect(playNowItems().first['Type'], 'Episode');
    });

    test('a lone episode is sent as a video so the receiver builds no queue of its own', () async {
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);

      expect(playNowItems(), hasLength(1));
      expect(playNowItems().single['Type'], 'Video');
    });

    test('an ended item with more queued waits for the receiver instead of starting the next one', () async {
      player = _Player(transport, _contextWith(upcoming: [_stub('item-2')]), onSessionEnded: () => sessionEnds++);
      final followed = <String>[];
      player.onReceiverChangedItem = (id) async => followed.add(id);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);
      player.debugExpireIdentifyWindow();

      transport.receive(_report('playbackprogress', position: 3590));
      transport.receive(_report('playbackstop', position: 3590));
      await _settle();
      expect(player.lastState.completed, isFalse);
      expect(sessionEnds, 0);

      transport.receive(_report('playbackstart', position: 1, item: 'item-2'));
      await _settle();
      expect(followed, ['item-2']);
      expect(player.lastState.completed, isFalse);
    });

    test('the app carries on from its own queue when the receiver does not move on', () async {
      player = _Player(transport, _contextWith(upcoming: [_stub('item-2')]), onSessionEnded: () => sessionEnds++)
        ..advanceWait = const Duration(milliseconds: 30);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);
      player.debugExpireIdentifyWindow();

      transport.receive(_report('playbackprogress', position: 3590));
      transport.receive(_report('playbackstop', position: 3590));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(player.lastState.completed, isTrue);
    });

    test('the last item ending completes at once', () async {
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);
      player.debugExpireIdentifyWindow();

      transport.receive(_report('playbackprogress', position: 3590));
      transport.receive(_report('playbackstop', position: 3590));
      await _settle();

      expect(player.lastState.completed, isTrue);
    });

    test('a skip with the TV remote is followed, once', () async {
      final followed = <String>[];
      player.onReceiverChangedItem = (id) async => followed.add(id);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);

      transport.receive(_report('playbackstart', position: 1));
      transport.receive(_report('playbackprogress', position: 10, item: 'item-5'));
      transport.receive(_report('playbackprogress', position: 11, item: 'item-5'));
      await _settle();

      expect(followed, ['item-5']);
    });

    test('reports of the item just left do not drag the app back', () async {
      final followed = <String>[];
      player.onReceiverChangedItem = (id) async => followed.add(id);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);

      player.updateItem(itemStub: _stub('item-2'));
      transport.receive(_report('playbackprogress', position: 3000));
      await _settle();

      expect(followed, isEmpty);
    });

    test('a TV still on an earlier cast is not followed while our item is on its way', () async {
      final followed = <String>[];
      player.onReceiverChangedItem = (id) async => followed.add(id);
      transport.identifyReply = _report('playbackstop', position: 500, item: 'item-9');
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);
      transport.receive(_report('playbackprogress', position: 501, item: 'item-9'));
      await _settle();
      expect(followed, isEmpty);

      // Ours is playing now; what the receiver plays after it is its own doing.
      transport.receive(_report('playbackstart', position: 1));
      transport.receive(_report('playbackstart', position: 1, item: 'item-2'));
      await _settle();
      expect(followed, ['item-2']);
    });

    test('the reply to Identify after a resume shows an item the receiver moved on to', () async {
      final followed = <String>[];
      player.onReceiverChangedItem = (id) async => followed.add(id);
      await player.init(VideoPlayerSettingsModel());
      await player.loadVideo('', true);
      transport.receive(_report('playbackstart', position: 1));

      transport.identifyReply = _report('playbackstop', position: 30, item: 'item-2');
      await player.onConnectionResumed();
      await _settle();

      expect(followed, ['item-2']);
      expect(sessionEnds, 0);
    });
  });

  test('a receiver error stops the spinner and shows the error', () async {
    await player.init(VideoPlayerSettingsModel());
    await player.loadVideo('', true);
    transport.receive(jsonEncode({'type': 'connectionerror', 'message': ''}));
    await _settle();

    expect(player.lastState.buffering, isFalse);
    expect(player.lastState.error, isTrue);
  });
}

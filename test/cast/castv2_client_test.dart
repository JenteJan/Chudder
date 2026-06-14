import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/wrappers/players/cast/castv2/cast_message.dart';
import 'package:fladder/wrappers/players/cast/castv2/cast_protocol.dart';
import 'package:fladder/wrappers/players/cast/castv2/castv2_client.dart';

/// In-memory [CastSocket]: records framed messages the client sends and lets a
/// test push framed messages back as if from the receiver.
class FakeCastSocket implements CastSocket {
  final _incoming = StreamController<List<int>>();
  final List<CastMessage> sent = [];
  bool closed = false;

  @override
  Stream<List<int>> get stream => _incoming.stream;

  @override
  void add(List<int> data) {
    // The client always writes one full frame per add().
    final framer = CastFramer();
    sent.addAll(framer.addBytes(data));
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// Simulates the receiver sending [payload] on [namespace] from [source].
  void receive(String namespace, String payload, {String source = 'receiver-0'}) {
    _incoming.add(CastMessage.string(
      sourceId: source,
      destinationId: 'sender-0',
      namespace: namespace,
      payload: payload,
    ).frame());
  }

  List<CastMessage> sentOn(String namespace) =>
      sent.where((m) => m.namespace == namespace).toList();
}

void main() {
  test('start opens a virtual connection to the platform receiver', () {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    final connects = socket.sentOn(CastProtocol.tpConnection);
    expect(connects, hasLength(1));
    expect(connects.single.destinationId, CastProtocol.platformReceiverId);
    expect(CastProtocol.messageType(connects.single.payloadUtf8!), 'CONNECT');

    client.close();
  });

  test('auto-replies PONG to a heartbeat PING', () async {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    socket.receive(CastProtocol.tpHeartbeat, CastProtocol.ping());
    await Future<void>.delayed(Duration.zero);

    final pongs = socket.sentOn(CastProtocol.tpHeartbeat).where(
        (m) => CastProtocol.messageType(m.payloadUtf8!) == 'PONG');
    expect(pongs, isNotEmpty);

    client.close();
  });

  test('launch resolves with the transport id and connects to the app', () async {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    final future = client.launch('F007D354');

    // The LAUNCH must have gone out with a requestId we can echo back.
    final launch = socket.sentOn(CastProtocol.receiver).single;
    final requestId = (jsonDecode(launch.payloadUtf8!) as Map)['requestId'] as int;
    expect(jsonDecode(launch.payloadUtf8!)['type'], 'LAUNCH');

    socket.receive(
      CastProtocol.receiver,
      jsonEncode({
        'requestId': requestId,
        'type': 'RECEIVER_STATUS',
        'status': {
          'applications': [
            {
              'appId': 'F007D354',
              'transportId': 'web-42',
              'namespaces': [
                {'name': CastProtocol.jellyfin}
              ],
            }
          ],
        },
      }),
    );

    final status = await future;
    expect(status.transportFor('F007D354'), 'web-42');

    // A virtual connection should now be open to the launched app.
    final appConnect = socket
        .sentOn(CastProtocol.tpConnection)
        .where((m) => m.destinationId == 'web-42');
    expect(appConnect, isNotEmpty);

    client.close();
  });

  test('launch times out if the receiver never replies', () async {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    await expectLater(
      client.launch('F007D354', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );

    client.close();
  });

  test('customMessages surfaces Jellyfin-namespace payloads only', () async {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    final received = <String>[];
    final sub = client.customMessages.listen(received.add);

    socket.receive(CastProtocol.jellyfin, '{"type":"playbackstart"}');
    socket.receive(CastProtocol.media, '{"type":"MEDIA_STATUS","status":[]}');
    socket.receive(CastProtocol.jellyfin, '{"type":"playbackprogress"}');
    await Future<void>.delayed(Duration.zero);

    expect(received, ['{"type":"playbackstart"}', '{"type":"playbackprogress"}']);

    await sub.cancel();
    client.close();
  });

  test('sendCustom targets the app transport on the Jellyfin namespace', () {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    client.sendCustom('web-42', '{"command":"Pause"}');

    final msg = socket.sentOn(CastProtocol.jellyfin).single;
    expect(msg.destinationId, 'web-42');
    expect(msg.payloadUtf8, '{"command":"Pause"}');

    client.close();
  });

  test('requestIds increment per request', () async {
    final socket = FakeCastSocket();
    final client = Castv2Client(socket)..start();

    unawaited(client.launch('A').catchError((_) => const ReceiverStatus()));
    unawaited(client.setVolume(0.5).catchError((_) {}));

    final ids = <int>[
      for (final m in socket.sent)
        if (m.payloadUtf8 != null && (jsonDecode(m.payloadUtf8!) as Map)['requestId'] is int)
          (jsonDecode(m.payloadUtf8!) as Map)['requestId'] as int
    ];
    // Distinct, monotonically increasing ids across the two requests.
    expect(ids.toSet().length, ids.length);
    expect(ids, equals([...ids]..sort()));

    client.close();
  });
}

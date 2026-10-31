// Is sim_server.dart still the real thing? The same random requests go to the
// port and to a real server, and what each session is sent has to match, frame
// by frame. Only runs when pointed at a server you may make groups on:
//   flutter test test/syncplay_sim/server_differential_test.dart \
//     --dart-define=LIVE_SERVER=https://host --dart-define=DIFF_RUNS=60
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'sim_server.dart';

const server = String.fromEnvironment('LIVE_SERVER');
const runs = int.fromEnvironment('DIFF_RUNS', defaultValue: 40);
const from = int.fromEnvironment('DIFF_FROM', defaultValue: 1);
const report = String.fromEnvironment('DIFF_REPORT');
const gapMs = 350;

/// One request by session 0 or 1.
class Req {
  const Req(this.who, this.kind, [this.arg = 0]);
  final int who;
  final String kind;
  final int arg;
  @override
  String toString() => '$who:$kind${arg == 0 ? '' : '($arg)'}';
}

List<Req> randomRequests(int seed) {
  final r = Random(seed);
  const kinds = [
    'pause', 'unpause', 'seek', 'readyHere', 'readyHere', 'readyPlaying', 'readyFar', 'readyWrongItem', //
    'buffering', 'next', 'previous', 'queue', 'join', 'leave', 'ping', 'stop',
  ];
  return [
    const Req(0, 'new'),
    const Req(0, 'queue'),
    const Req(0, 'readyHere'),
    for (var i = 0; i < 4 + r.nextInt(6); i++) Req(r.nextInt(2), kinds[r.nextInt(kinds.length)], 1 + r.nextInt(3)),
  ];
}

/// What a frame says, without what the clock or the ids make different.
String? normalise(Map<String, dynamic> frame) {
  final kind = frame['MessageType'];
  final data = frame['Data'];
  if (kind == 'SyncPlayCommand') {
    final d = data as Map<String, dynamic>;
    final exact = d['Command'] == 'Seek' ? ' at ${(d['PositionTicks'] as int) ~/ 10000000}' : '';
    return 'cmd ${d['Command']}$exact';
  }
  if (kind != 'SyncPlayGroupUpdate') return null;
  final d = data as Map<String, dynamic>;
  final type = d['Type'];
  final inner = d['Data'];
  return switch (type) {
    'StateUpdate' => 'state ${inner['State']}/${inner['Reason']}',
    'PlayQueue' => 'queue ${inner['Reason']} n=${(inner['Playlist'] as List).length} at=${inner['PlayingItemIndex']}',
    'GroupJoined' => 'joined ${inner['State']}',
    _ => '$type',
  };
}

const items = ['a0000000000000000000000000000000', 'b0000000000000000000000000000000', 'c0000000000000000000000000000000'];
const runTimeTicks = 3000 * 10000000;

/// The sequence on the port, with nothing between the sessions and the server.
List<List<String>> onPort(List<Req> requests) {
  final seen = [<String>[], <String>[]];
  FakeAsync(initialTime: DateTime.utc(2026, 10, 31)).run((async) {
    final port = SimServer(runTimeOf: (_) => runTimeTicks);
    final sessions = [
      for (var i = 0; i < 2; i++)
        SimSession('s$i', 'demo', (frame) {
          final text = normalise(json.decode(json.encode(frame)) as Map<String, dynamic>);
          if (text != null) seen[i].add(text);
        }),
    ];
    String? groupId;
    for (final req in requests) {
      final s = sessions[req.who];
      final g = port.groupOf(s);
      final position = g?.currentTicks ?? 0;
      final place = g?.playingPlaceId;
      Map<String, dynamic> body({bool playing = false, int? ticks, String? item}) => {
            'When': port.now.toIso8601String(),
            'PositionTicks': ticks ?? position,
            'IsPlaying': playing,
            'PlaylistItemId': item ?? place,
          };
      switch (req.kind) {
        case 'new':
          port.newGroup(s, 'diff');
          groupId = port.groupOf(s)?.groupId;
        case 'join':
          if (groupId != null) port.join(s, groupId);
        case 'leave':
          port.leave(s);
        default:
          port.inGroup(s, (g) {
            switch (req.kind) {
              case 'queue':
                g.play(s, items, 0, 60 * 10000000);
              case 'pause':
                g.pause(s);
              case 'unpause':
                g.unpause(s);
              case 'stop':
                g.stop(s);
              case 'seek':
                g.seek(s, 100 * req.arg * 10000000);
              case 'readyHere':
                g.ready(s, body());
              case 'readyPlaying':
                g.ready(s, body(playing: true));
              case 'readyFar':
                g.ready(s, body(ticks: position + 40 * 10000000));
              case 'readyWrongItem':
                g.ready(s, body(item: zeroGuid));
              case 'buffering':
                g.buffering(s, body());
              case 'next':
                g.stepItem(s, 1, place, 'NextItem');
              case 'previous':
                g.stepItem(s, -1, place, 'PreviousItem');
              case 'ping':
                g.updatePing(s, 20);
            }
          });
      }
      async.elapse(const Duration(milliseconds: gapMs));
    }
    final kept = [List.of(seen[0]), List.of(seen[1])];
    for (final s in sessions) {
      port.leaveIfIn(s);
    }
    port.close();
    seen
      ..clear()
      ..addAll(kept);
  });
  return seen;
}

class _Live {
  _Live(this.name);
  final String name;
  late String token;
  late WebSocket socket;
  final seen = <String>[];
  Map<String, dynamic>? lastCommand;
  String place = zeroGuid;

  /// Where the last queue started, and when the group got that far.
  int queueStart = 0;
  DateTime queueAt = DateTime.utc(2000);

  Map<String, String> get headers => {
        'Authorization': 'MediaBrowser Client="ChudderDiff", Device="$name", DeviceId="diff-$name", Version="1", Token="$token"',
        'Content-Type': 'application/json',
      };

  Future<void> open() async {
    token = '';
    final auth = await http.post(Uri.parse('$server/Users/AuthenticateByName'),
        headers: headers, body: json.encode({'Username': 'demo', 'Pw': 'demo'}));
    token = (json.decode(auth.body) as Map<String, dynamic>)['AccessToken'] as String;
    final host = server.replaceFirst('https://', 'wss://');
    socket = await WebSocket.connect('$host/socket?ApiKey=$token&api_key=$token&deviceId=diff-$name');
    socket.listen((raw) {
      final frame = json.decode(raw as String) as Map<String, dynamic>;
      if (frame['MessageType'] == 'ForceKeepAlive') socket.add(json.encode({'MessageType': 'KeepAlive'}));
      final text = normalise(frame);
      if (text == null) return;
      seen.add(text);
      if (frame['MessageType'] == 'SyncPlayCommand') {
        lastCommand = frame['Data'] as Map<String, dynamic>;
        place = lastCommand!['PlaylistItemId'] as String;
      } else {
        final d = frame['Data'] as Map<String, dynamic>;
        if (d['Type'] == 'PlayQueue') {
          final inner = d['Data'] as Map<String, dynamic>;
          queueStart = inner['StartPositionTicks'] as int;
          queueAt = DateTime.now();
          lastCommand = null;
          final list = inner['Playlist'] as List;
          final at = inner['PlayingItemIndex'] as int;
          place = at >= 0 && at < list.length ? list[at]['PlaylistItemId'] as String : zeroGuid;
        }
      }
    });
  }

  Future<http.Response> post(String path, [Map<String, dynamic>? body]) =>
      http.post(Uri.parse('$server/SyncPlay/$path'), headers: headers, body: json.encode(body ?? {}));
}

Future<List<List<String>>> onLive(List<Req> requests, List<String> ids) async {
  final sessions = [_Live('a'), _Live('b')];
  for (final s in sessions) {
    await s.open();
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  String? groupId;

  int estimate(_Live s) {
    // Whichever session heard last knows best.
    final latest = sessions[0].queueAt.isAfter(sessions[1].queueAt) ? sessions[0] : sessions[1];
    final c = s.lastCommand ?? latest.lastCommand;
    if (c == null) return latest.queueStart;
    final pos = c['PositionTicks'] as int;
    if (c['Command'] != 'Unpause') return pos;
    final elapsed = DateTime.now().toUtc().difference(DateTime.parse(c['When'] as String)).inMicroseconds * 10;
    return pos + (elapsed > 0 ? elapsed : 0);
  }

  for (final req in requests) {
    final s = sessions[req.who];
    final start = DateTime.now();
    final position = estimate(s);
    Map<String, dynamic> body({bool playing = false, int? ticks, String? item}) => {
          'When': DateTime.now().toUtc().toIso8601String(),
          'PositionTicks': ticks ?? position,
          'IsPlaying': playing,
          'PlaylistItemId': item ?? s.place,
        };
    switch (req.kind) {
      case 'new':
        final r = await s.post('New', {'GroupName': 'diff'});
        groupId = (json.decode(r.body) as Map<String, dynamic>)['GroupId'] as String;
      case 'join':
        if (groupId != null) await s.post('Join', {'GroupId': groupId});
      case 'leave':
        await s.post('Leave');
      case 'queue':
        await s.post('SetNewQueue', {'PlayingQueue': ids, 'PlayingItemPosition': 0, 'StartPositionTicks': 60 * 10000000});
      case 'pause':
        await s.post('Pause');
      case 'unpause':
        await s.post('Unpause');
      case 'stop':
        await s.post('Stop');
      case 'seek':
        await s.post('Seek', {'PositionTicks': 100 * req.arg * 10000000});
      case 'readyHere':
        await s.post('Ready', body());
      case 'readyPlaying':
        await s.post('Ready', body(playing: true));
      case 'readyFar':
        await s.post('Ready', body(ticks: position + 40 * 10000000));
      case 'readyWrongItem':
        await s.post('Ready', body(item: zeroGuid));
      case 'buffering':
        await s.post('Buffering', body());
      case 'next':
        await s.post('NextItem', {'PlaylistItemId': s.place});
      case 'previous':
        await s.post('PreviousItem', {'PlaylistItemId': s.place});
      case 'ping':
        await s.post('Ping', {'Ping': 20});
    }
    final left = gapMs - DateTime.now().difference(start).inMilliseconds;
    await Future<void>.delayed(Duration(milliseconds: left > 60 ? left : 60));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  final out = [List.of(sessions[0].seen), List.of(sessions[1].seen)];
  for (final s in sessions) {
    await s.post('Leave');
    await s.socket.close();
  }
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return out;
}

void main() {
  test('the port answers as the real server does', () async {
    final auth = await http.post(
      Uri.parse('$server/Users/AuthenticateByName'),
      headers: {
        'Authorization': 'MediaBrowser Client="ChudderDiff", Device="setup", DeviceId="diff-setup", Version="1"',
        'Content-Type': 'application/json',
      },
      body: json.encode({'Username': 'demo', 'Pw': 'demo'}),
    );
    final login = json.decode(auth.body) as Map<String, dynamic>;
    final uid = (login['User'] as Map<String, dynamic>)['Id'];
    final list = await http.get(
      Uri.parse('$server/Users/$uid/Items?IncludeItemTypes=Movie&Recursive=true&SortBy=Runtime&SortOrder=Descending&Limit=3'),
      headers: {'Authorization': 'MediaBrowser Token="${login['AccessToken']}"'},
    );
    final ids = [for (final i in (json.decode(list.body) as Map<String, dynamic>)['Items'] as List) i['Id'] as String];

    final out = StringBuffer();
    var differing = 0;
    for (var seed = from; seed < from + runs; seed++) {
      final requests = randomRequests(seed);
      final port = onPort(requests);
      final live = await onLive(requests, ids);
      for (var i = 0; i < 2; i++) {
        if (port[i].join('|') != live[i].join('|')) {
          differing++;
          out
            ..writeln('seed $seed session $i: $requests')
            ..writeln('  port ${port[i].join(' | ')}')
            ..writeln('  live ${live[i].join(' | ')}');
          break;
        }
      }
    }
    // ignore: avoid_print
    print('$differing of $runs sequences differ');
    if (report.isNotEmpty) File(report).writeAsStringSync('$differing of $runs differ\n$out');
    expect(differing, 0, reason: out.toString());
  }, skip: server.isEmpty ? 'needs --dart-define=LIVE_SERVER' : false, timeout: const Timeout(Duration(hours: 2)));
}

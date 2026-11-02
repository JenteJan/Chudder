// Random and exhaustive runs of a group, and what must hold after each.
import 'dart:async';
import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/syncplay/syncplay_models.dart';
import 'package:chudder/providers/video_player_provider.dart';

import 'sim_server.dart';
import 'sim_world.dart';

enum Act {
  pause,
  play,
  seek,
  seekNearEnd,
  next,
  previous,
  stall,
  slowLoad,
  dropSocket,
  leaveAndRejoin,
  loneEpisode,
  closePlayer,
  reopenPlayer,
  leaveForGood,
  lateJoin,
  groupStop,
}

class Step {
  const Step(this.atMs, this.member, this.act, this.arg);
  final int atMs;
  final int member;
  final Act act;
  final int arg;
  @override
  String toString() => '@${atMs}ms m$member ${act.name}($arg)';
}

/// How the group came to be.
enum Start { createdWhilePlaying, createdWhilePaused, createdThenQueued, playingThenHandedQueue }

class Scenario {
  const Scenario(this.seed, this.start, this.links, this.skewMs, this.overrunMs, this.steps);
  final int seed;
  final Start start;
  final List<Link> links;
  final int skewMs;
  final int overrunMs;
  final List<Step> steps;

  Scenario withSteps(List<Step> steps) => Scenario(seed, start, links, skewMs, overrunMs, steps);

  @override
  String toString() => 'seed=$seed ${start.name} links=${links.map((l) => l.name).join(',')} skew=$skewMs '
      'overrun=$overrunMs steps=${steps.join(' ')}';

  static Scenario random(int seed, {int? steps}) {
    final r = Random(seed);
    const links = [Link.lan, Link.lan, Link.wan, Link.bad];
    final members = 2 + (r.nextInt(3) == 0 ? 1 : 0) + (r.nextInt(8) == 0 ? 1 : 0);
    var at = 3000;
    final count = steps ?? 1 + r.nextInt(8);
    final list = <Step>[];
    for (var i = 0; i < count; i++) {
      at += const [40, 150, 400, 900, 2500, 6000][r.nextInt(6)] + r.nextInt(200);
      final act = Act.values[r.nextInt(Act.values.length)];
      final arg = switch (act) {
        Act.seek => 60 + r.nextInt(1500),
        Act.stall => const [300, 900, 3000, 8000][r.nextInt(4)],
        Act.slowLoad => const [1500, 5000, 12000][r.nextInt(3)],
        Act.dropSocket => const [800, 3000, 9000][r.nextInt(3)],
        Act.leaveAndRejoin => const [500, 4000][r.nextInt(2)],
        Act.loneEpisode => r.nextInt(episodeCount),
        _ => 0,
      };
      list.add(Step(at, r.nextInt(members), act, arg));
    }
    return Scenario(
      seed,
      Start.values[r.nextInt(Start.values.length)],
      [for (var i = 0; i < members; i++) links[r.nextInt(links.length)]],
      const [0, -118, 2300][r.nextInt(3)],
      const [0, 2700][r.nextInt(2)],
      list,
    );
  }
}

/// What an action takes as its argument in the exhaustive runs.
int plainArg(Act act) => switch (act) {
      Act.seek => 700,
      Act.stall => 3000,
      Act.slowLoad => 5000,
      Act.dropSocket => 3000,
      Act.leaveAndRejoin => 1000,
      Act.loneEpisode => 4,
      _ => 0,
    };

/// The [index]th of every pair of steps: each action by each member, followed
/// by each other at each gap, from each way a group can start, over a good
/// and a bad link.
Scenario pairScenario(int index) {
  const gaps = [50, 600, 3000];
  const starts = Start.values;
  const linkSets = [
    [Link.lan, Link.lan, Link.lan],
    [Link.lan, Link.bad, Link.wan],
  ];
  // The first fifteen: an index names the same pair for as long as it is kept.
  final actions = [
    for (var member = 0; member < 3; member++)
      for (final act in Act.values.take(15)) (member: member, act: act),
  ];
  var i = index;
  int take(int n) {
    final v = i % n;
    i ~/= n;
    return v;
  }

  final first = actions[take(actions.length)];
  final second = actions[take(actions.length)];
  final gap = gaps[take(gaps.length)];
  final start = starts[take(starts.length)];
  final links = linkSets[take(linkSets.length)];
  return Scenario(index, start, links, 0, 2700, [
    Step(4000, first.member, first.act, plainArg(first.act)),
    Step(4000 + gap, second.member, second.act, plainArg(second.act)),
  ]);
}

int get pairCount => 45 * 45 * 3 * 4 * 2;

/// The [index]th of every pair with a group Stop in it, on either side.
Scenario stopScenario(int index) {
  const gaps = [50, 600, 3000];
  const linkSets = [
    [Link.lan, Link.lan, Link.lan],
    [Link.lan, Link.bad, Link.wan],
  ];
  final others = [
    for (var member = 0; member < 3; member++)
      for (final act in Act.values) (member: member, act: act),
  ];
  var i = index;
  int take(int n) {
    final v = i % n;
    i ~/= n;
    return v;
  }

  final stopper = take(3);
  final other = others[take(others.length)];
  final stopFirst = take(2) == 0;
  final gap = gaps[take(gaps.length)];
  final start = Start.values[take(Start.values.length)];
  final links = linkSets[take(linkSets.length)];
  final stop = (member: stopper, act: Act.groupStop);
  final (first, second) = stopFirst ? (stop, other) : (other, stop);
  return Scenario(index, start, links, 0, 2700, [
    Step(4000, first.member, first.act, plainArg(first.act)),
    Step(4000 + gap, second.member, second.act, plainArg(second.act)),
  ]);
}

int get stopCount => 3 * 48 * 2 * 3 * 4 * 2;

class Outcome {
  Outcome(this.scenario, this.problems, this.trace, this.virtualMs);
  final Scenario scenario;
  final List<String> problems;
  final List<String> trace;
  final int virtualMs;
  bool get failed => problems.isNotEmpty;
}

final _trace = <String>[];
bool _listening = false;

void _listen() {
  if (_listening) return;
  _listening = true;
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    if (r.loggerName == 'SyncPlay' && !r.message.contains('Time sync') && !r.message.contains('Received WebSocket')) {
      _trace.add(r.message);
    }
  });
}

Outcome runScenario(Scenario s, SharedPreferences prefs, {bool keepTrace = false}) {
  _listen();
  _trace.clear();
  final problems = <String>[];
  final fake = FakeAsync(initialTime: DateTime.utc(2026, 10, 30, 21));
  var settledAt = 0;
  fake.run((async) {
    runZonedGuarded(() {
      final world = SimWorld(Random(s.seed), prefs, clockSkew: Duration(milliseconds: s.skewMs));
      for (var i = 0; i < s.links.length; i++) {
        final m = SimMember(world, 'm$i', s.links[i], prefs);
        m.sim.fileOverrun = Duration(milliseconds: s.overrunMs);
        world.members.add(m);
      }
      final a = world.members.first;

      Future<void> open() async {
        for (final m in world.members) {
          await m.sync.connect();
        }
        final first = a.helper;
        if (s.start == Start.playingThenHandedQueue) {
          final built = a.lonelyModel(a.firstEpisodes.elementAt(1));
          await a.player.loadPlaybackItem(built, const Duration(seconds: 20), waitForSyncPlayCommand: false);
          await Future<void>.delayed(const Duration(milliseconds: 600));
        } else if (s.start != Start.createdThenQueued) {
          final built = await first.createPlaybackModel(null, a.firstEpisodes.elementAt(1));
          await a.player.loadPlaybackItem(built!, const Duration(seconds: 20), waitForSyncPlayCommand: false);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await a.reportStarted(built);
          if (s.start == Start.createdWhilePaused) await a.sim.pause();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await a.sync.createGroup('sim');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (s.start == Start.createdThenQueued || s.start == Start.playingThenHandedQueue) {
          await a.sync.setNewQueue(
            itemIds: [for (var i = 0; i < episodeCount; i++) 'ep$i'],
            playingItemPosition: 1,
            startPositionTicks: 20 * ticksPerSecond,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 900));
        final groupId = a.group.groupId;
        if (groupId == null) throw StateError('no group');
        for (final (i, m) in world.members.indexed.skip(1)) {
          if (s.steps.any((st) => st.act == Act.lateJoin && st.member == i)) {
            m.outside = true;
            continue;
          }
          await m.sync.joinGroup(groupId);
        }
      }

      unawaited(open());

      var groupId = '';
      Timer(const Duration(milliseconds: 2500), () => groupId = a.group.groupId ?? '');

      for (final step in s.steps) {
        Timer(Duration(milliseconds: step.atMs), () {
          final m = world.members[step.member];
          if (!m.online) return;
          final inGroup = m.group.isInGroup;
          switch (step.act) {
            case Act.pause:
              if (inGroup) unawaited(m.player.userPause());
            case Act.play:
              if (inGroup) unawaited(m.player.userPlay());
            case Act.seek:
              if (inGroup) unawaited(m.player.userSeek(Duration(seconds: step.arg)));
            case Act.seekNearEnd:
              if (inGroup) unawaited(m.player.userSeek(episodeLength - const Duration(seconds: 4)));
            case Act.next:
              final next = m.model?.nextVideo;
              if (inGroup && next != null) unawaited(m.helper.loadNewVideo(next));
            case Act.previous:
              final previous = m.model?.previousVideo;
              if (inGroup && previous != null) unawaited(m.helper.loadNewVideo(previous));
            case Act.stall:
              if (m.sim.running) m.sim.stall(Duration(milliseconds: step.arg));
            case Act.slowLoad:
              m.sim.loadTime = Duration(milliseconds: step.arg);
              Timer(const Duration(seconds: 15), () => m.sim.loadTime = const Duration(milliseconds: 300));
            case Act.dropSocket:
              m.dropSocket(Duration(milliseconds: step.arg));
            case Act.leaveAndRejoin:
              if (inGroup) {
                unawaited(m.sync.leaveGroup().then((_) async {
                  await Future<void>.delayed(Duration(milliseconds: step.arg));
                  if (world.server.groups.containsKey(groupId)) await m.sync.joinGroup(groupId);
                }));
              }
            case Act.loneEpisode:
              if (inGroup) unawaited(m.sync.setNewQueue(itemIds: ['ep${step.arg}']));
            case Act.closePlayer:
              if (inGroup && m.model != null) {
                m.closed = true;
                m.container.read(isVideoPlayerRouteOpenProvider.notifier).state = false;
                unawaited(m.container.read(videoPlayerProvider).stop());
              }
            case Act.reopenPlayer:
              if (inGroup && m.closed) {
                m.closed = false;
                unawaited(m.sync.rejoinPlayback());
              }
            case Act.leaveForGood:
              if (inGroup) {
                m.outside = true;
                unawaited(m.sync.leaveGroup());
              }
            case Act.lateJoin:
              if (m.outside && !inGroup && world.server.groups.containsKey(groupId)) {
                m.outside = false;
                unawaited(m.sync.joinGroup(groupId));
              }
            case Act.groupStop:
              // Sent as jellyfin-web sends it: Chudder has no button for it.
              if (inGroup) world.server.groups[groupId]?.stop(m.session);
          }
        });
      }

      final last = s.steps.isEmpty ? 3000 : s.steps.last.atMs;
      settledAt = last + 42000;
      Timer(Duration(milliseconds: settledAt), () => problems.addAll(_check(world, s)));
    }, (e, st) {
      problems.add('exception: ${e.toString().split('\n').first} @ ${st.toString().split('\n').take(3).join(' | ')}');
    });
    async.elapse(Duration(milliseconds: settledAt + 50));
  });
  return Outcome(s, problems, keepTrace ? List.of(_trace) : const [], settledAt);
}

/// Long stalls and loads are allowed to run out the server's wait: then the
/// member really is not there.
bool _mayHitDeadline(Scenario s) => s.steps.any((st) =>
    st.act == Act.slowLoad ||
    st.act == Act.dropSocket ||
    st.act == Act.leaveAndRejoin ||
    st.act == Act.closePlayer ||
    st.act == Act.reopenPlayer ||
    (st.act == Act.stall && st.arg > 20000));

List<String> _check(SimWorld world, Scenario s) {
  final problems = <String>[];
  final stats = world.server.stats;
  if (stats.deadlines > 0 && !_mayHitDeadline(s)) problems.add('deadline: the group waited out 30 s');
  if (stats.refusedReadies > 30) problems.add('refusals: ${stats.refusedReadies} Readies refused');
  if (world.server.groups.isEmpty) return problems;
  final group = world.server.groups.values.first;
  final type = group.type;
  if (type == GroupStateType.waiting) problems.add('stuck: group still Waiting at the end');
  final inGroup = world.members.where((m) => group.memberIds.contains(m.session.id)).toList();
  for (final m in world.members) {
    if (m.outside) continue;
    if (!inGroup.contains(m) && m.group.isInGroup) problems.add('split: ${m.name} believes it is in, server disagrees');
    if (inGroup.contains(m) && !m.group.isInGroup) problems.add('split: ${m.name} believes it left, server has it');
  }
  final groupTicks = group.currentTicks;
  for (final m in inGroup) {
    if (m.closed) continue;
    if (m.group.groupState.name != type.name) {
      problems.add('state: ${m.name} says ${m.group.groupState.name}, server ${type.name}');
    }
    // Stopped, the server keeps its queue and every player has closed. One
    // that left first was on its own by then, and joins back as it stands.
    if (type == GroupStateType.idle) {
      const leaving = [Act.leaveAndRejoin, Act.leaveForGood, Act.lateJoin];
      final left = s.steps.any((st) => leaving.contains(st.act) && world.members[st.member] == m);
      if (m.model != null && !left) problems.add('running: ${m.name} still has a player in a stopped group');
      continue;
    }
    final item = group.playingItemId;
    if (item != null && m.model == null) problems.add('item: ${m.name} has nothing loaded');
    if (item != null && m.model != null && m.model!.item.id != item) {
      problems.add('item: ${m.name} on ${m.model!.item.id}, group on $item');
      continue;
    }
    final groupNext = group.nextItemId;
    if (item != null && m.model != null && groupNext != null && m.model!.nextVideo?.id != groupNext) {
      problems.add('queue: ${m.name} would go on to ${m.model!.nextVideo?.id}, the group to $groupNext');
    }
    final atEnd = m.sim.atEnd || groupTicks >= episodeLength.inMicroseconds * 10;
    if (item == null || atEnd) continue;
    if (type == GroupStateType.playing && !m.sim.running) problems.add('stopped: ${m.name} stands in a playing group');
    if (type == GroupStateType.paused && m.sim.running) problems.add('running: ${m.name} runs in a paused group');
    final off = (m.sim.position.inMicroseconds * 10 - groupTicks).abs() ~/ ticksPerMs;
    final allowed = type == GroupStateType.playing ? 600 + 2 * m.link.baseMs + 2 * m.link.jitterMs : 1100;
    if (off > allowed) problems.add('apart: ${m.name} ${off}ms from the group (${type.name})');
  }
  return problems;
}

/// The shortest list of steps that still fails the same way.
Outcome shrink(Outcome failing, SharedPreferences prefs) {
  String kind(Outcome o) => o.problems.first.split(':').first;
  final want = kind(failing);
  var current = failing;
  var changed = true;
  while (changed) {
    changed = false;
    for (var i = 0; i < current.scenario.steps.length; i++) {
      final fewer = [...current.scenario.steps]..removeAt(i);
      final attempt = runScenario(current.scenario.withSteps(fewer), prefs);
      if (attempt.failed && kind(attempt) == want) {
        current = attempt;
        changed = true;
        break;
      }
    }
  }
  return runScenario(current.scenario, prefs, keepTrace: true);
}

// Jellyfin 12.2's SyncPlay, ported from Group.cs and the *GroupState.cs files
// at tag v12.2: same states, same order of operations, same numbers. Kept
// beside the client tests so the real client code can run against it on a
// virtual clock. tool/syncplay_probe/live checks it against a real server.
import 'dart:async';

import 'package:clock/clock.dart';

const ticksPerMs = 10000;
const zeroGuid = '00000000000000000000000000000000';

const defaultPing = 500;
const maxPing = 10000;
const timeSyncOffsetMs = 2000;
const maxPlaybackOffsetMs = 500;
const maxCatchUpOffsetMs = 60000;
const groupWaitTimeoutMs = 30000;

enum GroupStateType { idle, waiting, paused, playing }

extension on GroupStateType {
  String get wire => switch (this) {
        GroupStateType.idle => 'Idle',
        GroupStateType.waiting => 'Waiting',
        GroupStateType.paused => 'Paused',
        GroupStateType.playing => 'Playing',
      };
}

/// One Jellyfin session: a device, and the socket that reaches it.
class SimSession {
  SimSession(this.id, this.userName, this.send);
  final String id;
  final String userName;
  void Function(Map<String, dynamic> frame) send;

  String? nowPlayingItem;
  int nowPlayingTicks = 0;
  bool nowPlayingPaused = false;
}

class _Member {
  _Member(this.session);
  final SimSession session;
  int ping = defaultPing;
  bool isBuffering = false;
  bool ignoreGroupWait = false;
}

class _Place {
  _Place(this.itemId, this.placeId);
  final String itemId;
  final String placeId;
}

abstract class _State {
  GroupStateType get type;
}

class _Idle extends _State {
  @override
  GroupStateType get type => GroupStateType.idle;
}

class _Paused extends _State {
  @override
  GroupStateType get type => GroupStateType.paused;
}

class _Playing extends _State {
  bool ignoreBuffering = false;
  @override
  GroupStateType get type => GroupStateType.playing;
}

class _Waiting extends _State {
  bool resumePlaying = false;
  bool initialStateSet = false;
  GroupStateType initialState = GroupStateType.idle;
  bool positionJumped = false;
  @override
  GroupStateType get type => GroupStateType.waiting;

  void saveInitial(GroupStateType prev) {
    if (!initialStateSet) {
      initialState = prev;
      initialStateSet = true;
    }
  }
}

/// What happened on the server in a run, for the checks afterwards.
class ServerStats {
  int deadlines = 0;
  int refusedReadies = 0;
  int wrongItemReports = 0;
  final List<String> log = [];
}

class SimGroup {
  SimGroup(this.server, this.groupName) : groupId = server.newId();

  final SimServer server;
  final String groupId;
  final String groupName;
  final Map<String, _Member> _participants = {};

  _State _state = _Idle();
  List<_Place> _queue = [];
  int _index = -1;
  DateTime _lastChange = clock.now().toUtc();
  int runTimeTicks = 0;
  int positionTicks = 0;
  DateTime lastActivity = clock.now().toUtc();
  int? _deadline;

  GroupStateType get type => _state.type;
  bool get isEmpty => _participants.isEmpty;
  Iterable<String> get memberIds => _participants.keys;
  String? get playingItemId => _index >= 0 && _index < _queue.length ? _queue[_index].itemId : null;
  String get playingPlaceId => _index >= 0 && _index < _queue.length ? _queue[_index].placeId : zeroGuid;
  int get queueLength => _queue.length;
  String? get nextItemId => _index >= 0 && _index + 1 < _queue.length ? _queue[_index + 1].itemId : null;
  bool get resumePlayingWhileWaiting => _state is _Waiting && (_state as _Waiting).resumePlaying;

  /// Where the group's playhead is now.
  int get currentTicks {
    if (type != GroupStateType.playing) return positionTicks;
    final elapsed = server.now.difference(lastActivity).inMicroseconds * 10;
    return positionTicks + (elapsed > 0 ? elapsed : 0);
  }

  DateTime get _now => server.now;

  int get _nowMs => clock.now().millisecondsSinceEpoch;

  // --- Group.cs: sessions --------------------------------------------------

  Iterable<_Member> _filter(String from, String type) => switch (type) {
        'CurrentSession' => [if (_participants[from] != null) _participants[from]!],
        'AllGroup' => _participants.values.toList(),
        'AllExceptCurrentSession' => _participants.values.where((m) => m.session.id != from).toList(),
        'AllReady' => _participants.values.where((m) => !m.isBuffering).toList(),
        _ => const [],
      };

  void _sendCommand(SimSession from, String filter, Map<String, dynamic> command) {
    final targets = filter == 'CurrentSession' ? [from] : _filter(from.id, filter).map((m) => m.session);
    for (final target in targets) {
      target.send({'MessageType': 'SyncPlayCommand', 'Data': command, 'MessageId': server.newId()});
    }
  }

  void _sendUpdate(SimSession from, String filter, String updateType, Object? data) {
    final frame = {
      'MessageType': 'SyncPlayGroupUpdate',
      'MessageId': server.newId(),
      'Data': {'GroupId': groupId, 'Data': data, 'Type': updateType},
    };
    final targets = filter == 'CurrentSession' ? [from] : _filter(from.id, filter).map((m) => m.session);
    for (final target in targets) {
      target.send(frame);
    }
  }

  Map<String, dynamic> _command(String type, {DateTime? when}) => {
        'GroupId': groupId,
        'PlaylistItemId': playingPlaceId,
        'When': _wire(when ?? lastActivity),
        'PositionTicks': positionTicks,
        'Command': type,
        'EmittedAt': _wire(_now),
      };

  String _wire(DateTime t) => t.toUtc().toIso8601String();

  Map<String, dynamic> _info() => {
        'GroupId': groupId,
        'GroupName': groupName,
        'State': type.wire,
        'Participants': _participants.values.map((m) => m.session.userName).toSet().toList(),
        'LastUpdatedAt': _wire(_now),
      };

  Map<String, dynamic> info() => _info();

  Map<String, dynamic> _queueUpdate(String reason) {
    var start = positionTicks;
    final isPlaying = type == GroupStateType.playing;
    if (isPlaying) {
      final elapsed = _now.difference(lastActivity).inMicroseconds * 10;
      start += elapsed > 0 ? elapsed : 0;
    }
    return {
      'Reason': reason,
      'LastUpdate': _wire(_lastChange),
      'Playlist': [
        for (final p in _queue) {'ItemId': p.itemId, 'PlaylistItemId': p.placeId}
      ],
      'PlayingItemIndex': _index,
      'StartPositionTicks': start,
      'IsPlaying': isPlaying,
      'ShuffleMode': 'Sorted',
      'RepeatMode': 'RepeatNone',
    };
  }

  void _addSession(SimSession session) => _participants.putIfAbsent(session.id, () => _Member(session));

  void _removeSession(SimSession session) {
    _participants.remove(session.id);
    _updateDeadline(false);
  }

  void _setState(_State state) {
    _state = state;
    if (state.type != GroupStateType.waiting) _deadline = null;
  }

  void _setBuffering(SimSession session, bool buffering) {
    _participants[session.id]?.isBuffering = buffering;
    _updateDeadline(false);
  }

  void _setAllBuffering(bool buffering) {
    for (final m in _participants.values) {
      m.isBuffering = buffering;
    }
    _updateDeadline(buffering);
  }

  bool get _anyBuffering => _participants.values.any((m) => m.isBuffering && !m.ignoreGroupWait);

  void _updateDeadline(bool newPeriod) {
    if (type != GroupStateType.waiting || !_anyBuffering) {
      _deadline = null;
      return;
    }
    if (_deadline == null || newPeriod) _deadline = _nowMs + groupWaitTimeoutMs;
  }

  int get _highestPing {
    if (_participants.isEmpty) return defaultPing;
    return _participants.values.map((m) => m.ping).reduce((a, b) => a > b ? a : b);
  }

  int _sanitize(int? ticks) => (ticks ?? 0).clamp(0, runTimeTicks);

  void _restartCurrentItem() {
    positionTicks = 0;
    lastActivity = _now;
  }

  void _setPlaylist(List<String> ids, int index, int startTicks) {
    _queue = [for (final id in ids) _Place(id, server.newId())];
    _index = index;
    _lastChange = _now;
    runTimeTicks = server.runTimeOf(playingItemId!);
    positionTicks = startTicks;
    lastActivity = _now;
  }

  bool _step(int by) {
    final to = _index + by;
    if (to < 0 || to >= _queue.length) return false;
    _index = to;
    _lastChange = _now;
    runTimeTicks = server.runTimeOf(playingItemId!);
    _restartCurrentItem();
    return true;
  }

  void _fallBack(GroupStateType prev) {
    _setState(switch (prev) {
      GroupStateType.playing => _Playing(),
      GroupStateType.paused => _Paused(),
      _ => _Idle(),
    });
  }

  void _stateUpdate(SimSession session, GroupStateType state, String reason) {
    _sendUpdate(session, 'AllGroup', 'StateUpdate', {'State': state.wire, 'Reason': reason});
  }

  // --- Group.cs: lifecycle -------------------------------------------------

  void create(SimSession session) {
    _addSession(session);
    final playing = session.nowPlayingItem;
    _restartCurrentItem();
    if (playing != null) {
      // No client here reports a now-playing queue, so the list stays empty
      // and the item is not found in it, as on the real server.
      _queue = [];
      _index = -1;
      _lastChange = _now;
      runTimeTicks = server.runTimeOf(playing);
      positionTicks = session.nowPlayingTicks;
      _setState(_Waiting()..resumePlaying = !session.nowPlayingPaused);
    }
    _sendUpdate(session, 'CurrentSession', 'GroupJoined', _info());
    _sessionJoined(session, type);
  }

  void join(SimSession session) {
    _addSession(session);
    _sendUpdate(session, 'CurrentSession', 'GroupJoined', _info());
    _sendUpdate(session, 'AllExceptCurrentSession', 'UserJoined', session.userName);
    _sessionJoined(session, type);
  }

  void leave(SimSession session) {
    _sessionLeaving(session);
    _removeSession(session);
    _sendUpdate(session, 'CurrentSession', 'GroupLeft', groupId);
    _sendUpdate(session, 'AllExceptCurrentSession', 'UserLeft', session.userName);
  }

  void _sessionJoined(SimSession session, GroupStateType prev) {
    switch (_state) {
      case _Idle():
        _stop(session, prev);
      case _Paused():
      case _Playing():
        final w = _Waiting();
        final was = type;
        _setState(w);
        _waitingJoined(w, session, was);
      case final _Waiting w:
        _waitingJoined(w, session, prev);
    }
  }

  void _waitingJoined(_Waiting w, SimSession session, GroupStateType prev) {
    w.saveInitial(prev);
    if (prev == GroupStateType.playing) {
      w.resumePlaying = true;
      final elapsed = _now.difference(lastActivity).inMicroseconds * 10;
      lastActivity = _now;
      positionTicks += elapsed > 0 ? elapsed : 0;
    }
    _sendUpdate(session, 'CurrentSession', 'PlayQueue', _queueUpdate('NewPlaylist'));
    _setBuffering(session, true);
    _sendCommand(session, 'AllReady', _command('Pause'));
  }

  void _sessionLeaving(SimSession session) {
    final state = _state;
    if (state is! _Waiting) return;
    state.saveInitial(state.type);
    _setBuffering(session, false);
    if (!_anyBuffering) {
      if (state.resumePlaying) {
        final playing = _Playing();
        _setState(playing);
        _playingUnpause(playing, session, GroupStateType.waiting);
      } else {
        _setState(_Paused());
      }
    }
  }

  void handleDeadline() {
    final deadline = _deadline;
    if (deadline == null || deadline > _nowMs) return;
    _deadline = null;
    final state = _state;
    if (state is! _Waiting) return;
    final blocking = _participants.values.where((m) => m.isBuffering && !m.ignoreGroupWait).toList();
    if (blocking.isEmpty) return;
    server.stats.deadlines++;
    server.stats.log.add('deadline: gave up on ${blocking.map((m) => m.session.id).join(', ')}');
    final session = blocking.first.session;
    if (state.resumePlaying) {
      _waitingUnpause(state, session, GroupStateType.waiting);
      return;
    }
    _setAllBuffering(false);
    _setState(_Paused());
    _sendCommand(session, 'AllGroup', _command('Pause'));
    _stateUpdate(session, GroupStateType.paused, 'Pause');
  }

  // --- requests ------------------------------------------------------------

  void play(SimSession s, List<String> ids, int index, int start) {
    switch (_state) {
      case _Paused():
      case _Playing():
      case _Idle():
        final was = type;
        final w = _Waiting();
        _setState(w);
        _waitingPlay(w, s, was, ids, index, start);
      case final _Waiting w:
        _waitingPlay(w, s, GroupStateType.waiting, ids, index, start);
    }
  }

  void _waitingPlay(_Waiting w, SimSession s, GroupStateType prev, List<String> ids, int index, int start) {
    w.saveInitial(prev);
    w.resumePlaying = true;
    final ok = ids.isNotEmpty && index >= 0 && index < ids.length;
    w.positionJumped = ok;
    if (!ok) {
      _fallBack(prev);
      return;
    }
    _setPlaylist(ids, index, start);
    _sendUpdate(s, 'AllGroup', 'PlayQueue', _queueUpdate('NewPlaylist'));
    _setAllBuffering(true);
  }

  void unpause(SimSession s) {
    switch (_state) {
      case _Idle():
        final w = _Waiting();
        _setState(w);
        _waitingUnpause(w, s, GroupStateType.idle);
      case _Paused():
        final playing = _Playing();
        _setState(playing);
        _playingUnpause(playing, s, GroupStateType.paused);
      case final _Playing playing:
        _playingUnpause(playing, s, GroupStateType.playing);
      case final _Waiting w:
        _waitingUnpause(w, s, GroupStateType.waiting);
    }
  }

  void _waitingUnpause(_Waiting w, SimSession s, GroupStateType prev) {
    w.saveInitial(prev);
    if (prev == GroupStateType.idle) {
      w.resumePlaying = true;
      _restartCurrentItem();
      w.positionJumped = true;
      _sendUpdate(s, 'AllGroup', 'PlayQueue', _queueUpdate('NewPlaylist'));
      _setAllBuffering(true);
    } else if (w.resumePlaying) {
      _setAllBuffering(false);
      final playing = _Playing()..ignoreBuffering = true;
      _setState(playing);
      _playingUnpause(playing, s, GroupStateType.waiting);
    } else {
      w.resumePlaying = true;
      _stateUpdate(s, GroupStateType.waiting, 'Unpause');
    }
  }

  void _playingUnpause(_Playing playing, SimSession s, GroupStateType prev) {
    if (prev != GroupStateType.playing) {
      final highest = _highestPing * 2;
      final delay = highest > defaultPing ? highest : defaultPing;
      lastActivity = _now.add(Duration(milliseconds: delay));
      _sendCommand(s, 'AllGroup', _command('Unpause'));
      _stateUpdate(s, GroupStateType.playing, 'Unpause');
    } else {
      _sendCommand(s, 'CurrentSession', _command('Unpause'));
    }
  }

  void pause(SimSession s) {
    switch (_state) {
      case _Idle():
        _stop(s, GroupStateType.idle);
      case _Playing():
        _setState(_Paused());
        _pausedPause(s, GroupStateType.playing);
      case _Paused():
        _pausedPause(s, GroupStateType.paused);
      case final _Waiting w:
        w.saveInitial(GroupStateType.waiting);
        w.resumePlaying = false;
        _stateUpdate(s, GroupStateType.waiting, 'Pause');
    }
  }

  void _pausedPause(SimSession s, GroupStateType prev) {
    if (prev != GroupStateType.paused) {
      final elapsed = _now.difference(lastActivity).inMicroseconds * 10;
      lastActivity = _now;
      positionTicks += elapsed > 0 ? elapsed : 0;
      _sendCommand(s, 'AllGroup', _command('Pause'));
      _stateUpdate(s, GroupStateType.paused, 'Pause');
    } else {
      _sendCommand(s, 'CurrentSession', _command('Pause'));
    }
  }

  void stop(SimSession s) {
    final prev = type;
    _setState(_Idle());
    _stop(s, prev);
  }

  void _stop(SimSession s, GroupStateType prev) {
    final command = _command('Stop');
    _sendCommand(s, prev != GroupStateType.idle ? 'AllGroup' : 'CurrentSession', command);
  }

  void seek(SimSession s, int ticks) {
    switch (_state) {
      case _Idle():
        _stop(s, GroupStateType.idle);
      case _Paused():
      case _Playing():
        final was = type;
        final w = _Waiting();
        _setState(w);
        _waitingSeek(w, s, was, ticks);
      case final _Waiting w:
        _waitingSeek(w, s, GroupStateType.waiting, ticks);
    }
  }

  void _waitingSeek(_Waiting w, SimSession s, GroupStateType prev, int ticks) {
    w.saveInitial(prev);
    if (prev == GroupStateType.playing) {
      w.resumePlaying = true;
    } else if (prev == GroupStateType.paused) {
      w.resumePlaying = false;
    }
    positionTicks = _sanitize(ticks);
    lastActivity = _now;
    w.positionJumped = true;
    _sendCommand(s, 'AllGroup', _command('Seek'));
    _setAllBuffering(true);
    _stateUpdate(s, GroupStateType.waiting, 'Seek');
  }

  void buffering(SimSession s, Map<String, dynamic> body) {
    switch (_state) {
      case _Idle():
        _stop(s, GroupStateType.idle);
      case final _Playing playing:
        if (playing.ignoreBuffering) return;
        final w = _Waiting();
        _setState(w);
        _waitingBuffer(w, s, GroupStateType.playing, body);
      case _Paused():
        final w = _Waiting();
        _setState(w);
        _waitingBuffer(w, s, GroupStateType.paused, body);
      case final _Waiting w:
        _waitingBuffer(w, s, GroupStateType.waiting, body);
    }
  }

  void _waitingBuffer(_Waiting w, SimSession s, GroupStateType prev, Map<String, dynamic> body) {
    w.saveInitial(prev);
    if ((body['PlaylistItemId'] as String? ?? zeroGuid) != playingPlaceId) {
      server.stats.wrongItemReports++;
      _sendUpdate(s, 'CurrentSession', 'PlayQueue', _queueUpdate('SetCurrentItem'));
      _setBuffering(s, true);
      return;
    }
    if (prev == GroupStateType.playing) {
      w.resumePlaying = true;
      _setBuffering(s, true);
      final elapsed = _now.difference(lastActivity).inMicroseconds * 10;
      lastActivity = _now;
      positionTicks += elapsed > 0 ? elapsed : 0;
      _sendCommand(s, 'AllReady', _command('Pause'));
    } else if (prev == GroupStateType.paused) {
      w.resumePlaying = false;
      _setBuffering(s, true);
      _sendCommand(s, 'CurrentSession', _command('Pause'));
    } else {
      _setBuffering(s, true);
      if (!w.resumePlaying) _sendCommand(s, 'CurrentSession', _command('Pause'));
    }
    _stateUpdate(s, GroupStateType.waiting, 'Buffer');
  }

  void ready(SimSession s, Map<String, dynamic> body) {
    switch (_state) {
      case _Idle():
        _stop(s, GroupStateType.idle);
      case final _Playing playing:
        _playingReady(playing, s, GroupStateType.playing);
      case _Paused():
        _pausedReady(s, GroupStateType.paused);
      case final _Waiting w:
        _waitingReady(w, s, GroupStateType.waiting, body);
    }
  }

  void _playingReady(_Playing playing, SimSession s, GroupStateType prev) {
    if (prev == GroupStateType.playing) {
      _sendCommand(s, 'CurrentSession', _command('Unpause'));
    } else if (prev == GroupStateType.waiting) {
      _stateUpdate(s, GroupStateType.playing, 'Ready');
    }
  }

  void _pausedReady(SimSession s, GroupStateType prev) {
    if (prev == GroupStateType.paused) {
      _sendCommand(s, 'CurrentSession', _command('Pause'));
    } else if (prev == GroupStateType.waiting) {
      _sendCommand(s, 'AllGroup', _command('Pause'));
      _stateUpdate(s, GroupStateType.paused, 'Ready');
    }
  }

  void _waitingReady(_Waiting w, SimSession s, GroupStateType prev, Map<String, dynamic> body) {
    w.saveInitial(prev);
    if ((body['PlaylistItemId'] as String? ?? zeroGuid) != playingPlaceId) {
      server.stats.wrongItemReports++;
      _sendUpdate(s, 'CurrentSession', 'PlayQueue', _queueUpdate('SetCurrentItem'));
      _setBuffering(s, true);
      return;
    }
    final isPlaying = body['IsPlaying'] as bool? ?? false;
    final when = body['When'] == null ? null : DateTime.parse(body['When'] as String).toUtc();
    final currentTime = _now;
    var elapsedTicks = when == null ? 0 : currentTime.difference(when).inMicroseconds * 10;
    if (elapsedTicks.abs() > timeSyncOffsetMs * ticksPerMs) elapsedTicks = 0;
    if (!isPlaying) elapsedTicks = 0;
    final requestTicks = _sanitize(body['PositionTicks'] as int?);
    final clientPosition = requestTicks + elapsedTicks;
    var delayTicks = positionTicks - clientPosition;
    const maxOffset = maxPlaybackOffsetMs * ticksPerMs;

    if (w.resumePlaying) {
      final allowed = isPlaying && !w.positionJumped ? maxCatchUpOffsetMs * ticksPerMs : maxOffset;
      if (delayTicks.abs() > allowed) {
        server.stats.refusedReadies++;
        server.stats.log.add('refused Ready from ${s.id}: ${delayTicks / ticksPerMs} ms off');
        _setBuffering(s, true);
        _sendCommand(s, 'CurrentSession', _command('Seek'));
        _stateUpdate(s, GroupStateType.waiting, 'Ready');
        return;
      }
      _setBuffering(s, false);
      if (_anyBuffering) {
        _sendCommand(s, 'CurrentSession', _command('Pause', when: currentTime.add(Duration(microseconds: delayTicks ~/ 10))));
      } else {
        if (delayTicks > _highestPing * 2 * ticksPerMs) {
          lastActivity = currentTime.add(Duration(microseconds: delayTicks ~/ 10));
          _sendCommand(s, isPlaying ? 'AllExceptCurrentSession' : 'AllGroup', _command('Unpause'));
        } else {
          delayTicks = _highestPing * 2 * ticksPerMs;
          if (delayTicks < defaultPing * ticksPerMs) delayTicks = defaultPing * ticksPerMs;
          lastActivity = currentTime.add(Duration(microseconds: delayTicks ~/ 10));
          _sendCommand(s, 'AllGroup', _command('Unpause'));
        }
        final playing = _Playing();
        _setState(playing);
        _playingReady(playing, s, GroupStateType.waiting);
      }
    } else {
      if ((positionTicks - requestTicks).abs() > maxOffset) {
        server.stats.refusedReadies++;
        server.stats.log.add('refused Ready from ${s.id}: wrong position, paused');
        _setBuffering(s, true);
        _sendCommand(s, 'CurrentSession', _command('Seek'));
        _stateUpdate(s, GroupStateType.waiting, 'Ready');
        return;
      }
      _setBuffering(s, false);
      if (!_anyBuffering) {
        _setState(_Paused());
        if (w.initialState == GroupStateType.playing) {
          _pausedPause(s, GroupStateType.waiting);
        } else if (w.initialState == GroupStateType.paused) {
          _pausedReady(s, GroupStateType.waiting);
        }
      }
    }
  }

  void stepItem(SimSession s, int by, String? fromPlace, String reason) {
    switch (_state) {
      case _Idle():
      case _Paused():
      case _Playing():
        final was = type;
        final w = _Waiting();
        _setState(w);
        _waitingStep(w, s, was, by, fromPlace, reason);
      case final _Waiting w:
        _waitingStep(w, s, GroupStateType.waiting, by, fromPlace, reason);
    }
  }

  void _waitingStep(_Waiting w, SimSession s, GroupStateType prev, int by, String? from, String reason) {
    w.saveInitial(prev);
    w.resumePlaying = true;
    if ((from ?? zeroGuid) != playingPlaceId) return;
    final moved = _step(by);
    w.positionJumped = moved;
    if (moved) {
      _sendUpdate(s, 'AllGroup', 'PlayQueue', _queueUpdate(reason));
      _setAllBuffering(true);
    } else {
      _fallBack(prev);
    }
  }

  void queueItems(SimSession s, List<String> ids) {
    if (ids.isEmpty) return;
    _queue.addAll(ids.map((id) => _Place(id, server.newId())));
    _lastChange = _now;
    _sendUpdate(s, 'AllGroup', 'PlayQueue', _queueUpdate('Queue'));
  }

  void updatePing(SimSession s, int ping) => _participants[s.id]?.ping = ping.clamp(0, maxPing);
}

class SimServer {
  SimServer({this.clockSkew = Duration.zero, required this.runTimeOf}) {
    _sweep = Timer.periodic(const Duration(seconds: 1), (_) {
      for (final group in groups.values.toList()) {
        group.handleDeadline();
      }
    });
  }

  /// How far the server's clock is from the clients'.
  final Duration clockSkew;
  final int Function(String itemId) runTimeOf;
  final stats = ServerStats();
  final Map<String, SimGroup> groups = {};
  final Map<String, SimSession> sessions = {};
  final Map<String, SimGroup> _sessionToGroup = {};
  late final Timer _sweep;
  int _ids = 0;

  DateTime get now => clock.now().toUtc().add(clockSkew);

  String newId() => (++_ids).toRadixString(16).padLeft(32, 'a');

  SimGroup? groupOf(SimSession s) => _sessionToGroup[s.id];

  void _notInGroup(SimSession s) => s.send({
        'MessageType': 'SyncPlayGroupUpdate',
        'MessageId': newId(),
        'Data': {'GroupId': zeroGuid, 'Data': '', 'Type': 'NotInGroup'},
      });

  Map<String, dynamic> newGroup(SimSession s, String name) {
    leaveIfIn(s);
    final group = SimGroup(this, name);
    groups[group.groupId] = group;
    _sessionToGroup[s.id] = group;
    group.create(s);
    return group.info();
  }

  void join(SimSession s, String groupId) {
    final group = groups[groupId];
    if (group == null) {
      s.send({
        'MessageType': 'SyncPlayGroupUpdate',
        'MessageId': newId(),
        'Data': {'GroupId': zeroGuid, 'Data': '', 'Type': 'GroupDoesNotExist'},
      });
      return;
    }
    final existing = _sessionToGroup[s.id];
    if (existing != null) {
      if (existing.groupId == groupId) {
        group.join(s);
        return;
      }
      leaveIfIn(s);
    }
    _sessionToGroup[s.id] = group;
    group.join(s);
  }

  /// A Leave asked for: out of nothing, the server says so.
  void leave(SimSession s) {
    if (_sessionToGroup[s.id] == null) {
      _notInGroup(s);
      return;
    }
    leaveIfIn(s);
  }

  void leaveIfIn(SimSession s) {
    final group = _sessionToGroup.remove(s.id);
    if (group == null) return;
    group.leave(s);
    if (group.isEmpty) groups.remove(group.groupId);
  }

  /// A request that needs a group.
  void inGroup(SimSession s, void Function(SimGroup group) action) {
    final group = _sessionToGroup[s.id];
    if (group == null) {
      _notInGroup(s);
      return;
    }
    if (group.isEmpty) return;
    action(group);
  }

  void close() => _sweep.cancel();
}

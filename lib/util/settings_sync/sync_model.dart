import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:chudder/util/settings_transfer.dart';

/// Settings sync, the shape of it.
///
/// An account keeps one record of profiles: named sets of settings ("TV",
/// "Phone"), each section with when it was last changed and on which device.
/// A device follows one profile, section by section or keeping some of its
/// own, and pushes its changes to it. What the app remembers rather than what
/// someone set - languages remembered per show, collection queues, the
/// languages watched in - belongs to the person, not a profile, and is merged
/// across every device rather than replaced.

/// The kind of device a profile was made on, to suggest it to its own kind.
enum DeviceKind {
  phone,
  tablet,
  desktop,
  tv,
  web;

  static DeviceKind fromName(String? name) =>
      DeviceKind.values.firstWhereOrNull((kind) => kind.name == name) ?? desktop;
}

/// The sections that are settings, newest wins. The languages section is
/// one, for its rules - what it remembers per show travels as a memory.
const syncedSettingSections = [
  SettingsSection.app,
  SettingsSection.home,
  SettingsSection.player,
  SettingsSection.subtitles,
  SettingsSection.languages,
  SettingsSection.syncPlay,
  SettingsSection.books,
  SettingsSection.photos,
];

/// One section in a profile: its stored value (decoded JSON, device-only
/// fields left out), when it was changed and where.
class SyncedSection {
  const SyncedSection({required this.value, required this.at, required this.by});

  final Object? value;
  final DateTime at;

  /// The device that changed it, by name.
  final String by;

  Map<String, Object?> toJson() => {'v': value, 'at': at.toUtc().toIso8601String(), 'by': by};

  static SyncedSection? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return SyncedSection(value: json['v'], at: at, by: '${json['by'] ?? ''}');
  }
}

/// A named set of settings on the account.
class SyncProfile {
  const SyncProfile({
    required this.id,
    required this.name,
    required this.kind,
    this.sections = const {},
    required this.updatedAt,
    this.updatedBy = '',
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final Map<SettingsSection, SyncedSection> sections;
  final DateTime updatedAt;
  final String updatedBy;

  SyncProfile copyWith({
    String? name,
    DeviceKind? kind,
    Map<SettingsSection, SyncedSection>? sections,
    DateTime? updatedAt,
    String? updatedBy,
  }) =>
      SyncProfile(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        sections: sections ?? this.sections,
        updatedAt: updatedAt ?? this.updatedAt,
        updatedBy: updatedBy ?? this.updatedBy,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'updatedBy': updatedBy,
        'sections': {for (final entry in sections.entries) entry.key.name: entry.value.toJson()},
      };

  static SyncProfile? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final sections = <SettingsSection, SyncedSection>{};
    final raw = json['sections'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final section = SettingsSection.values.firstWhereOrNull((s) => s.name == entry.key);
        final value = SyncedSection.fromJson(entry.value);
        if (section != null && value != null) sections[section] = value;
      }
    }
    return SyncProfile(
      id: json['id'] as String,
      name: '${json['name'] ?? ''}',
      kind: DeviceKind.fromName('${json['kind']}'),
      sections: sections,
      updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedBy: '${json['updatedBy'] ?? ''}',
    );
  }
}

/// A profile as it was before a change, to go back to.
class ProfileVersion {
  const ProfileVersion({required this.profile, required this.replacedAt, required this.replacedBy});

  final SyncProfile profile;
  final DateTime replacedAt;
  final String replacedBy;

  Map<String, Object?> toJson() => {
        'profile': profile.toJson(),
        'replacedAt': replacedAt.toUtc().toIso8601String(),
        'replacedBy': replacedBy,
      };

  static ProfileVersion? fromJson(Object? json) {
    if (json is! Map) return null;
    final profile = SyncProfile.fromJson(json['profile']);
    final at = DateTime.tryParse('${json['replacedAt']}');
    if (profile == null || at == null) return null;
    return ProfileVersion(profile: profile, replacedAt: at, replacedBy: '${json['replacedBy'] ?? ''}');
  }
}

/// What the app remembers for the person, merged across devices.
class SyncMemories {
  const SyncMemories({this.remembered = const {}, this.queues = const [], this.watched = const {}, this.updatedAt});

  /// Language choices per show, collection or playlist, by their key, as the
  /// language preferences store them (each with its `savedAt`).
  final Map<String, Map<String, Object?>> remembered;

  /// Collection queues as stored (each with its scope id and `savedAt`).
  final List<Map<String, Object?>> queues;

  /// Languages watched in: code to [score, day].
  final Map<String, List<num>> watched;
  final DateTime? updatedAt;

  bool get isEmpty => remembered.isEmpty && queues.isEmpty && watched.isEmpty;

  Map<String, Object?> toJson() => {
        'remembered': remembered,
        'queues': queues,
        'watched': watched,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static SyncMemories fromJson(Object? json) {
    if (json is! Map) return const SyncMemories();
    final remembered = <String, Map<String, Object?>>{};
    final rawRemembered = json['remembered'];
    if (rawRemembered is Map) {
      for (final entry in rawRemembered.entries) {
        if (entry.value is Map) remembered['${entry.key}'] = Map<String, Object?>.from(entry.value as Map);
      }
    }
    final queues = <Map<String, Object?>>[
      for (final queue in (json['queues'] is List ? json['queues'] as List : const []))
        if (queue is Map) Map<String, Object?>.from(queue),
    ];
    final watched = <String, List<num>>{};
    final rawWatched = json['watched'];
    if (rawWatched is Map) {
      for (final entry in rawWatched.entries) {
        final value = entry.value;
        if (value is List && value.length == 2 && value.every((n) => n is num)) {
          watched['${entry.key}'] = [value[0] as num, value[1] as num];
        }
      }
    }
    return SyncMemories(
      remembered: remembered,
      queues: queues,
      watched: watched,
      updatedAt: DateTime.tryParse('${json['updatedAt']}'),
    );
  }

  static DateTime _savedAt(Map<String, Object?> entry) =>
      DateTime.tryParse('${entry['savedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Both sides together: each remembered choice and each collection queue
  /// as most recently saved anywhere; each watched language counted as much
  /// as the side that counted it most (adding them up would count a play
  /// again every time two devices met).
  static SyncMemories merge(SyncMemories a, SyncMemories b) {
    final remembered = <String, Map<String, Object?>>{...a.remembered};
    b.remembered.forEach((key, entry) {
      final mine = remembered[key];
      if (mine == null || _savedAt(entry).isAfter(_savedAt(mine))) remembered[key] = entry;
    });

    String queueKey(Map<String, Object?> queue) => '${queue['userId']}:${queue['id']}';
    final queues = <String, Map<String, Object?>>{for (final queue in a.queues) queueKey(queue): queue};
    for (final queue in b.queues) {
      final mine = queues[queueKey(queue)];
      if (mine == null || _savedAt(queue).isAfter(_savedAt(mine))) queues[queueKey(queue)] = queue;
    }
    // At most as many as one device keeps, the latest.
    final sortedQueues = queues.values.sorted((x, y) => _savedAt(x).compareTo(_savedAt(y)));
    final keptQueues = sortedQueues.length > 20 ? sortedQueues.sublist(sortedQueues.length - 20) : sortedQueues;

    final today = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    double now(List<num> entry) => entry[0] * math.pow(0.5, (today - entry[1]) / 60).toDouble();
    final watched = <String, List<num>>{...a.watched};
    b.watched.forEach((code, entry) {
      final mine = watched[code];
      if (mine == null || now(entry) > now(mine)) watched[code] = entry;
    });

    final latest = [a.updatedAt, b.updatedAt].nonNulls.maxOrNull;
    return SyncMemories(remembered: remembered, queues: keptQueues, watched: watched, updatedAt: latest);
  }

  /// The same memories, whatever order they were put together in.
  bool sameAs(SyncMemories other) => _canonical(toJson()) == _canonical(other.toJson());

  static String _canonical(Map<String, Object?> json) {
    final copy = Map.of(json)..remove('updatedAt');
    final queues = (copy['queues'] as List).cast<Map<String, Object?>>().map(canonicalJson).toList()..sort();
    copy['queues'] = queues;
    return canonicalJson(copy);
  }
}

/// JSON with its maps' keys in order, to compare two values by content.
String canonicalJson(Object? value) {
  Object? sort(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final key in keys) key: sort(v[key])};
    }
    if (v is List) return v.map(sort).toList();
    return v;
  }

  return jsonEncode(sort(value));
}

/// Everything the account keeps for sync: its profiles, each one's earlier
/// versions, and the memories.
/// A device that syncs, as the account lists it: so a profile can say which
/// devices are on it, and an old one can be taken off the list.
class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.profileId,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final DeviceKind kind;
  final String? profileId;
  final DateTime lastSeen;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'profileId': profileId,
        'lastSeen': lastSeen.toUtc().toIso8601String(),
      };

  static SyncDevice? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return SyncDevice(
      id: json['id'] as String,
      name: '${json['name'] ?? ''}',
      kind: DeviceKind.fromName('${json['kind']}'),
      profileId: json['profileId'] as String?,
      lastSeen: DateTime.tryParse('${json['lastSeen']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// One change to a profile, as the recent changes list it: the parts one
/// device changed in one sitting, with what they were before - to undo.
class ProfileChange {
  const ProfileChange({required this.at, required this.by, required this.before});

  final DateTime at;
  final String by;

  /// The parts changed, each with its value before the change (null: the
  /// part did not exist yet).
  final Map<SettingsSection, Object?> before;
}

/// Everything the account keeps for sync: its profiles, each one's earlier
/// versions, the devices, and the memories.
class SyncRecord {
  const SyncRecord({
    this.profiles = const [],
    this.history = const {},
    this.memories = const SyncMemories(),
    this.devices = const {},
  });

  final List<SyncProfile> profiles;
  final Map<String, List<ProfileVersion>> history;
  final SyncMemories memories;
  final Map<String, SyncDevice> devices;

  /// Versions kept per profile.
  static const maxHistory = 20;

  static const format = 'chudder-sync';
  static const version = 1;

  SyncProfile? profile(String? id) => profiles.firstWhereOrNull((profile) => profile.id == id);

  SyncRecord copyWith({
    List<SyncProfile>? profiles,
    Map<String, List<ProfileVersion>>? history,
    SyncMemories? memories,
    Map<String, SyncDevice>? devices,
  }) =>
      SyncRecord(
        profiles: profiles ?? this.profiles,
        history: history ?? this.history,
        memories: memories ?? this.memories,
        devices: devices ?? this.devices,
      );

  /// [profile] in place of the one with its id (or added), the one it
  /// replaces kept as a version to go back to - unless it was changed by the
  /// same device within [coalesce], which would only fill the history with
  /// every step of one sitting.
  SyncRecord withProfile(
    SyncProfile profile, {
    required DateTime now,
    required String device,
    Duration coalesce = const Duration(minutes: 10),
  }) {
    final before = this.profile(profile.id);
    final versions = [...?history[profile.id]];
    if (before != null) {
      final last = versions.lastOrNull;
      final sameSitting = last != null && last.replacedBy == device && now.difference(last.replacedAt) < coalesce;
      if (!sameSitting && canonicalJson(before.toJson()['sections']) != canonicalJson(profile.toJson()['sections'])) {
        versions.add(ProfileVersion(profile: before, replacedAt: now, replacedBy: device));
      }
    }
    return copyWith(
      profiles: [
        for (final existing in profiles) existing.id == profile.id ? profile : existing,
        if (before == null) profile,
      ],
      history: {
        ...history,
        profile.id: versions.length > maxHistory ? versions.sublist(versions.length - maxHistory) : versions,
      },
    );
  }

  SyncRecord withoutProfile(String id) => copyWith(
        profiles: profiles.where((profile) => profile.id != id).toList(),
        history: Map.of(history)..remove(id),
      );

  SyncRecord withMemories(SyncMemories memories) => copyWith(memories: memories);

  SyncRecord withDevice(SyncDevice device) => copyWith(devices: {...devices, device.id: device});

  SyncRecord withoutDevice(String id) => copyWith(devices: Map.of(devices)..remove(id));

  /// The devices on [profileId], the latest seen first.
  List<SyncDevice> devicesOn(String profileId) => devices.values
      .where((device) => device.profileId == profileId)
      .sorted((a, b) => b.lastSeen.compareTo(a.lastSeen));

  /// [profileId]'s changes, the latest first: each kept version against the
  /// one after it (or the profile as it is now).
  List<ProfileChange> changesOf(String profileId) {
    final current = profile(profileId);
    final versions = history[profileId] ?? const <ProfileVersion>[];
    final changes = <ProfileChange>[];
    for (var i = 0; i < versions.length; i++) {
      final before = versions[i].profile;
      final after = i + 1 < versions.length ? versions[i + 1].profile : current;
      if (after == null) continue;
      final changed = <SettingsSection, Object?>{
        for (final section in {...before.sections.keys, ...after.sections.keys})
          if (canonicalJson(before.sections[section]?.value) != canonicalJson(after.sections[section]?.value))
            section: before.sections[section]?.value,
      };
      if (changed.isEmpty) continue;
      changes.add(ProfileChange(at: versions[i].replacedAt, by: versions[i].replacedBy, before: changed));
    }
    return changes.reversed.toList();
  }

  /// The record as the display preferences hold it: a few keys of text.
  Map<String, String> toPrefs() => {
        'format': format,
        'version': '$version',
        'profiles': jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
        'history': jsonEncode(history.map((id, versions) => MapEntry(id, versions.map((v) => v.toJson()).toList()))),
        'memories': jsonEncode(memories.toJson()),
        'devices': jsonEncode(devices.values.map((device) => device.toJson()).toList()),
      };

  static SyncRecord fromPrefs(Map<String, Object?>? prefs) {
    if (prefs == null || prefs['format'] != format) return const SyncRecord();
    Object? decode(String key) {
      final raw = prefs[key];
      if (raw is! String || raw.isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }

    final profiles = decode('profiles');
    final history = decode('history');
    final devices = decode('devices');
    return SyncRecord(
      profiles: (profiles is List ? profiles : const []).map(SyncProfile.fromJson).nonNulls.toList(),
      history: {
        if (history is Map)
          for (final entry in history.entries)
            '${entry.key}':
                (entry.value is List ? entry.value as List : const []).map(ProfileVersion.fromJson).nonNulls.toList(),
      },
      memories: SyncMemories.fromJson(decode('memories')),
      devices: {
        for (final device in (devices is List ? devices : const []).map(SyncDevice.fromJson).nonNulls)
          device.id: device,
      },
    );
  }
}

/// What a device knows of a section it follows: what it last held, when that
/// changed here, and which profile version it last matched.
class LocalSection {
  const LocalSection({required this.hash, required this.changedAt, this.syncedAt});

  /// [canonicalJson] of the value held here.
  final String hash;

  /// When this device last saw the value change here.
  final DateTime changedAt;

  /// The profile's time for this section when this device last matched it -
  /// pushed or pulled. Null: never.
  final DateTime? syncedAt;

  bool get changedSinceSync => syncedAt == null || changedAt.isAfter(syncedAt!);

  LocalSection copyWith({String? hash, DateTime? changedAt, DateTime? syncedAt}) => LocalSection(
        hash: hash ?? this.hash,
        changedAt: changedAt ?? this.changedAt,
        syncedAt: syncedAt ?? this.syncedAt,
      );

  Map<String, Object?> toJson() => {
        'hash': hash,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'syncedAt': syncedAt?.toUtc().toIso8601String(),
      };

  static LocalSection? fromJson(Object? json) {
    if (json is! Map) return null;
    final changedAt = DateTime.tryParse('${json['changedAt']}');
    if (changedAt == null) return null;
    return LocalSection(
      hash: '${json['hash'] ?? ''}',
      changedAt: changedAt,
      syncedAt: DateTime.tryParse('${json['syncedAt']}'),
    );
  }
}

/// What to do with one section when this device and its profile meet.
enum SectionAction { none, pull, push }

/// The rule for one section: whichever side changed since the two last
/// matched goes to the other; when both did, the later change wins.
SectionAction decideSection({required LocalSection? local, required SyncedSection? remote, required String localHash}) {
  if (remote == null) return SectionAction.push;
  final remoteHash = canonicalJson(remote.value);
  if (remoteHash == localHash) return SectionAction.none;
  if (local == null) {
    // Never synced here: the profile is what this device signed up to follow.
    return SectionAction.pull;
  }
  final remoteChanged = local.syncedAt == null || remote.at.isAfter(local.syncedAt!);
  final localChanged = local.changedSinceSync;
  if (remoteChanged && localChanged) {
    return remote.at.isAfter(local.changedAt) ? SectionAction.pull : SectionAction.push;
  }
  if (remoteChanged) return SectionAction.pull;
  if (localChanged) return SectionAction.push;
  // Neither changed, yet they differ: the profile's is the one followed.
  return SectionAction.pull;
}

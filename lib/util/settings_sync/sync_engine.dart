import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';

import 'package:chudder/util/settings_sync/sync_model.dart';
import 'package:chudder/util/settings_transfer.dart';

/// Where a device keeps its settings: the app's preferences, or a map in a
/// test standing in for a second device.
abstract class SyncLocalStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
}

/// Where the account keeps the sync record.
abstract class SyncRemote {
  /// Null when it cannot be reached.
  Future<SyncRecord?> read();
  Future<bool> write(SyncRecord record);
}

/// How one device syncs, as it keeps it (never synced itself, never part of
/// an export: it says what this device does).
class SyncSetup {
  const SyncSetup({
    this.enabled = false,
    this.profileId,
    this.keepOwn = const {},
    this.shareMemories = true,
    this.deviceName = '',
    this.deviceId = '',
    this.sections = const {},
    this.lastSync,
    this.answeredSetup = false,
  });

  /// This device on the account's list of devices; made up the first time.
  final String deviceId;

  final bool enabled;
  final String? profileId;

  /// Sections this device keeps as its own, whatever the profile says.
  final Set<SettingsSection> keepOwn;

  /// Whether remembered languages, collection queues and watched languages
  /// are merged with the account's.
  final bool shareMemories;

  /// What this device is called in the profiles' history: "Living room TV".
  final String deviceName;

  final Map<SettingsSection, LocalSection> sections;
  final DateTime? lastSync;

  /// Whether the offer to set this device up from a profile was answered,
  /// either way. Asked once.
  final bool answeredSetup;

  bool follows(SettingsSection section) => enabled && !keepOwn.contains(section);

  SyncSetup copyWith({
    bool? enabled,
    String? Function()? profileId,
    Set<SettingsSection>? keepOwn,
    bool? shareMemories,
    String? deviceName,
    String? deviceId,
    Map<SettingsSection, LocalSection>? sections,
    DateTime? lastSync,
    bool? answeredSetup,
  }) =>
      SyncSetup(
        enabled: enabled ?? this.enabled,
        profileId: profileId != null ? profileId() : this.profileId,
        keepOwn: keepOwn ?? this.keepOwn,
        shareMemories: shareMemories ?? this.shareMemories,
        deviceName: deviceName ?? this.deviceName,
        deviceId: deviceId ?? this.deviceId,
        sections: sections ?? this.sections,
        lastSync: lastSync ?? this.lastSync,
        answeredSetup: answeredSetup ?? this.answeredSetup,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'profileId': profileId,
        'keepOwn': keepOwn.map((section) => section.name).toList(),
        'shareMemories': shareMemories,
        'deviceName': deviceName,
        'deviceId': deviceId,
        'sections': {for (final entry in sections.entries) entry.key.name: entry.value.toJson()},
        'lastSync': lastSync?.toUtc().toIso8601String(),
        'answeredSetup': answeredSetup,
      };

  static SyncSetup fromJson(String? source) {
    if (source == null || source.isEmpty) return const SyncSetup();
    try {
      final map = jsonDecode(source) as Map;
      SettingsSection? section(Object? name) => SettingsSection.values.firstWhereOrNull((s) => s.name == name);
      final sections = <SettingsSection, LocalSection>{};
      final raw = map['sections'];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final key = section(entry.key);
          final value = LocalSection.fromJson(entry.value);
          if (key != null && value != null) sections[key] = value;
        }
      }
      return SyncSetup(
        enabled: map['enabled'] == true,
        profileId: map['profileId'] as String?,
        keepOwn: (map['keepOwn'] as List? ?? const []).map(section).nonNulls.toSet(),
        shareMemories: map['shareMemories'] != false,
        deviceName: '${map['deviceName'] ?? ''}',
        deviceId: '${map['deviceId'] ?? ''}',
        sections: sections,
        lastSync: DateTime.tryParse('${map['lastSync']}'),
        answeredSetup: map['answeredSetup'] == true,
      );
    } catch (_) {
      return const SyncSetup();
    }
  }
}

/// What one sync did.
class SyncOutcome {
  const SyncOutcome({
    required this.setup,
    this.record,
    this.pulled = const {},
    this.pushed = const {},
    this.memoriesChanged = false,
    this.error,
  });

  final SyncSetup setup;

  /// The record as it now stands on the account; null when it was not read.
  final SyncRecord? record;

  /// Sections taken from the profile: their settings must be read again.
  final Set<SettingsSection> pulled;
  final Set<SettingsSection> pushed;

  /// Whether the memories here changed and must be read again.
  final bool memoriesChanged;

  final SyncError? error;
}

enum SyncError { unreachable, profileGone, writeFailed }

/// Syncs one device with its account. No state of its own: everything it
/// knows comes in as a [SyncSetup] and goes out as a new one.
class SyncEngine {
  SyncEngine({required this.local, required this.remote, DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  final SyncLocalStore local;
  final SyncRemote remote;
  final DateTime Function() clock;

  static const _rememberedField = 'remembered';

  // ---- Reading and writing this device's sections ----

  Object? _decoded(SettingsSection section) {
    final stored = local.getString(section.key);
    if (stored == null || stored.isEmpty) return null;
    try {
      return jsonDecode(stored);
    } catch (_) {
      return stored;
    }
  }

  /// [section] as it travels: without what describes this device only, and
  /// for the languages without what they remember (a memory, not a setting).
  Object? localValue(SettingsSection section) {
    final value = _decoded(section);
    if (value is! Map) return value;
    final copy = Map<String, Object?>.from(value);
    copy.removeWhere((key, _) => section.deviceOnly.contains(key));
    if (section == SettingsSection.languages) copy.remove(_rememberedField);
    return copy;
  }

  Future<void> _writeSection(SettingsSection section, Object? value) async {
    if (value == null) return;
    final current = _decoded(section);
    Object? merged = value;
    if (value is Map) {
      merged = {
        ...Map<String, Object?>.from(value),
        if (current is Map)
          for (final key in section.deviceOnly)
            if (current.containsKey(key)) key: current[key],
        if (section == SettingsSection.languages && current is Map && current.containsKey(_rememberedField))
          _rememberedField: current[_rememberedField],
      };
    }
    await local.setString(section.key, merged is String ? merged : jsonEncode(merged));
  }

  // ---- Memories ----

  SyncMemories localMemories() {
    final languages = _decoded(SettingsSection.languages);
    final remembered = <String, Map<String, Object?>>{};
    if (languages is Map && languages[_rememberedField] is List) {
      for (final entry in languages[_rememberedField] as List) {
        if (entry is Map) remembered['${entry['userId']}:${entry['scopeId']}'] = Map<String, Object?>.from(entry);
      }
    }
    final queues = _decoded(SettingsSection.collectionQueues);
    final watched = _decoded(SettingsSection.watchedLanguages);
    return SyncMemories.fromJson({
      'remembered': remembered,
      'queues': queues is List ? queues : const [],
      'watched': watched is Map ? watched : const {},
    });
  }

  Future<void> _writeMemories(SyncMemories memories) async {
    final languages = _decoded(SettingsSection.languages);
    final languageMap = languages is Map ? Map<String, Object?>.from(languages) : <String, Object?>{};
    languageMap[_rememberedField] = memories.remembered.values.toList();
    await local.setString(SettingsSection.languages.key, jsonEncode(languageMap));
    await local.setString(SettingsSection.collectionQueues.key, jsonEncode(memories.queues));
    await local.setString(SettingsSection.watchedLanguages.key, jsonEncode(memories.watched));
  }

  // ---- Keeping track of changes here ----

  /// [setup] with each followed section's value as it is here now; a section
  /// that differs from what was last seen is marked changed now. [changed]
  /// says whether anything did - a reason to sync soon.
  ({SyncSetup setup, bool changed}) track(SyncSetup setup) {
    if (!setup.enabled) return (setup: setup, changed: false);
    final now = clock().toUtc();
    final sections = Map.of(setup.sections);
    var changed = false;
    for (final section in syncedSettingSections) {
      if (!setup.follows(section)) continue;
      final hash = canonicalJson(localValue(section));
      final known = sections[section];
      if (known == null) {
        // First seen: not a change of this device's, so a later pull wins.
        sections[section] = LocalSection(hash: hash, changedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
      } else if (known.hash != hash) {
        sections[section] = known.copyWith(hash: hash, changedAt: now);
        changed = true;
      }
    }
    return (setup: setup.copyWith(sections: sections), changed: changed);
  }

  // ---- Syncing ----

  /// Meets the account: takes what changed in the profile, gives it what
  /// changed here, merges the memories. The memories are the account's, not
  /// a profile's: they are merged on a device that follows no profile too. Tries again once when another device
  /// wrote in between.
  Future<SyncOutcome> sync(SyncSetup setup,
      {String deviceName = '', DeviceKind deviceKind = DeviceKind.desktop}) async {
    var outcome = await _syncOnce(setup, deviceName: deviceName, deviceKind: deviceKind);
    if (outcome.error == SyncError.writeFailed) {
      outcome = await _syncOnce(outcome.setup, deviceName: deviceName, deviceKind: deviceKind);
    }
    return outcome;
  }

  /// How long a device's "last seen" may be out of date before a sync that
  /// changed nothing else writes it anyway.
  static const seenEvery = Duration(hours: 6);

  /// [setup] with a device id, made up when it has none.
  static SyncSetup withDeviceId(SyncSetup setup) =>
      setup.deviceId.isNotEmpty ? setup : setup.copyWith(deviceId: _newId());

  static SyncRecord _seen(SyncRecord record, SyncSetup setup,
      {required String name, required DeviceKind kind, required DateTime now}) {
    return record
        .withDevice(SyncDevice(id: setup.deviceId, name: name, kind: kind, profileId: setup.profileId, lastSeen: now));
  }

  static bool _needsSeen(SyncRecord record, SyncSetup setup,
      {required String name, required DeviceKind kind, required DateTime now}) {
    final known = record.devices[setup.deviceId];
    return known == null ||
        known.name != name ||
        known.kind != kind ||
        known.profileId != setup.profileId ||
        now.difference(known.lastSeen) > seenEvery;
  }

  Future<SyncOutcome> _syncOnce(SyncSetup setup, {required String deviceName, required DeviceKind deviceKind}) async {
    if (!setup.enabled && !setup.shareMemories) return SyncOutcome(setup: setup);
    setup = withDeviceId(setup);
    final device = deviceName.isNotEmpty ? deviceName : setup.deviceName;
    var record = await remote.read();
    if (record == null) return SyncOutcome(setup: setup, error: SyncError.unreachable);
    final profile = setup.enabled ? record.profile(setup.profileId) : null;
    if (setup.enabled && profile == null) {
      return SyncOutcome(setup: setup.copyWith(enabled: false), record: record, error: SyncError.profileGone);
    }

    if (profile != null) setup = track(setup).setup;
    final now = clock().toUtc();
    final sections = Map.of(setup.sections);
    final profileSections = Map.of(profile?.sections ?? const <SettingsSection, SyncedSection>{});
    final pulled = <SettingsSection>{};
    final pushed = <SettingsSection>{};

    for (final section in syncedSettingSections) {
      if (profile == null || !setup.follows(section)) continue;
      final value = localValue(section);
      final hash = canonicalJson(value);
      final remoteSection = profileSections[section];
      final known = sections[section];
      // A section never synced here counts as unchanged here: the profile is
      // what this device chose to follow.
      final neverSynced = known == null || known.syncedAt == null;
      final action = neverSynced
          ? (remoteSection == null
              ? SectionAction.push
              : (canonicalJson(remoteSection.value) == hash ? SectionAction.none : SectionAction.pull))
          : decideSection(local: known, remote: remoteSection, localHash: hash);
      switch (action) {
        case SectionAction.pull:
          await _writeSection(section, remoteSection!.value);
          final newHash = canonicalJson(localValue(section));
          sections[section] = LocalSection(hash: newHash, changedAt: remoteSection.at, syncedAt: remoteSection.at);
          pulled.add(section);
        case SectionAction.push:
          if (value == null) break;
          final at = (known != null && !neverSynced) ? known.changedAt : now;
          profileSections[section] = SyncedSection(value: value, at: at, by: device);
          sections[section] = LocalSection(hash: hash, changedAt: at, syncedAt: at);
          pushed.add(section);
        case SectionAction.none:
          final at = remoteSection?.at;
          sections[section] = LocalSection(hash: hash, changedAt: known?.changedAt ?? at ?? now, syncedAt: at);
      }
    }

    var dirty = pushed.isNotEmpty;
    if (dirty && profile != null) {
      record = record.withProfile(
        profile.copyWith(sections: profileSections, updatedAt: now, updatedBy: device),
        now: now,
        device: device,
      );
    }

    var memoriesChanged = false;
    if (setup.shareMemories) {
      final mine = localMemories();
      final merged = SyncMemories.merge(record.memories, mine);
      if (!merged.sameAs(mine)) {
        await _writeMemories(merged);
        memoriesChanged = true;
      }
      if (!merged.sameAs(record.memories)) {
        record = record.withMemories(SyncMemories(
            remembered: merged.remembered, queues: merged.queues, watched: merged.watched, updatedAt: now));
        dirty = true;
      }
    }

    if (dirty || _needsSeen(record, setup, name: device, kind: deviceKind, now: now)) {
      record = _seen(record, setup, name: device, kind: deviceKind, now: now);
      dirty = true;
    }

    final newSetup = setup.copyWith(sections: sections, lastSync: now);
    if (dirty) {
      final written = await remote.write(record);
      if (!written) {
        return SyncOutcome(setup: setup, record: record, error: SyncError.writeFailed, pulled: pulled);
      }
      // Another device may have written between the read and the write; the
      // record holds one or the other. Read it back to know.
      final back = await remote.read();
      final landed = profile == null ? null : back?.profile(profile.id);
      final lost = profile != null &&
          (landed == null ||
              pushed.any((section) =>
                  canonicalJson(landed.sections[section]?.value) != canonicalJson(profileSections[section]?.value)));
      if (lost) {
        return SyncOutcome(
          setup: newSetup.copyWith(sections: {
            for (final entry in sections.entries)
              entry.key: pushed.contains(entry.key) ? entry.value.copyWith(syncedAt: DateTime.utc(1970)) : entry.value,
          }),
          record: back,
          error: SyncError.writeFailed,
          pulled: pulled,
        );
      }
      record = back!;
    }
    return SyncOutcome(
      setup: newSetup,
      record: record,
      pulled: pulled,
      pushed: pushed,
      memoriesChanged: memoriesChanged,
    );
  }

  // ---- Profiles ----

  /// A new profile with this device's settings, followed from now on.
  Future<({SyncSetup setup, SyncRecord? record, SyncError? error})> createProfile(
    SyncSetup setup, {
    required String name,
    required DeviceKind kind,
    required String deviceName,
    String? copyFromId,
  }) async {
    final record = await remote.read();
    if (record == null) return (setup: setup, record: null, error: SyncError.unreachable);
    final now = clock().toUtc();
    final source = record.profile(copyFromId);
    final sections = <SettingsSection, SyncedSection>{
      if (source != null)
        ...source.sections
            .map((key, value) => MapEntry(key, SyncedSection(value: value.value, at: now, by: deviceName)))
      else
        for (final section in syncedSettingSections)
          if (localValue(section) case final value?) section: SyncedSection(value: value, at: now, by: deviceName),
    };
    final profile = SyncProfile(
      id: _newId(),
      name: name,
      kind: kind,
      sections: sections,
      updatedAt: now,
      updatedBy: deviceName,
    );
    final withId = withDeviceId(setup);
    var updated = record.withProfile(profile, now: now, device: deviceName);
    // What this device remembers goes along from the start, for the next
    // device to set up from it.
    if (setup.shareMemories) {
      final merged = SyncMemories.merge(record.memories, localMemories());
      updated = updated.withMemories(
          SyncMemories(remembered: merged.remembered, queues: merged.queues, watched: merged.watched, updatedAt: now));
    }
    updated = _seen(updated, withId.copyWith(profileId: () => profile.id), name: deviceName, kind: kind, now: now);
    if (!await remote.write(updated)) return (setup: setup, record: record, error: SyncError.writeFailed);
    final newSetup = SyncSetup(
      enabled: true,
      profileId: profile.id,
      keepOwn: setup.keepOwn,
      shareMemories: setup.shareMemories,
      deviceName: deviceName,
      deviceId: withId.deviceId,
      answeredSetup: true,
      sections: source == null
          ? {
              for (final entry in sections.entries)
                entry.key: LocalSection(hash: canonicalJson(entry.value.value), changedAt: now, syncedAt: now),
            }
          : const {},
    );
    return (setup: newSetup, record: updated, error: null);
  }

  /// Takes [profileId]'s settings here once, without following it: the
  /// sections taken, for reading in again.
  Future<({Set<SettingsSection> taken, SyncError? error})> takeOnce(
    String profileId, {
    Set<SettingsSection> except = const {},
  }) async {
    final record = await remote.read();
    if (record == null) return (taken: <SettingsSection>{}, error: SyncError.unreachable);
    final profile = record.profile(profileId);
    if (profile == null) return (taken: <SettingsSection>{}, error: SyncError.profileGone);
    final taken = <SettingsSection>{};
    for (final entry in profile.sections.entries) {
      if (except.contains(entry.key)) continue;
      if (canonicalJson(entry.value.value) == canonicalJson(localValue(entry.key))) continue;
      await _writeSection(entry.key, entry.value.value);
      taken.add(entry.key);
    }
    return (taken: taken, error: null);
  }

  /// [setup] following [profileId]: its sections are taken over on the next
  /// sync, apart from those kept as this device's own.
  SyncSetup follow(SyncSetup setup, String profileId, {Set<SettingsSection>? keepOwn, required String deviceName}) =>
      SyncSetup(
        enabled: true,
        profileId: profileId,
        keepOwn: keepOwn ?? setup.keepOwn,
        shareMemories: setup.shareMemories,
        deviceName: deviceName,
        deviceId: setup.deviceId,
        answeredSetup: true,
      );

  /// Puts an earlier version of a profile back, as a new change: every
  /// device following it takes it on its next sync.
  Future<({SyncRecord? record, SyncError? error})> restore(ProfileVersion version, {required String deviceName}) async {
    final record = await remote.read();
    if (record == null) return (record: null, error: SyncError.unreachable);
    final current = record.profile(version.profile.id);
    if (current == null) return (record: record, error: SyncError.profileGone);
    final now = clock().toUtc();
    final restored = current.copyWith(
      sections: version.profile.sections
          .map((key, value) => MapEntry(key, SyncedSection(value: value.value, at: now, by: deviceName))),
      updatedAt: now,
      updatedBy: deviceName,
    );
    final updated = record.withProfile(restored, now: now, device: deviceName, coalesce: Duration.zero);
    if (!await remote.write(updated)) return (record: record, error: SyncError.writeFailed);
    return (record: updated, error: null);
  }

  /// Puts back what [change] changed - only [parts] of it when given - as a
  /// new change: every device on the profile takes it on its next sync.
  Future<({SyncRecord? record, SyncError? error})> undo(
    String profileId,
    ProfileChange change, {
    Set<SettingsSection>? parts,
    required String deviceName,
  }) async {
    final record = await remote.read();
    if (record == null) return (record: null, error: SyncError.unreachable);
    final current = record.profile(profileId);
    if (current == null) return (record: record, error: SyncError.profileGone);
    final now = clock().toUtc();
    final sections = Map.of(current.sections);
    for (final entry in change.before.entries) {
      if (parts != null && !parts.contains(entry.key)) continue;
      if (entry.value == null) {
        sections.remove(entry.key);
      } else {
        sections[entry.key] = SyncedSection(value: entry.value, at: now, by: deviceName);
      }
    }
    final updated = record.withProfile(
      current.copyWith(sections: sections, updatedAt: now, updatedBy: deviceName),
      now: now,
      device: deviceName,
      coalesce: Duration.zero,
    );
    if (!await remote.write(updated)) return (record: record, error: SyncError.writeFailed);
    return (record: updated, error: null);
  }

  /// Takes a device off the account's list - one that is gone for good.
  Future<({SyncRecord? record, SyncError? error})> forgetDevice(String deviceId) async {
    final record = await remote.read();
    if (record == null) return (record: null, error: SyncError.unreachable);
    final updated = record.withoutDevice(deviceId);
    if (!await remote.write(updated)) return (record: record, error: SyncError.writeFailed);
    return (record: updated, error: null);
  }

  Future<({SyncRecord? record, SyncError? error})> rename(String profileId, String name, {DeviceKind? kind}) async {
    final record = await remote.read();
    if (record == null) return (record: null, error: SyncError.unreachable);
    final current = record.profile(profileId);
    if (current == null) return (record: record, error: SyncError.profileGone);
    final updated = record.copyWith(profiles: [
      for (final profile in record.profiles)
        profile.id == profileId ? profile.copyWith(name: name, kind: kind) : profile,
    ]);
    if (!await remote.write(updated)) return (record: record, error: SyncError.writeFailed);
    return (record: updated, error: null);
  }

  Future<({SyncRecord? record, SyncError? error})> delete(String profileId) async {
    final record = await remote.read();
    if (record == null) return (record: null, error: SyncError.unreachable);
    final updated = record.withoutProfile(profileId);
    if (!await remote.write(updated)) return (record: record, error: SyncError.writeFailed);
    return (record: updated, error: null);
  }

  static String _newId() {
    final random = math.Random.secure();
    return List.generate(12, (_) => random.nextInt(36).toRadixString(36)).join();
  }
}

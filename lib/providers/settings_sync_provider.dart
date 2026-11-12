import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/settings/arguments_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/watched_languages_provider.dart';
import 'package:chudder/util/application_info.dart';
import 'package:chudder/util/settings_sync/sync_engine.dart';
import 'package:chudder/util/settings_sync/sync_model.dart';
import 'package:chudder/util/settings_transfer.dart';

final _log = Logger('SettingsSync');

class _PrefsStore implements SyncLocalStore {
  _PrefsStore(this.preferences);

  final SharedPreferences preferences;

  @override
  String? getString(String key) => preferences.getString(key);

  @override
  Future<void> setString(String key, String value) => preferences.setString(key, value);
}

class _AccountRemote implements SyncRemote {
  _AccountRemote(this.ref);

  final Ref ref;

  @override
  Future<SyncRecord?> read() async {
    try {
      final prefs = await ref.read(jellyApiProvider).getSyncRecord();
      return prefs == null ? null : SyncRecord.fromPrefs(prefs);
    } catch (error) {
      _log.info('sync: account not reached: $error');
      return null;
    }
  }

  @override
  Future<bool> write(SyncRecord record) async {
    try {
      return await ref.read(jellyApiProvider).setSyncRecord(record.toPrefs());
    } catch (error) {
      _log.info('sync: not written: $error');
      return false;
    }
  }
}

enum SyncStatus { idle, syncing, error }

class SettingsSyncState {
  const SettingsSyncState({
    this.setup = const SyncSetup(),
    this.record,
    this.status = SyncStatus.idle,
    this.error,
    this.taken,
  });

  /// What the last sync took from the profile, and from which device - for
  /// a word on screen that the settings just changed.
  final ({Set<SettingsSection> sections, String by, DateTime at})? taken;

  final SyncSetup setup;

  /// The account's record as last read; null until it was.
  final SyncRecord? record;
  final SyncStatus status;
  final SyncError? error;

  SyncProfile? get profile => record?.profile(setup.profileId);

  SettingsSyncState copyWith({
    SyncSetup? setup,
    SyncRecord? Function()? record,
    SyncStatus? status,
    SyncError? Function()? error,
    ({Set<SettingsSection> sections, String by, DateTime at})? taken,
  }) =>
      SettingsSyncState(
        setup: setup ?? this.setup,
        record: record != null ? record() : this.record,
        status: status ?? this.status,
        error: error != null ? error() : this.error,
        taken: taken ?? this.taken,
      );
}

/// What kind of device this is, to name and suggest profiles by.
DeviceKind currentDeviceKind(ApplicationInfo info) {
  if (kIsWeb) return DeviceKind.web;
  if (leanBackMode) return DeviceKind.tv;
  return switch (info.platform) {
    TargetPlatform.android || TargetPlatform.iOS => DeviceKind.phone,
    _ => DeviceKind.desktop,
  };
}

final settingsSyncProvider = StateNotifierProvider<SettingsSyncNotifier, SettingsSyncState>((ref) {
  // A setup of its own per account on this device.
  final userId = ref.watch(userProvider.select((user) => user?.id));
  return SettingsSyncNotifier(ref, userId);
});

class SettingsSyncNotifier extends StateNotifier<SettingsSyncState> {
  SettingsSyncNotifier(this.ref, this.userId) : super(const SettingsSyncState()) {
    state = state.copyWith(setup: _readSetup());
  }

  final Ref ref;
  final String? userId;

  /// How soon after a change here it is sent.
  static const pushDelay = Duration(seconds: 4);

  late final SyncEngine _engine = SyncEngine(
    local: _PrefsStore(ref.read(sharedPreferencesProvider)),
    remote: _AccountRemote(ref),
  );

  Future<void>? _running;
  Timer? _pushTimer;

  String get _key => 'settingsSync:$userId';

  SyncSetup _readSetup() {
    if (userId == null) return const SyncSetup();
    try {
      return SyncSetup.fromJson(ref.read(sharedPreferencesProvider).getString(_key));
    } catch (_) {
      return const SyncSetup();
    }
  }

  void _saveSetup(SyncSetup setup) {
    state = state.copyWith(setup: setup);
    if (userId == null) return;
    try {
      ref.read(sharedPreferencesProvider).setString(_key, jsonEncode(setup.toJson()));
    } catch (_) {}
  }

  /// This device's name in the profiles' history.
  String get deviceName {
    final own = state.setup.deviceName;
    if (own.isNotEmpty) return own;
    return ref.read(applicationInfoProvider).platformLabel;
  }

  /// What the screen says, where the platform cannot: a phone or a tablet.
  DeviceKind? screenKind;

  DeviceKind get deviceKind {
    final kind = currentDeviceKind(ref.read(applicationInfoProvider));
    return kind == DeviceKind.phone && screenKind == DeviceKind.tablet ? DeviceKind.tablet : kind;
  }

  bool get _offline => ref.read(offlineStateProvider);

  /// Reads the account's record, for the setup prompt and the sync page.
  Future<SyncRecord?> fetchRecord() async {
    if (_offline || userId == null) return null;
    final record = await _AccountRemote(ref).read();
    if (mounted && record != null) state = state.copyWith(record: () => record);
    return record;
  }

  /// Syncs now; one at a time.
  Future<void> syncNow() => _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    _pushTimer?.cancel();
    // The memories sync on a device that follows no profile too.
    if ((!state.setup.enabled && !state.setup.shareMemories) || _offline || userId == null) return;
    state = state.copyWith(status: SyncStatus.syncing);
    final outcome = await _engine.sync(state.setup, deviceName: deviceName, deviceKind: deviceKind);
    if (!mounted) return;
    _saveSetup(outcome.setup);
    await _reload(outcome.pulled, memories: outcome.memoriesChanged);
    final profile = outcome.record?.profile(outcome.setup.profileId);
    final by = outcome.pulled.map((section) => profile?.sections[section]?.by).nonNulls.toSet();
    state = state.copyWith(
      record: outcome.record != null ? () => outcome.record : null,
      status: outcome.error == null ? SyncStatus.idle : SyncStatus.error,
      error: () => outcome.error,
      taken: outcome.pulled.isEmpty ? null : (sections: outcome.pulled, by: by.join(', '), at: DateTime.now()),
    );
    if (outcome.pulled.isNotEmpty || outcome.pushed.isNotEmpty || outcome.error != null) {
      _log.info('sync: took ${outcome.pulled.map((s) => s.name)}, gave ${outcome.pushed.map((s) => s.name)}'
          '${outcome.memoriesChanged ? ', memories merged' : ''}${outcome.error != null ? ', ${outcome.error}' : ''}');
    }
  }

  /// Reads settings stored by a sync into the running app.
  Future<void> _reload(Set<SettingsSection> sections, {required bool memories}) async {
    if (sections.isEmpty && !memories) return;
    await ref.read(sharedUtilityProvider).loadSettings();
    if (sections.contains(SettingsSection.languages) || memories) {
      ref.read(languagePreferencesProvider.notifier).reload();
    }
    if (memories) ref.read(watchedLanguagesProvider).reload();
  }

  /// Looks for changes made here since the last look; sends them shortly
  /// after the last one.
  void checkForChanges() {
    if (!state.setup.enabled) return;
    final tracked = _engine.track(state.setup);
    if (!tracked.changed) return;
    _saveSetup(tracked.setup);
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, syncNow);
  }

  /// The sections in which [profile] differs from this device now: what
  /// following it would change here.
  List<SettingsSection> differences(SyncProfile profile) => [
        for (final section in syncedSettingSections)
          if (profile.sections[section] case final remote?)
            if (canonicalJson(remote.value) != canonicalJson(_engine.localValue(section))) section,
      ];

  /// Whether there is a change here not yet sent.
  bool get hasPendingChanges => _pushTimer?.isActive == true;

  // ---- Choices made on the sync page and in the setup prompt ----

  Future<SyncError?> createProfile(String name, {DeviceKind? kind, String? copyFromId}) async {
    final result = await _engine.createProfile(
      state.setup,
      name: name,
      kind: kind ?? deviceKind,
      deviceName: deviceName,
      copyFromId: copyFromId,
    );
    if (!mounted) return result.error;
    if (result.error == null) {
      _saveSetup(result.setup);
      state = state.copyWith(record: () => result.record, error: () => null);
      if (copyFromId != null) await syncNow();
    }
    return result.error;
  }

  /// Follows [profileId] from now on and takes its settings, apart from
  /// [keepOwn].
  Future<void> follow(String profileId, {Set<SettingsSection>? keepOwn}) async {
    _saveSetup(_engine.follow(state.setup, profileId, keepOwn: keepOwn, deviceName: deviceName));
    await syncNow();
  }

  /// Takes a profile's settings here once; this device does not follow it.
  Future<SyncError?> takeOnce(String profileId) async {
    final result = await _engine.takeOnce(profileId);
    if (!mounted) return result.error;
    await _reload(result.taken, memories: false);
    if (result.taken.isNotEmpty) {
      final profile = state.record?.profile(profileId);
      state = state.copyWith(taken: (sections: result.taken, by: profile?.name ?? '', at: DateTime.now()));
    }
    return result.error;
  }

  /// Undoes [change] on the profile this device is on - [parts] of it, or
  /// all - and takes the result here.
  Future<SyncError?> undo(ProfileChange change, {Set<SettingsSection>? parts}) async {
    final profileId = state.setup.profileId;
    if (profileId == null) return SyncError.profileGone;
    final result = await _engine.undo(profileId, change, parts: parts, deviceName: deviceName);
    if (!mounted) return result.error;
    if (result.record != null) state = state.copyWith(record: () => result.record);
    if (result.error == null) await syncNow();
    return result.error;
  }

  /// Takes a device that is gone off the account's list.
  Future<SyncError?> forgetDevice(String deviceId) async {
    final result = await _engine.forgetDevice(deviceId);
    if (mounted && result.record != null) state = state.copyWith(record: () => result.record);
    return result.error;
  }

  /// The first device on an account: a profile is made from it, named
  /// [name], and followed - every device syncs through a profile.
  Future<SyncError?> startFirstProfile(String name) => createProfile(name);

  void stop() => _saveSetup(state.setup.copyWith(enabled: false, profileId: () => null, sections: const {}));

  void answerSetup() => _saveSetup(state.setup.copyWith(answeredSetup: true));

  Future<void> setKeepOwn(SettingsSection section, bool keep) async {
    final keepOwn = {...state.setup.keepOwn};
    keep ? keepOwn.add(section) : keepOwn.remove(section);
    final sections = Map.of(state.setup.sections)..remove(section);
    _saveSetup(state.setup.copyWith(keepOwn: keepOwn, sections: sections));
    // Followed again: take the profile's.
    if (!keep) await syncNow();
  }

  Future<void> setShareMemories(bool share) async {
    _saveSetup(state.setup.copyWith(shareMemories: share));
    if (share) await syncNow();
  }

  void setDeviceName(String name) => _saveSetup(state.setup.copyWith(deviceName: name.trim()));

  Future<SyncError?> rename(String profileId, String name, {DeviceKind? kind}) async {
    final result = await _engine.rename(profileId, name, kind: kind);
    if (mounted && result.record != null) state = state.copyWith(record: () => result.record);
    return result.error;
  }

  Future<SyncError?> delete(String profileId) async {
    final result = await _engine.delete(profileId);
    if (!mounted) return result.error;
    if (result.record != null) state = state.copyWith(record: () => result.record);
    if (result.error == null && state.setup.profileId == profileId) stop();
    return result.error;
  }

  Future<SyncError?> restore(ProfileVersion version) async {
    final result = await _engine.restore(version, deviceName: deviceName);
    if (!mounted) return result.error;
    if (result.record != null) state = state.copyWith(record: () => result.record);
    if (result.error == null) await syncNow();
    return result.error;
  }

  @override
  void dispose() {
    _pushTimer?.cancel();
    super.dispose();
  }
}

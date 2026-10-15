// Settings sync between devices on one account, with the account's record
// kept as the server keeps it (text by key, written whole) and each device's
// settings in a map of its own.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/settings_sync/sync_engine.dart';
import 'package:chudder/util/settings_sync/sync_model.dart';
import 'package:chudder/util/settings_transfer.dart';

class _Device implements SyncLocalStore {
  final Map<String, String> values = {};

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  Map<String, dynamic> json(SettingsSection section) => jsonDecode(values[section.key]!) as Map<String, dynamic>;
  void set(SettingsSection section, Object value) => values[section.key] = jsonEncode(value);
}

class _Account implements SyncRemote {
  Map<String, String>? prefs;
  bool reachable = true;

  /// Drops the next write after reading it back as someone else's.
  int loseWrites = 0;

  @override
  Future<SyncRecord?> read() async => reachable ? SyncRecord.fromPrefs(prefs) : null;

  @override
  Future<bool> write(SyncRecord record) async {
    if (!reachable) return false;
    if (loseWrites > 0) {
      loseWrites--;
      return true;
    }
    prefs = record.toPrefs();
    return true;
  }
}

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 15, 12);
  DateTime call() => now;
  void advance(Duration by) => now = now.add(by);
}

void main() {
  late _Account account;
  late _Clock clock;
  late _Device tv, phone;
  late SyncEngine tvSync, phoneSync;
  late SyncSetup tvSetup, phoneSetup;

  setUp(() async {
    account = _Account();
    clock = _Clock();
    tv = _Device();
    phone = _Device();
    tvSync = SyncEngine(local: tv, remote: account, clock: clock.call);
    phoneSync = SyncEngine(local: phone, remote: account, clock: clock.call);

    tv.set(SettingsSection.player, {'enableSpeedBoost': true, 'playerOptions': 'libMDK', 'skipForward': 30});
    tv.set(SettingsSection.subtitles, {'fontSize': 60});
    tv.set(SettingsSection.app, {'posterSize': 1.4, 'syncPath': '/tv/downloads'});
    tv.set(SettingsSection.languages, {
      'askToRemember': true,
      'rules': [
        {'language': 'ja', 'keepOriginalAudio': true}
      ],
      'remembered': [
        {'userId': 'u', 'scopeId': 'show-a', 'audioLanguage': 'ja', 'savedAt': '2026-10-01T00:00:00.000'}
      ],
    });

    phone.set(SettingsSection.player, {'enableSpeedBoost': false, 'playerOptions': 'libMPV', 'skipForward': 10});
    phone.set(SettingsSection.subtitles, {'fontSize': 30});
    phone.set(SettingsSection.app, {'posterSize': 0.8, 'syncPath': '/phone/downloads'});
    phone.set(SettingsSection.languages, {
      'askToRemember': false,
      'rules': [],
      'remembered': [
        {'userId': 'u', 'scopeId': 'show-b', 'subtitlesOff': true, 'savedAt': '2026-10-02T00:00:00.000'}
      ],
    });

    final created = await tvSync.createProfile(const SyncSetup(), name: 'TV', kind: DeviceKind.tv, deviceName: 'TV');
    tvSetup = created.setup;
    phoneSetup = phoneSync.follow(const SyncSetup(), tvSetup.profileId!, deviceName: 'Phone');
  });

  Future<SyncOutcome> syncTv() async {
    final outcome = await tvSync.sync(tvSetup, deviceKind: DeviceKind.tv);
    tvSetup = outcome.setup;
    return outcome;
  }

  Future<SyncOutcome> syncPhone() async {
    final outcome = await phoneSync.sync(phoneSetup, deviceKind: DeviceKind.phone);
    phoneSetup = outcome.setup;
    return outcome;
  }

  group('setting a device up from a profile', () {
    test('it takes every section, and keeps what is its own', () async {
      final outcome = await syncPhone();
      expect(outcome.error, isNull);
      expect(outcome.pulled, containsAll([SettingsSection.player, SettingsSection.subtitles, SettingsSection.app]));
      expect(phone.json(SettingsSection.player)['skipForward'], 30);
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60);
      // What describes the phone stays the phone's.
      expect(phone.json(SettingsSection.player)['playerOptions'], 'libMPV');
      expect(phone.json(SettingsSection.app)['syncPath'], '/phone/downloads');
      // The rules came; what the phone remembered stayed, and the TV's joined it.
      expect(phone.json(SettingsSection.languages)['rules'], hasLength(1));
      final remembered = (phone.json(SettingsSection.languages)['remembered'] as List).map((e) => e['scopeId']);
      expect(remembered, containsAll(['show-a', 'show-b']));
    });

    test('a section kept as its own is neither taken nor given', () async {
      phoneSetup = phoneSync.follow(const SyncSetup(), tvSetup.profileId!,
          keepOwn: {SettingsSection.subtitles}, deviceName: 'Phone');
      await syncPhone();
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 30);

      phone.set(SettingsSection.subtitles, {'fontSize': 25});
      clock.advance(const Duration(minutes: 1));
      final outcome = await syncPhone();
      expect(outcome.pushed, isNot(contains(SettingsSection.subtitles)));
      await syncTv();
      expect(tv.json(SettingsSection.subtitles)['fontSize'], 60);
    });
  });

  group('changes', () {
    setUp(() async => await syncPhone());

    test('one made on the phone reaches the TV', () async {
      clock.advance(const Duration(minutes: 5));
      phone.set(SettingsSection.player, {...phone.json(SettingsSection.player), 'skipForward': 15});
      final pushed = await syncPhone();
      expect(pushed.pushed, {SettingsSection.player});

      clock.advance(const Duration(minutes: 1));
      final pulled = await syncTv();
      expect(pulled.pulled, {SettingsSection.player});
      expect(tv.json(SettingsSection.player)['skipForward'], 15);
      expect(tv.json(SettingsSection.player)['playerOptions'], 'libMDK');
    });

    test('changes to different sections on both devices both survive', () async {
      clock.advance(const Duration(minutes: 5));
      phone.set(SettingsSection.player, {...phone.json(SettingsSection.player), 'skipForward': 15});
      tv.set(SettingsSection.subtitles, {'fontSize': 70});
      tvSetup = tvSync.track(tvSetup).setup;
      phoneSetup = phoneSync.track(phoneSetup).setup;
      await syncPhone();
      await syncTv();
      await syncPhone();
      expect(tv.json(SettingsSection.player)['skipForward'], 15);
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 70);
    });

    test('the same section changed on both: the later change wins on both', () async {
      clock.advance(const Duration(minutes: 5));
      tv.set(SettingsSection.subtitles, {'fontSize': 70});
      tvSetup = tvSync.track(tvSetup).setup;
      clock.advance(const Duration(minutes: 1));
      phone.set(SettingsSection.subtitles, {'fontSize': 40});
      phoneSetup = phoneSync.track(phoneSetup).setup;
      // The TV gets there first, with the older change.
      await syncTv();
      await syncPhone();
      await syncTv();
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 40);
      expect(tv.json(SettingsSection.subtitles)['fontSize'], 40);
    });

    test('nothing changed: nothing written', () async {
      final before = account.prefs;
      final outcome = await syncTv();
      expect(outcome.pushed, isEmpty);
      expect(outcome.pulled, isEmpty);
      expect(identical(account.prefs, before), isTrue);
    });
  });

  group('memories', () {
    test('remembered languages from both devices end up on both', () async {
      await syncPhone();
      await syncTv();
      final tvRemembered = (tv.json(SettingsSection.languages)['remembered'] as List).map((e) => e['scopeId']);
      expect(tvRemembered, containsAll(['show-a', 'show-b']));
    });

    test('the same show remembered on both: the later choice', () async {
      await syncPhone();
      clock.advance(const Duration(minutes: 5));
      phone.set(SettingsSection.languages, {
        ...phone.json(SettingsSection.languages),
        'remembered': [
          {'userId': 'u', 'scopeId': 'show-a', 'audioLanguage': 'en', 'savedAt': '2026-10-10T00:00:00.000'}
        ],
      });
      await syncPhone();
      await syncTv();
      final showA =
          (tv.json(SettingsSection.languages)['remembered'] as List).firstWhere((e) => e['scopeId'] == 'show-a');
      expect(showA['audioLanguage'], 'en');
    });

    test('collection queues and watched languages merge without counting twice', () async {
      tv.values[SettingsSection.collectionQueues.key] = jsonEncode([
        {
          'userId': 'u',
          'id': 'pokemon',
          'itemIds': ['a', 'b'],
          'savedAt': '2026-10-01T00:00:00.000'
        },
      ]);
      phone.values[SettingsSection.collectionQueues.key] = jsonEncode([
        {
          'userId': 'u',
          'id': 'pokemon',
          'itemIds': ['b', 'a'],
          'savedAt': '2026-10-05T00:00:00.000'
        },
        {
          'userId': 'u',
          'id': 'ghibli',
          'itemIds': ['x', 'y'],
          'savedAt': '2026-10-03T00:00:00.000'
        },
      ]);
      final day = DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
      tv.values[SettingsSection.watchedLanguages.key] = jsonEncode({
        'ja': [5, day]
      });
      phone.values[SettingsSection.watchedLanguages.key] = jsonEncode({
        'ja': [3, day],
        'en': [2, day]
      });
      await syncPhone();
      await syncTv();
      await syncPhone();
      for (final device in [tv, phone]) {
        final queues = jsonDecode(device.values[SettingsSection.collectionQueues.key]!) as List;
        expect(queues.map((q) => q['id']), unorderedEquals(['pokemon', 'ghibli']));
        expect(queues.firstWhere((q) => q['id'] == 'pokemon')['itemIds'], ['b', 'a']);
        final watched = jsonDecode(device.values[SettingsSection.watchedLanguages.key]!) as Map;
        expect(watched['ja'][0], 5);
        expect(watched['en'][0], 2);
      }
      // Meeting again changes nothing.
      final again = await syncTv();
      expect(again.memoriesChanged, isFalse);
    });

    test('a device that does not share memories keeps them to itself', () async {
      phoneSetup = phoneSetup.copyWith(shareMemories: false);
      await syncPhone();
      final remembered = (phone.json(SettingsSection.languages)['remembered'] as List).map((e) => e['scopeId']);
      expect(remembered, ['show-b']);
    });
  });

  group('history', () {
    test('earlier versions are kept, one per sitting, and can be put back', () async {
      await syncPhone();
      clock.advance(const Duration(hours: 1));
      tv.set(SettingsSection.subtitles, {'fontSize': 70});
      await syncTv();
      clock.advance(const Duration(minutes: 2));
      tv.set(SettingsSection.subtitles, {'fontSize': 80});
      await syncTv();

      final record = SyncRecord.fromPrefs(account.prefs);
      final versions = record.history[tvSetup.profileId]!;
      expect(versions, hasLength(1), reason: 'two changes minutes apart are one sitting');
      expect(versions.single.profile.sections[SettingsSection.subtitles]!.value, {'fontSize': 60});

      clock.advance(const Duration(minutes: 1));
      final restored = await phoneSync.restore(versions.single, deviceName: 'Phone');
      expect(restored.error, isNull);
      await syncTv();
      await syncPhone();
      expect(tv.json(SettingsSection.subtitles)['fontSize'], 60);
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60);
    });

    test('at most twelve versions', () async {
      for (var i = 0; i < 20; i++) {
        clock.advance(const Duration(hours: 1));
        tv.set(SettingsSection.subtitles, {'fontSize': 40 + i});
        await syncTv();
      }
      expect(SyncRecord.fromPrefs(account.prefs).history[tvSetup.profileId], hasLength(SyncRecord.maxHistory));
    });
  });

  group('when things go wrong', () {
    test('the account out of reach: nothing changes here', () async {
      account.reachable = false;
      final outcome = await syncPhone();
      expect(outcome.error, SyncError.unreachable);
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 30);
    });

    test('a profile deleted elsewhere: this device stops following it', () async {
      await syncPhone();
      await tvSync.delete(tvSetup.profileId!);
      final outcome = await syncPhone();
      expect(outcome.error, SyncError.profileGone);
      expect(phoneSetup.enabled, isFalse);
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60, reason: 'what it had stays');
    });

    test('a write lost to another device is tried again', () async {
      await syncPhone();
      clock.advance(const Duration(minutes: 5));
      phone.set(SettingsSection.subtitles, {'fontSize': 45});
      account.loseWrites = 1;
      final outcome = await syncPhone();
      expect(outcome.error, isNull);
      await syncTv();
      expect(tv.json(SettingsSection.subtitles)['fontSize'], 45);
    });
  });

  group('profiles', () {
    test('a second profile made from the first starts as a copy', () async {
      final made = await phoneSync.createProfile(phoneSetup,
          name: 'Phone', kind: DeviceKind.phone, deviceName: 'Phone', copyFromId: tvSetup.profileId);
      phoneSetup = made.setup;
      await syncPhone();
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60);
      expect(SyncRecord.fromPrefs(account.prefs).profiles.map((p) => p.name), ['TV', 'Phone']);
    });

    test('used once: taken here without following, device-only fields kept', () async {
      final taken = await phoneSync.takeOnce(tvSetup.profileId!);
      expect(taken.error, isNull);
      expect(taken.taken, contains(SettingsSection.subtitles));
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60);
      expect(phone.json(SettingsSection.app)['syncPath'], '/phone/downloads');
      // Not following: a later change on the TV does not come.
      tv.set(SettingsSection.subtitles, {'fontSize': 99});
      clock.advance(const Duration(hours: 1));
      await syncTv();
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60);
    });

    test('renamed', () async {
      await tvSync.rename(tvSetup.profileId!, 'Living room');
      expect(SyncRecord.fromPrefs(account.prefs).profile(tvSetup.profileId)!.name, 'Living room');
    });
  });

  group('devices and changes', () {
    test('every device on the account, with its profile and kind', () async {
      await syncPhone();
      final record = SyncRecord.fromPrefs(account.prefs);
      final devices = record.devicesOn(tvSetup.profileId!);
      expect(devices.map((device) => device.name), unorderedEquals(['TV', 'Phone']));
      expect(devices.firstWhere((device) => device.name == 'Phone').kind, DeviceKind.phone);
      expect(phoneSetup.deviceId, isNotEmpty);
      expect(phoneSetup.deviceId, isNot(tvSetup.deviceId));
    });

    test('a device that is gone is taken off the list', () async {
      await syncPhone();
      await tvSync.forgetDevice(phoneSetup.deviceId);
      expect(SyncRecord.fromPrefs(account.prefs).devices.keys, [tvSetup.deviceId]);
    });

    test('recent changes say who changed what, and one part of a change can be undone', () async {
      await syncPhone();
      clock.advance(const Duration(hours: 1));
      phone.set(SettingsSection.subtitles, {'fontSize': 45});
      phone.set(SettingsSection.player, {...phone.json(SettingsSection.player), 'skipForward': 5});
      phoneSetup = phoneSync.track(phoneSetup).setup;
      await syncPhone();

      var record = SyncRecord.fromPrefs(account.prefs);
      final changes = record.changesOf(tvSetup.profileId!);
      expect(changes.first.by, 'Phone');
      expect(changes.first.before.keys, unorderedEquals([SettingsSection.subtitles, SettingsSection.player]));
      expect(changes.first.before[SettingsSection.subtitles], {'fontSize': 60});

      clock.advance(const Duration(minutes: 1));
      final undone =
          await tvSync.undo(tvSetup.profileId!, changes.first, parts: {SettingsSection.subtitles}, deviceName: 'TV');
      expect(undone.error, isNull);
      await syncTv();
      await syncPhone();
      expect(phone.json(SettingsSection.subtitles)['fontSize'], 60, reason: 'undone');
      expect(phone.json(SettingsSection.player)['skipForward'], 5, reason: 'left as changed');
      record = SyncRecord.fromPrefs(account.prefs);
      expect(record.changesOf(tvSetup.profileId!).first.by, 'TV', reason: 'the undo is a change too');
    });
  });

  test('a device\'s own setup is kept and read back', () {
    final setup = SyncSetup(
      enabled: true,
      profileId: 'p',
      keepOwn: const {SettingsSection.app},
      deviceName: 'Living room TV',
      sections: {
        SettingsSection.player: LocalSection(hash: 'h', changedAt: DateTime.utc(2026), syncedAt: DateTime.utc(2026)),
      },
      answeredSetup: true,
    );
    final back = SyncSetup.fromJson(jsonEncode(setup.toJson()));
    expect(back.keepOwn, {SettingsSection.app});
    expect(back.deviceName, 'Living room TV');
    expect(back.sections[SettingsSection.player]!.syncedAt, DateTime.utc(2026));
    expect(back.answeredSetup, isTrue);
  });
}

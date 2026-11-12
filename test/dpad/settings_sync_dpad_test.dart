// The settings-profile dialogs, by remote.

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/providers/settings_sync_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/screens/settings/client_sections/client_settings_sync.dart';
import 'package:chudder/util/settings_sync/sync_engine.dart';
import 'package:chudder/util/settings_sync/sync_model.dart';
import 'package:chudder/util/settings_transfer.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

import 'dpad_fakes.dart';
import 'dpad_walk.dart';

final _at = DateTime.now().subtract(const Duration(hours: 3));

SyncProfile _profile(String id, String name, DeviceKind kind, {int fontSize = 60, int skip = 30}) => SyncProfile(
      id: id,
      name: name,
      kind: kind,
      updatedAt: _at,
      updatedBy: 'Living room TV',
      sections: {
        SettingsSection.subtitles: SyncedSection(value: {'fontSize': fontSize}, at: _at, by: 'Living room TV'),
        SettingsSection.player: SyncedSection(value: {'skipForward': skip}, at: _at, by: 'Living room TV'),
      },
    );

final _record = SyncRecord(
  profiles: [_profile('tv', 'TV', DeviceKind.tv), _profile('phone', 'Phone', DeviceKind.phone)],
  history: {
    'tv': [
      // Before the phone changed both parts.
      ProfileVersion(
        profile: _profile('tv', 'TV', DeviceKind.tv, fontSize: 50, skip: 10),
        replacedAt: _at,
        replacedBy: 'Phone',
      ),
    ],
  },
  devices: {
    'this': SyncDevice(id: 'this', name: 'Laptop', kind: DeviceKind.desktop, profileId: 'tv', lastSeen: _at),
    'tv1': SyncDevice(id: 'tv1', name: 'Living room TV', kind: DeviceKind.tv, profileId: 'tv', lastSeen: _at),
  },
);

/// The sync state with a record already read and this device on TV.
class _OnTv extends SettingsSyncNotifier {
  _OnTv(super.ref, super.userId) {
    state = SettingsSyncState(
      setup: const SyncSetup(
        enabled: true,
        profileId: 'tv',
        deviceName: 'Laptop',
        deviceId: 'this',
        answeredSetup: true,
      ),
      record: _record,
    );
  }
}

Future<List<Override>> _overrides() async {
  SharedPreferences.setMockInitialValues({});
  return [
    ...playerFakes,
    sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
    settingsSyncProvider.overrideWith((ref) => _OnTv(ref, 'user')),
  ];
}

void main() {
  testWidgets('the settings page groups: shared memories, then the profile', (tester) async {
    await pumpDpad(
      tester,
      overrides: await _overrides(),
      child: Material(
        child: Consumer(builder: (context, ref, _) => ListView(children: buildClientSettingsSync(context, ref))),
      ),
    );
    expect(find.text('Shared across all your devices'), findsOneWidget);
    expect(find.text('Syncing with the profile TV'), findsOneWidget);
    final walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(ListView));
  });

  testWidgets('profiles: join, the menu beside each, start one, leave', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => const SyncProfilesDialog()),
      overrides: await _overrides(),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SyncProfilesDialog));
    walk.expectAllReachable(within: find.byType(SyncProfilesDialog));
    expect(find.textContaining("this device's profile"), findsOneWidget);
    expect(find.text('Leave this profile'), findsOneWidget);
  });

  testWidgets('what this device takes: every part and the memories', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => const SyncSectionsDialog()),
      overrides: await _overrides(),
    );
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SyncSectionsDialog));
    walk.expectAllReachable(within: find.byType(SyncSectionsDialog));
  });

  testWidgets('recent changes: who changed what, and each part to undo', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => const SyncChangesDialog()),
      overrides: await _overrides(),
    );
    expect(find.textContaining('Phone changed'), findsOneWidget);
    var walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SyncChangesDialog));
    walk.expectAllReachable(within: find.byType(SyncChangesDialog));

    await tester.tap(find.textContaining('Phone changed'));
    await tester.pumpAndSettle();
    expect(find.text('Undo all of it'), findsOneWidget);
    expect(find.textContaining('Undo the change to'), findsNWidgets(2));
    walk = await walkDpad(tester);
    walk.expectAllReachable(within: find.byType(AlertDialog).last);
  });

  testWidgets('devices: this one to rename, the others to forget', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => const SyncDevicesDialog()),
      overrides: await _overrides(),
    );
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Living room TV'), findsOneWidget);
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SyncDevicesDialog));
    walk.expectAllReachable(within: find.byType(SyncDevicesDialog));
  });

  testWidgets('a new device: its own kind\'s profile suggested, or a new one', (tester) async {
    await openDpad(
      tester,
      (context) => showTvDialog(context: context, builder: (_) => SyncSetupDialog(record: _record)),
      overrides: await _overrides(),
    );
    // A test runs as a phone: the phone profile is suggested and takes all.
    expect(find.textContaining('suggested for this device'), findsOneWidget);
    expect(find.text('New profile: Phone'), findsOneWidget);
    expect(find.textContaining('This device keeps its own'), findsNothing);
    // The TV's, from another kind of device: this one keeps its own look.
    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This device keeps its own'), findsOneWidget);
    await tester.tap(find.text('Choose what to take'));
    await tester.pumpAndSettle();
    final walk = await walkDpad(tester);
    walk.expectStartsInside(find.byType(SyncSetupDialog));
    walk.expectAllReachable(within: find.byType(SyncSetupDialog));
  });
}

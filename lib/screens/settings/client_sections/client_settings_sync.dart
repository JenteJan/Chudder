import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:intl/intl.dart';

import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/settings_sync_provider.dart';
import 'package:chudder/screens/settings/client_sections/client_settings_backup.dart';
import 'package:chudder/screens/settings/settings_list_tile.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/shared/outlined_text_field.dart';
import 'package:chudder/screens/video_player/components/track_option_row.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/settings_sync/sync_engine.dart';
import 'package:chudder/util/settings_sync/sync_model.dart';
import 'package:chudder/util/settings_transfer.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

/// "5 min ago" and the like.
String syncWhen(BuildContext context, DateTime? time) {
  if (time == null) return context.localized.syncNever;
  final since = DateTime.now().difference(time.toLocal());
  if (since.inMinutes < 1) return context.localized.syncWhenJustNow;
  if (since.inHours < 1) return context.localized.syncWhenMinutes(since.inMinutes);
  if (since.inDays < 1) return context.localized.syncWhenHours(since.inHours);
  if (since.inDays < 7) return context.localized.syncWhenDays(since.inDays);
  return DateFormat.yMMMd().format(time.toLocal());
}

IconData deviceKindIcon(DeviceKind kind) => switch (kind) {
      DeviceKind.phone => IconsaxPlusLinear.mobile,
      DeviceKind.tablet => IconsaxPlusLinear.mobile,
      DeviceKind.desktop => IconsaxPlusLinear.monitor,
      DeviceKind.tv => IconsaxPlusLinear.screenmirroring,
      DeviceKind.web => IconsaxPlusLinear.global,
    };

String deviceKindLabel(BuildContext context, DeviceKind kind) => switch (kind) {
      DeviceKind.phone => context.localized.deviceKindPhone,
      DeviceKind.tablet => context.localized.deviceKindTablet,
      DeviceKind.desktop => context.localized.deviceKindDesktop,
      DeviceKind.tv => context.localized.deviceKindTv,
      DeviceKind.web => context.localized.deviceKindWeb,
    };

String? syncErrorText(BuildContext context, SyncError? error) => switch (error) {
      SyncError.unreachable => context.localized.syncErrorUnreachable,
      SyncError.profileGone => context.localized.syncErrorProfileGone,
      SyncError.writeFailed => context.localized.syncErrorWrite,
      null => null,
    };

String _parts(BuildContext context, Iterable<SettingsSection> sections) =>
    sections.map((section) => settingsSectionLabel(context, section)).join(', ');

void _showError(BuildContext context, SyncError? error) {
  final text = syncErrorText(context, error);
  if (text != null && context.mounted) FladderSnack.show(text, context: context);
}

/// Settings > Settings profile: the profile this device is on, how it
/// syncs, and the file backup - the one place for all of it.
List<Widget> buildClientSettingsSync(BuildContext context, WidgetRef ref) {
  final sync = ref.watch(settingsSyncProvider);
  final notifier = ref.read(settingsSyncProvider.notifier);
  final online = !ref.watch(offlineStateProvider);
  final setup = sync.setup;
  final profile = sync.profile;
  final onProfile = setup.enabled;
  final error = syncErrorText(context, sync.error);

  final status = !onProfile
      ? context.localized.syncNoProfileDesc
      : sync.status == SyncStatus.syncing
          ? context.localized.syncSyncing
          : context.localized.syncStatusUpToDate(syncWhen(context, setup.lastSync));
  final changes = profile == null ? const <ProfileChange>[] : sync.record?.changesOf(profile.id) ?? const [];
  final devices = profile == null ? const <SyncDevice>[] : sync.record?.devicesOn(profile.id) ?? const [];

  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.settingsProfileSync),
    [
      SettingsListTile(
        icon: onProfile ? deviceKindIcon(profile?.kind ?? notifier.deviceKind) : IconsaxPlusLinear.profile_delete,
        label: Text(onProfile ? (profile?.name ?? '…') : context.localized.syncNoProfile),
        // A deleted profile takes this device off it: the reason still shows.
        subLabel: Text(error != null ? '$status\n$error' : status),
        onTap: online ? () => showSyncProfiles(context) : null,
      ),
      if (onProfile) ...[
        SettingsListTile(
          icon: IconsaxPlusLinear.refresh,
          label: Text(context.localized.syncNow),
          onTap: online
              ? () async {
                  final before = ref.read(settingsSyncProvider).taken;
                  await notifier.syncNow();
                  if (!context.mounted) return;
                  final after = ref.read(settingsSyncProvider);
                  // What changed has its own word; otherwise say it was looked at.
                  if (after.error == null && identical(after.taken, before)) {
                    FladderSnack.show(context.localized.syncUpToDate, context: context);
                  }
                }
              : null,
        ),
        SettingsListTile(
          icon: IconsaxPlusLinear.setting_4,
          label: Text(context.localized.syncParts),
          subLabel: Text(context.localized.syncPartsSummary(
            syncedSettingSections.where(setup.follows).length,
            syncedSettingSections.length,
          )),
          onTap: () => showTvDialog(context: context, builder: (_) => const SyncSectionsDialog()),
        ),
        SettingsListTile(
          icon: IconsaxPlusLinear.clock,
          label: Text(context.localized.syncRecentChanges),
          subLabel: Text(changes.isEmpty
              ? context.localized.syncRecentChangesNone
              : context.localized.syncChangeTitle(changes.first.by, _parts(context, changes.first.before.keys))),
          onTap: online && profile != null
              ? () async {
                  await notifier.fetchRecord();
                  if (context.mounted) {
                    await showTvDialog(context: context, builder: (_) => const SyncChangesDialog());
                  }
                }
              : null,
        ),
        SettingsListTile(
          icon: IconsaxPlusLinear.devices,
          label: Text(context.localized.syncDevices),
          subLabel: Text(context.localized.syncDevicesSummary(devices.length, notifier.deviceName)),
          onTap: () => showTvDialog(context: context, builder: (_) => const SyncDevicesDialog()),
        ),
      ],
      SettingsListTile(
        icon: IconsaxPlusLinear.document_upload,
        label: Text(context.localized.settingsExportFile),
        subLabel: Text(context.localized.settingsExportFileDesc),
        onTap: () => exportSettingsToFile(context, ref),
      ),
      SettingsListTile(
        icon: IconsaxPlusLinear.document_download,
        label: Text(context.localized.settingsImportFile),
        subLabel: Text(context.localized.settingsImportFileDesc),
        onTap: () => importSettingsFromFile(context, ref),
      ),
    ],
  );
}

/// The profiles on the account: join one, make one, rename or delete.
Future<void> showSyncProfiles(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final record = await container.read(settingsSyncProvider.notifier).fetchRecord();
  if (!context.mounted) return;
  if (record == null) {
    FladderSnack.show(context.localized.syncErrorUnreachable, context: context);
    return;
  }
  await showTvDialog(context: context, builder: (_) => const SyncProfilesDialog());
}

Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) => showTvDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title, hint: context.localized.syncProfileName, initial: initial),
    );

class SyncProfilesDialog extends ConsumerWidget {
  const SyncProfilesDialog({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref, {SyncProfile? copyOf}) async {
    final notifier = ref.read(settingsSyncProvider.notifier);
    final name = await _askName(
      context,
      title:
          copyOf == null ? context.localized.syncCreateProfile : context.localized.syncCreateProfileCopy(copyOf.name),
      initial: copyOf == null ? deviceKindLabel(context, notifier.deviceKind) : '',
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    _showError(context, await notifier.createProfile(name, copyFromId: copyOf?.id));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref, SyncProfile profile) async {
    final name = await _askName(context, title: context.localized.syncRename, initial: profile.name);
    if (name == null || name.isEmpty || !context.mounted) return;
    _showError(context, await ref.read(settingsSyncProvider.notifier).rename(profile.id, name));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, SyncProfile profile) async {
    final sure = await showTvDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.syncDelete),
        content: Text(context.localized.syncDeleteConfirm(profile.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.localized.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(context.localized.syncDelete)),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    _showError(context, await ref.read(settingsSyncProvider.notifier).delete(profile.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(settingsSyncProvider);
    final notifier = ref.read(settingsSyncProvider.notifier);
    final profiles = sync.record?.profiles ?? const <SyncProfile>[];
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.profile_2user),
      title: Text(context.localized.syncProfiles),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  context.localized.syncProfilesDesc,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              for (final (index, profile) in profiles.indexed)
                _ProfileRow(
                  profile: profile,
                  devices: sync.record?.devicesOn(profile.id).length ?? 0,
                  current: sync.setup.enabled && sync.setup.profileId == profile.id,
                  autofocus: index == 0,
                  onJoin: () async {
                    await notifier.follow(profile.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  onTakeOnce: () async => _showError(context, await notifier.takeOnce(profile.id)),
                  onCopy: () => _create(context, ref, copyOf: profile),
                  onRename: () => _rename(context, ref, profile),
                  onDelete: () => _delete(context, ref, profile),
                ),
              TrackActionRow(
                icon: IconsaxPlusLinear.add,
                title: context.localized.syncCreateProfile,
                subtitle: context.localized.syncCreateProfileDesc,
                onTap: () => _create(context, ref),
              ),
              if (sync.setup.enabled)
                TrackActionRow(
                  icon: IconsaxPlusLinear.logout,
                  title: context.localized.syncLeave,
                  subtitle: context.localized.syncLeaveDesc,
                  onTap: () {
                    notifier.stop();
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.close)),
      ],
    );
  }
}

/// One profile: the row joins it; its menu sits beside it.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.devices,
    required this.current,
    required this.onJoin,
    required this.onTakeOnce,
    required this.onCopy,
    required this.onRename,
    required this.onDelete,
    this.autofocus = false,
  });

  final SyncProfile profile;
  final int devices;
  final bool current;
  final bool autofocus;
  final VoidCallback onJoin;
  final VoidCallback onTakeOnce;
  final VoidCallback onCopy;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return TrackOptionRow(
      title: profile.name,
      subtitle: [
        if (current) context.localized.syncThisDevicesProfile,
        context.localized.syncDeviceCount(devices),
        context.localized.syncChangedBy(profile.updatedBy, syncWhen(context, profile.updatedAt)),
      ].join(' · '),
      selected: current,
      autofocus: autofocus,
      onTap: onJoin,
      menu: PopupMenuButton<String>(
        tooltip: context.localized.moreOptions,
        icon: const Icon(IconsaxPlusLinear.more),
        onSelected: (value) => switch (value) {
          'once' => onTakeOnce(),
          'copy' => onCopy(),
          'rename' => onRename(),
          _ => onDelete(),
        },
        itemBuilder: (context) => [
          if (!current) PopupMenuItem(value: 'once', child: Text(context.localized.syncTakeOnce)),
          PopupMenuItem(value: 'copy', child: Text(context.localized.syncCopyProfile)),
          PopupMenuItem(value: 'rename', child: Text(context.localized.syncRename)),
          PopupMenuItem(value: 'delete', child: Text(context.localized.syncDelete)),
        ],
      ),
    );
  }
}

/// Which parts of the profile this device takes, and whether it shares its
/// memories.
class SyncSectionsDialog extends ConsumerWidget {
  const SyncSectionsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(settingsSyncProvider.select((sync) => sync.setup));
    final notifier = ref.read(settingsSyncProvider.notifier);
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.setting_4),
      title: Text(context.localized.syncParts),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  context.localized.syncSectionsDesc,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              for (final section in syncedSettingSections)
                OptionRow(
                  title: settingsSectionLabel(context, section),
                  trailing: Switch(
                    value: setup.follows(section),
                    onChanged: (follow) => notifier.setKeepOwn(section, !follow),
                  ),
                  onTap: () => notifier.setKeepOwn(section, setup.follows(section)),
                ),
              const Divider(),
              OptionRow(
                title: context.localized.syncShareMemories,
                trailing: Switch(value: setup.shareMemories, onChanged: notifier.setShareMemories),
                onTap: () => notifier.setShareMemories(!setup.shareMemories),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  context.localized.syncShareMemoriesDesc,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.close)),
      ],
    );
  }
}

/// The profile's recent changes: who changed what, each one to undo.
class SyncChangesDialog extends ConsumerWidget {
  const SyncChangesDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(settingsSyncProvider);
    final profile = sync.profile;
    final changes = profile == null ? const <ProfileChange>[] : sync.record?.changesOf(profile.id) ?? const [];
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.clock),
      title: Text(context.localized.syncRecentChanges),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 500,
        child: changes.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text(context.localized.syncRecentChangesNone))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final change in changes)
                      TrackActionRow(
                        icon: IconsaxPlusLinear.edit_2,
                        title: context.localized.syncChangeTitle(change.by, _parts(context, change.before.keys)),
                        subtitle: syncWhen(context, change.at),
                        onTap: () => showTvDialog(context: context, builder: (_) => _UndoDialog(change: change)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.close)),
      ],
    );
  }
}

/// One change: undo a part of it, or all of it.
class _UndoDialog extends ConsumerWidget {
  const _UndoDialog({required this.change});

  final ProfileChange change;

  Future<void> _undo(BuildContext context, WidgetRef ref, {Set<SettingsSection>? parts}) async {
    final error = await ref.read(settingsSyncProvider.notifier).undo(change, parts: parts);
    if (!context.mounted) return;
    FladderSnack.show(syncErrorText(context, error) ?? context.localized.syncUndone, context: context);
    if (error == null) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parts = change.before.keys.toList();
    return AlertDialog(
      title: Text(context.localized.syncChangeTitle(change.by, _parts(context, parts))),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (parts.length > 1)
              for (final part in parts)
                TrackActionRow(
                  icon: IconsaxPlusLinear.undo,
                  title: context.localized.syncUndoPart(settingsSectionLabel(context, part)),
                  onTap: () => _undo(context, ref, parts: {part}),
                ),
            TrackActionRow(
              icon: IconsaxPlusLinear.undo,
              title: parts.length > 1
                  ? context.localized.syncUndoAll
                  : context.localized.syncUndoPart(settingsSectionLabel(context, parts.single)),
              subtitle: syncWhen(context, change.at),
              onTap: () => _undo(context, ref),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
      ],
    );
  }
}

/// The devices on the profile; this one to rename, the others to forget.
class SyncDevicesDialog extends ConsumerWidget {
  const SyncDevicesDialog({super.key});

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(settingsSyncProvider.notifier);
    final name = await showTvDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: context.localized.syncRenameDevice,
        hint: context.localized.syncDeviceNameDesc,
        initial: notifier.deviceName,
      ),
    );
    if (name == null || name.isEmpty) return;
    notifier.setDeviceName(name);
    await notifier.syncNow();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(settingsSyncProvider);
    final notifier = ref.read(settingsSyncProvider.notifier);
    final profile = sync.profile;
    final devices = profile == null ? const <SyncDevice>[] : sync.record?.devicesOn(profile.id) ?? const [];
    final thisId = sync.setup.deviceId;
    // This device first, even before its first sync put it on the list.
    final mine = devices.firstWhereOrNull((device) => device.id == thisId);
    final others = devices.where((device) => device.id != thisId).toList();
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.devices),
      title: Text(context.localized.syncDevices),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TrackOptionRow(
                title: notifier.deviceName,
                subtitle: '${context.localized.syncThisDevice} · '
                    '${deviceKindLabel(context, mine?.kind ?? notifier.deviceKind)} · '
                    '${context.localized.syncRenameDevice}',
                selected: true,
                autofocus: true,
                onTap: () => _rename(context, ref),
              ),
              for (final device in others)
                TrackOptionRow(
                  title: device.name,
                  subtitle: context.localized
                      .syncDeviceSeen(deviceKindLabel(context, device.kind), syncWhen(context, device.lastSeen)),
                  selected: false,
                  onTap: () {},
                  menu: PopupMenuButton<String>(
                    tooltip: context.localized.moreOptions,
                    icon: const Icon(IconsaxPlusLinear.more),
                    onSelected: (_) async => _showError(context, await notifier.forgetDevice(device.id)),
                    itemBuilder: (context) => [
                      PopupMenuItem(value: 'forget', child: Text(context.localized.syncForgetDevice)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.close)),
      ],
    );
  }
}

/// Asked once on a device not yet on a profile, when the account has
/// profiles: join one, or start one of its own.
class SyncSetupDialog extends ConsumerStatefulWidget {
  const SyncSetupDialog({required this.record, super.key});

  final SyncRecord record;

  @override
  ConsumerState<SyncSetupDialog> createState() => _SyncSetupDialogState();
}

class _SyncSetupDialogState extends ConsumerState<SyncSetupDialog> {
  /// The id of "a new profile from this device" among the choices.
  static const _newProfile = '';

  late final DeviceKind _kind = ref.read(settingsSyncProvider.notifier).deviceKind;

  /// The profile for this kind of device first, then the latest changed.
  late final List<SyncProfile> _profiles = widget.record.profiles.sorted((a, b) {
    final kind = (b.kind == _kind ? 1 : 0) - (a.kind == _kind ? 1 : 0);
    return kind != 0 ? kind : b.updatedAt.compareTo(a.updatedAt);
  });

  /// No profile for this kind of device yet: a new one is the suggestion,
  /// rather than taking a phone's layout to a television.
  late String _chosen = _profiles.first.kind == _kind ? _profiles.first.id : _newProfile;
  late final Set<SettingsSection> _keepOwn = _defaultKeepOwn(_profiles.first);
  bool _customise = false;

  /// A profile from another kind of device: this one keeps its own look.
  Set<SettingsSection> _defaultKeepOwn(SyncProfile profile) =>
      profile.kind == _kind ? {} : {SettingsSection.app, SettingsSection.home};

  void _choose(String id) => setState(() {
        _chosen = id;
        _keepOwn.clear();
        final profile = widget.record.profile(id);
        if (profile != null) _keepOwn.addAll(_defaultKeepOwn(profile));
      });

  Future<void> _use() async {
    final notifier = ref.read(settingsSyncProvider.notifier);
    final name = deviceKindLabel(context, _kind);
    Navigator.of(context).pop();
    if (_chosen == _newProfile) {
      await notifier.startFirstProfile(name);
    } else {
      await notifier.follow(_chosen, keepOwn: _keepOwn);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(settingsSyncProvider.notifier);
    final existing = _chosen != _newProfile;
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.profile_2user),
      title: Text(context.localized.syncSetupTitle),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(context.localized.syncSetupBody, style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 8),
              for (final (index, profile) in _profiles.indexed)
                TrackOptionRow(
                  title: profile.name,
                  subtitle: [
                    if (profile.kind == _kind) context.localized.syncSuggested,
                    context.localized.syncChangedBy(profile.updatedBy, syncWhen(context, profile.updatedAt)),
                    _changes(context, notifier.differences(profile)),
                  ].join(' · '),
                  selected: profile.id == _chosen,
                  autofocus: index == 0,
                  onTap: () => _choose(profile.id),
                ),
              TrackOptionRow(
                title: context.localized.syncSetupNew(deviceKindLabel(context, _kind)),
                subtitle: [
                  if (_profiles.first.kind != _kind) context.localized.syncSuggested,
                  context.localized.syncSetupNewDesc,
                ].join(' · '),
                selected: _chosen == _newProfile,
                onTap: () => _choose(_newProfile),
              ),
              if (existing && !_customise)
                TrackActionRow(
                  icon: IconsaxPlusLinear.setting_4,
                  title: context.localized.syncSetupCustomise,
                  subtitle: _keepOwn.isEmpty ? null : context.localized.syncSetupKeepsOwn(_parts(context, _keepOwn)),
                  onTap: () => setState(() => _customise = true),
                )
              else if (existing) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    context.localized.syncSetupKeepOwnHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                for (final section in syncedSettingSections)
                  OptionRow(
                    title: settingsSectionLabel(context, section),
                    trailing: Checkbox(value: !_keepOwn.contains(section), onChanged: (_) => _toggle(section)),
                    onTap: () => _toggle(section),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.syncSetupLater)),
        FilledButton(onPressed: _use, child: Text(context.localized.syncSetupUse)),
      ],
    );
  }

  /// What joining a profile would change here, by part.
  String _changes(BuildContext context, List<SettingsSection> sections) => sections.isEmpty
      ? context.localized.syncSetupSame
      : context.localized.syncSetupChanges(_parts(context, sections));

  void _toggle(SettingsSection section) =>
      setState(() => _keepOwn.contains(section) ? _keepOwn.remove(section) : _keepOwn.add(section));
}

/// A name to type: a profile's, this device's.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.hint, required this.initial});

  final String title;
  final String hint;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: OutlinedTextField(
          controller: _controller,
          autoFocus: true,
          label: widget.hint,
          onSubmitted: (_) => _done(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
        FilledButton(onPressed: _done, child: Text(context.localized.done)),
      ],
    );
  }
}

/// Keeps a device on its profile: syncs when the app starts and comes back
/// to the front, sends a change a few seconds after it is made, asks every
/// ten minutes while the app is in front. A device not on a profile yet is
/// put on one: the account's first device starts one, a later one is asked
/// which to join.
class SettingsSyncHost extends ConsumerStatefulWidget {
  const SettingsSyncHost({required this.child, super.key});

  final Widget child;

  /// How often settings here are looked at for changes.
  static const checkEvery = Duration(seconds: 15);

  /// How often the account is asked while the app is in front.
  static const pullEvery = Duration(minutes: 10);

  @override
  ConsumerState<SettingsSyncHost> createState() => _SettingsSyncHostState();
}

class _SettingsSyncHostState extends ConsumerState<SettingsSyncHost> with WidgetsBindingObserver {
  Timer? _check;
  Timer? _pull;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check = Timer.periodic(SettingsSyncHost.checkEvery, (_) {
      if (mounted) ref.read(settingsSyncProvider.notifier).checkForChanges();
    });
    // A device left on - a television through an evening - still hears of
    // changes made elsewhere.
    _pull = Timer.periodic(SettingsSyncHost.pullEvery, (_) {
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ref.read(settingsSyncProvider.notifier).syncNow();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    final notifier = ref.read(settingsSyncProvider.notifier);
    final setup = ref.read(settingsSyncProvider).setup;
    if (setup.enabled) {
      await notifier.syncNow();
      return;
    }
    if (setup.answeredSetup) return;
    final record = await notifier.fetchRecord();
    if (!mounted || record == null) return;
    if (record.profiles.isNotEmpty) {
      await showTvDialog(context: context, builder: (_) => SyncSetupDialog(record: record));
      return;
    }
    // The first device on the account. Settings saved to the account the
    // older way are offered as its start.
    final backup = await ref.read(jellyApiProvider).getSettingsBackup().catchError((_) => null);
    final bundle = backup == null ? null : SettingsBundle.decode(backup.bundle);
    if (!mounted) return;
    if (bundle != null) await confirmAndApplySettings(context, ref, bundle);
    if (!mounted) return;
    final name = deviceKindLabel(context, notifier.deviceKind);
    final error = await notifier.startFirstProfile(name);
    if (!mounted) return;
    if (error == null) FladderSnack.show(context.localized.syncFirstProfile(name), context: context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(settingsSyncProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        notifier.checkForChanges();
        notifier.syncNow();
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        notifier.checkForChanges();
        if (notifier.hasPendingChanges) notifier.syncNow();
      default:
    }
  }

  @override
  void dispose() {
    _check?.cancel();
    _pull?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.read(settingsSyncProvider.notifier).screenKind =
        MediaQuery.sizeOf(context).shortestSide >= 600 ? DeviceKind.tablet : DeviceKind.phone;
    // Back online: what waited goes out, and what changed elsewhere comes in.
    ref.listen(offlineStateProvider, (previous, offline) {
      if (previous == true && !offline) ref.read(settingsSyncProvider.notifier).syncNow();
    });
    // A word when settings change underneath: the subtitles grew because
    // they were changed on the phone, not by themselves.
    ref.listen(settingsSyncProvider.select((sync) => sync.taken), (previous, taken) {
      if (taken == null || identical(previous, taken)) return;
      final parts = _parts(context, taken.sections);
      FladderSnack.show(
        taken.by.isEmpty ? context.localized.syncTakenNoDevice(parts) : context.localized.syncTaken(taken.by, parts),
        context: context,
      );
    });
    return widget.child;
  }
}

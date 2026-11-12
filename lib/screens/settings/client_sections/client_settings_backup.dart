import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/providers/watched_languages_provider.dart';
import 'package:chudder/providers/settings/language_preferences_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/application_info.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/settings_transfer.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

SettingsBundle _collect(WidgetRef ref) => SettingsBundle.collect(
      ref.read(sharedPreferencesProvider),
      device: ref.read(applicationInfoProvider).versionAndPlatform,
    );

String _stamp(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';

Future<void> exportSettingsToFile(BuildContext context, WidgetRef ref) async {
  final bundle = _collect(ref);
  try {
    final path = await FilePicker.saveFile(
      dialogTitle: context.localized.settingsExportFile,
      fileName: 'chudder-settings-${_stamp(bundle.exportedAt)}.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(bundle.encode())),
    );
    if (path == null || !context.mounted) return;
    FladderSnack.show(context.localized.settingsExported, context: context);
  } catch (error) {
    if (!context.mounted) return;
    FladderSnack.show('${context.localized.somethingWentWrong}: $error', context: context);
  }
}

Future<void> importSettingsFromFile(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFile(
    dialogTitle: context.localized.settingsImportFile,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  final bytes = await picked?.readAsBytes();
  if (bytes == null || !context.mounted) return;
  final bundle = SettingsBundle.decode(utf8.decode(bytes, allowMalformed: true));
  if (bundle == null) {
    FladderSnack.show(context.localized.settingsImportInvalid, context: context);
    return;
  }
  await confirmAndApplySettings(context, ref, bundle);
}

/// Shows what came in and lets the person choose which parts to take; then
/// stores those and reads them into the running app.
Future<void> confirmAndApplySettings(BuildContext context, WidgetRef ref, SettingsBundle bundle) async {
  final chosen = await showTvDialog<Set<SettingsSection>>(
    context: context,
    builder: (context) => ImportSettingsDialog(bundle: bundle),
  );
  if (chosen == null || chosen.isEmpty) return;
  await bundle.writeTo(ref.read(sharedPreferencesProvider), chosen);
  await ref.read(sharedUtilityProvider).loadSettings();
  ref.read(languagePreferencesProvider.notifier).reload();
  ref.read(watchedLanguagesProvider).reload();
  if (!context.mounted) return;
  FladderSnack.show(context.localized.settingsImported, context: context);
}

String settingsSectionLabel(BuildContext context, SettingsSection section) => switch (section) {
      SettingsSection.app => context.localized.settingsSectionApp,
      SettingsSection.home => context.localized.settingsSectionHome,
      SettingsSection.player => context.localized.settingsSectionPlayer,
      SettingsSection.subtitles => context.localized.settingsSectionSubtitles,
      SettingsSection.languages => context.localized.languagePreferences,
      SettingsSection.syncPlay => context.localized.syncPlay,
      SettingsSection.books => context.localized.settingsSectionBooks,
      SettingsSection.photos => context.localized.settingsSectionPhotos,
      SettingsSection.collectionQueues => context.localized.settingsSectionCollectionQueues,
      SettingsSection.watchedLanguages => context.localized.settingsSectionWatchedLanguages,
    };

/// What came in, with a box per part to take over; pops the chosen parts.
class ImportSettingsDialog extends StatefulWidget {
  const ImportSettingsDialog({required this.bundle, super.key});
  final SettingsBundle bundle;

  @override
  State<ImportSettingsDialog> createState() => _ImportSettingsDialogState();
}

class _ImportSettingsDialogState extends State<ImportSettingsDialog> {
  late final Set<SettingsSection> _chosen = widget.bundle.sections.keys.toSet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bundle = widget.bundle;
    final available = SettingsSection.values.where(bundle.sections.containsKey).toList();
    return AlertDialog(
      icon: const Icon(IconsaxPlusLinear.document_download),
      title: Text(context.localized.settingsImportTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.localized.settingsImportFrom(_stamp(bundle.exportedAt), bundle.device),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              for (final section in available)
                CheckboxListTile(
                  value: _chosen.contains(section),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(settingsSectionLabel(context, section)),
                  onChanged: (value) => setState(() => value == true ? _chosen.add(section) : _chosen.remove(section)),
                ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  Icon(IconsaxPlusLinear.info_circle, size: 16, color: scheme.onSurfaceVariant),
                  Expanded(
                    child: Text(
                      context.localized.settingsImportKeeps,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
        FilledButton(
          onPressed: _chosen.isEmpty ? null : () => Navigator.of(context).pop(_chosen),
          child: Text(context.localized.settingsImportApply),
        ),
      ],
    );
  }
}

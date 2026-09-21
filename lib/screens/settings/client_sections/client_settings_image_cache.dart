import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/screens/settings/settings_list_tile.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/custom_cache_manager.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/option_dialogue.dart';

/// What the artwork caches occupy on disk right now.
final imageCacheUsageProvider = FutureProvider.autoDispose<int>((ref) => CustomCacheManager.diskUsage());

List<Widget> buildClientSettingsImageCache(BuildContext context, WidgetRef ref) {
  final settings = ref.watch(clientSettingsProvider);
  final notifier = ref.read(clientSettingsProvider.notifier);
  final usage = kIsWeb ? null : ref.watch(imageCacheUsageProvider).value;

  Widget option<T>(T type, bool selected, Function tap, String title, [String? subtitle]) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: selected,
        onChanged: (_) => tap(),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  Widget policyTile(ImageKind kind, String label) {
    final current = settings.imageCachePolicies[kind] ?? ImageCachePolicy.keep;
    return SettingsListTile(
      label: Text(label),
      subLabel: Text(current.label(context)),
      onTap: () => openMultiSelectOptions<ImageCachePolicy>(
        context,
        label: label,
        items: ImageCachePolicy.values,
        selected: [current],
        onChanged: (values) => notifier.setImageCachePolicy(kind, values.first),
        itemBuilder: (type, selected, tap) => option(type, selected, tap, type.label(context)),
      ),
    );
  }

  return settingsListGroup(context, SettingsLabelDivider(label: context.localized.imageCacheSize), [
    SettingsListTile(
      label: Text(context.localized.imageCacheSize),
      subLabel: Text(settings.imageCacheSize.description(context)),
      onTap: () => openMultiSelectOptions<ImageCacheSize>(
        context,
        label: context.localized.imageCacheSize,
        items: ImageCacheSize.values,
        selected: [settings.imageCacheSize],
        onChanged: (values) => notifier.setImageCacheSize(values.first),
        itemBuilder: (type, selected, tap) =>
            option(type, selected, tap, type.label(context), type.description(context)),
      ),
    ),
    SettingsListTile(
      label: Text(context.localized.imageKeepTime),
      subLabel: Text('${settings.imageKeepTime.label(context)} · ${context.localized.imageKeepTimeDesc}'),
      onTap: () => openMultiSelectOptions<ImageKeepTime>(
        context,
        label: context.localized.imageKeepTime,
        items: ImageKeepTime.values,
        selected: [settings.imageKeepTime],
        onChanged: (values) => notifier.setImageKeepTime(values.first),
        itemBuilder: (type, selected, tap) => option(type, selected, tap, type.label(context)),
      ),
    ),
    policyTile(ImageKind.discover, context.localized.imageCacheDiscover),
    policyTile(ImageKind.photos, context.localized.imageCachePhotos),
    policyTile(ImageKind.chapters, context.localized.imageCacheChapters),
    if (!kIsWeb)
      SettingsListTile(
        label: Text(context.localized.imageCacheClear),
        subLabel: Text([
          if (usage != null) context.localized.imageCacheInUse(formatBytes(usage)),
          context.localized.imageCacheClearDesc,
        ].join(' · ')),
        onTap: () async {
          await CustomCacheManager.clear();
          ref.invalidate(imageCacheUsageProvider);
          if (context.mounted) FladderSnack.show(context.localized.imageCacheCleared, context: context);
        },
      ),
  ]);
}

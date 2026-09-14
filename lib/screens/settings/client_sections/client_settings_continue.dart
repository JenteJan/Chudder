import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/home_settings_model.dart';
import 'package:chudder/providers/settings/home_settings_provider.dart';
import 'package:chudder/screens/settings/settings_list_tile.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';
import 'package:chudder/util/localization_helper.dart';

/// How Continue watching and Next up are shown, wherever they are: the home
/// page, its banner and every library - and whether wide cards play.
List<Widget> buildClientSettingsContinue(BuildContext context, WidgetRef ref) {
  final combined = ref.watch(homeSettingsProvider.select((value) => value.nextUp == HomeNextUp.combined));
  final wide = ref.watch(homeSettingsProvider.select((value) => value.continueArt == HomeContinueArt.screenshots));
  final previews = ref.watch(homeSettingsProvider.select((value) => value.cardPreviews));
  final notifier = ref.read(homeSettingsProvider.notifier);

  void setCombined(bool value) =>
      notifier.update((current) => current.copyWith(nextUp: value ? HomeNextUp.combined : HomeNextUp.separate));
  void setWide(bool value) => notifier.update(
      (current) => current.copyWith(continueArt: value ? HomeContinueArt.screenshots : HomeContinueArt.posters));

  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.dashboardContinueWatching),
    [
      SettingsListTile(
        label: Text(context.localized.settingsCombineContinueTitle),
        subLabel: Text(context.localized.settingsCombineContinueDesc),
        onTap: () => setCombined(!combined),
        trailing: Switch(value: combined, onChanged: setCombined),
      ),
      SettingsListTile(
        label: Text(context.localized.settingsWideContinueTitle),
        subLabel: Text(context.localized.settingsWideContinueDesc),
        onTap: () => setWide(!wide),
        trailing: Switch(value: wide, onChanged: setWide),
      ),
      SettingsListTile(
        label: Text(context.localized.settingsCardPreviewsTitle),
        subLabel: Text(context.localized.settingsCardPreviewsDesc),
        onTap: () => notifier.update((current) => current.copyWith(cardPreviews: !previews)),
        trailing: Switch(
          value: previews,
          onChanged: (value) => notifier.update((current) => current.copyWith(cardPreviews: value)),
        ),
      ),
    ],
  );
}

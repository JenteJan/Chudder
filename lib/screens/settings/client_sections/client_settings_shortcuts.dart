import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/client_settings_model.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/screens/settings/widgets/key_listener.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';
import 'package:chudder/util/localization_helper.dart';

List<Widget> buildClientSettingsShortCuts(
  BuildContext context,
  WidgetRef ref,
) {
  final clientSettings = ref.watch(clientSettingsProvider);
  return settingsListGroup(
    context,
    SettingsLabelDivider(label: context.localized.shortCuts),
    [
      // Closing the window and quitting are the browser's on the web: its
      // own Ctrl+W and Ctrl+Q come first, and this app cannot do either.
      ...GlobalHotKeys.values
          .where((entry) => !kIsWeb || (entry != GlobalHotKeys.closeWindow && entry != GlobalHotKeys.exit))
          .map(
        (entry) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  entry.label(context),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: KeyCombinationWidget(
                  currentKey: clientSettings.shortcuts[entry],
                  defaultKey: clientSettings.defaultShortCuts[entry]!,
                  onChanged: (value) => ref.read(clientSettingsProvider.notifier).setShortcuts(MapEntry(entry, value)),
                ),
              )
            ],
          ),
        ),
      )
    ],
  );
}

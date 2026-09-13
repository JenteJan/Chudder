import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/control_panel/control_libraries_provider.dart';
import 'package:chudder/screens/control_panel/control_library_edit/control_library_location.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';

class LocationEditorSection extends ConsumerWidget {
  final VirtualFolderInfo selectedFolder;

  const LocationEditorSection({
    required this.selectedFolder,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.read(controlLibrariesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...settingsListGroup(
          context,
          SettingsLabelDivider(label: selectedFolder.name ?? ""),
          [
            ControlLibraryLocationEditor(
              library: selectedFolder,
              onAdd: (folder) {
                var updatedFolder = selectedFolder.copyWith(
                  locations: [...?selectedFolder.locations, folder],
                );
                provider.updateLibraryLocations(
                  updatedFolder.itemId,
                  updatedFolder.locations ?? [],
                );
              },
              onRemove: (folder) {
                var updatedFolder = selectedFolder.copyWith(
                  locations: selectedFolder.locations?.where((element) => element != folder).toList(),
                );
                provider.updateLibraryLocations(
                  updatedFolder.itemId,
                  updatedFolder.locations ?? [],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

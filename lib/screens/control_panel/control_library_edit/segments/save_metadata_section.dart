import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/control_panel/control_libraries_provider.dart';
import 'package:chudder/screens/settings/widgets/settings_label_divider.dart';
import 'package:chudder/screens/settings/widgets/settings_list_group.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/sortable_item_list.dart';

class SaveMetadataSection extends ConsumerWidget {
  final LibraryOptions? currentOptions;

  const SaveMetadataSection({
    required this.currentOptions,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.read(controlLibrariesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsListChild(
          isFirst: true,
          isLast: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsLabelDivider(label: context.localized.saveMetadata),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SortableItemList<String>(
                  items: currentOptions?.localMetadataReaderOrder ?? [],
                  included: currentOptions?.metadataSavers,
                  itemBuilder: (item) => Text(item),
                  onIncludeChange: (items) {
                    provider.updateSelectedLibraryOptions(
                      currentOptions?.copyWith(
                        metadataSavers: items,
                      ),
                    );
                  },
                  onReorder: (items) {},
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

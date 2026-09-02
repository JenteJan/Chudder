import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/providers/edit_item_provider.dart';
import 'package:fladder/screens/metadata/edit_screens/edit_fields.dart';
import 'package:fladder/screens/metadata/edit_screens/edit_image_content.dart';
import 'package:fladder/screens/shared/adaptive_dialog.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';

enum MetaEditOptions {
  general,
  primary,
  logo,
  backdrops,
  advanced;

  const MetaEditOptions();

  String label(BuildContext context) => switch (this) {
        MetaEditOptions.general => context.localized.general,
        MetaEditOptions.primary => context.localized.primary,
        MetaEditOptions.logo => context.localized.logo(1),
        MetaEditOptions.backdrops => context.localized.backdrop(1),
        MetaEditOptions.advanced => context.localized.advanced
      };
}

/// [targets] are the other items the dialog may be switched to - a show's
/// seasons and episodes - so artwork for one of them can be set from the
/// show's own editor instead of whichever episode the page had selected.
Future<ItemBaseModel?> showEditItemPopup(
  BuildContext context,
  String itemId, {
  Set<MetaEditOptions> options = const {
    MetaEditOptions.general,
    MetaEditOptions.primary,
    MetaEditOptions.logo,
    MetaEditOptions.backdrops,
    MetaEditOptions.advanced,
  },
  List<ItemBaseModel> targets = const [],
}) async {
  ItemBaseModel? updatedItem;
  var shouldRefresh = false;
  await showDialogAdaptive(
    context: context,
    builder: (context) {
      return EditDialogSwitcher(
        id: itemId,
        itemUpdated: (newItem) => updatedItem = newItem,
        refreshOnClose: (refresh) => shouldRefresh = refresh,
        options: options,
        targets: targets,
      );
    },
  );
  if (shouldRefresh == true) {
    context.refreshData();
  }
  return updatedItem;
}

class EditDialogSwitcher extends ConsumerStatefulWidget {
  final String id;
  final Function(ItemBaseModel? newItem) itemUpdated;
  final Function(bool refresh) refreshOnClose;
  final Set<MetaEditOptions> options;
  final List<ItemBaseModel> targets;

  const EditDialogSwitcher({
    required this.id,
    required this.itemUpdated,
    required this.refreshOnClose,
    required this.options,
    this.targets = const [],
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EditDialogSwitcherState();
}

class _EditDialogSwitcherState extends ConsumerState<EditDialogSwitcher> with TickerProviderStateMixin {
  /// What the editor is on right now; starts at the item it was opened for
  /// and moves with the target picker.
  late String currentId = widget.id;

  Future<void> refreshEditor() async {
    return ref.read(editItemProvider.notifier).fetchInformation(currentId);
  }

  String _targetLabel(ItemBaseModel target) => switch (target) {
        SeriesModel _ => context.localized.entireShow,
        SeasonModel season => season.name,
        EpisodeModel episode => episode.detailedName(context.localized) ?? episode.name,
        _ => target.detailedName(context.localized) ?? target.name,
      };

  int selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => refreshEditor());
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = ref.watch(editItemProvider.select((value) => value.item));
    final saving = ref.watch(editItemProvider.select((value) => value.saving));
    final state = ref.watch(editItemProvider).editedJson;
    final generalFields = ref.watch(editItemProvider.notifier).getFields ?? {};
    final advancedFields = ref.watch(editItemProvider.notifier).advancedFields ?? {};

    Map<MetaEditOptions, Widget> widgets = Map.fromEntries(
      {
        MetaEditOptions.general: EditFields(fields: generalFields, json: state),
        // Keyed per type: the switcher below otherwise reuses one tab's state
        // for the next, and the new type is never fetched.
        MetaEditOptions.primary: const EditImageContent(key: ValueKey(ImageType.primary), type: ImageType.primary),
        MetaEditOptions.logo: const EditImageContent(key: ValueKey(ImageType.logo), type: ImageType.logo),
        MetaEditOptions.backdrops: const EditImageContent(key: ValueKey(ImageType.backdrop), type: ImageType.backdrop),
        MetaEditOptions.advanced: EditFields(fields: advancedFields, json: state),
      }.entries.where((entry) => widget.options.contains(entry.key)),
    );

    return Column(
      spacing: 8,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 16),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Text(
                  currentItem?.detailedName(context.localized) ?? currentItem?.name ?? "",
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                  autofocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
                  onPressed: () => refreshEditor(),
                  icon: const Icon(
                    IconsaxPlusLinear.refresh,
                  ))
            ],
          ),
        ),
        if (widget.targets.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 360,
              label: Text(context.localized.editing),
              initialSelection: currentId,
              dropdownMenuEntries: widget.targets
                  .map((target) => DropdownMenuEntry<String>(value: target.id, label: _targetLabel(target)))
                  .toList(),
              onSelected: (id) {
                if (id == null || id == currentId) return;
                setState(() => currentId = id);
                refreshEditor();
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SegmentedButton(
            segments: widgets.keys
                .map(
                  (value) => ButtonSegment(
                    value: value,
                    label: Text(value.label(context)),
                  ),
                )
                .toList(),
            selected: {widgets.keys.elementAt(selectedTabIndex)},
            showSelectedIcon: false,
            onSelectionChanged: (newSelection) {
              setState(() {
                selectedTabIndex = widgets.keys.toList().indexOf(newSelection.first);
              });
            },
          ),
        ),
        Flexible(
          child: AnimatedFadeSize(
            child: widgets.values.elementAt(selectedTabIndex),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.close)),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final response = await FladderSnack.showResponse(
                          ref.read(editItemProvider.notifier).saveInformation(widgets.keys.toSet()),
                          successTitle: context.localized.metaDataSavedFor(
                            currentItem?.detailedName(context.localized) ?? currentItem?.name ?? "",
                          ),
                        );
                        if (response.isSuccess) {
                          widget.itemUpdated(response.data);
                          widget.refreshOnClose(true);
                        }
                        Navigator.of(context).pop();
                      },
                child: saving
                    ? SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                            backgroundColor: Theme.of(context).colorScheme.onPrimary, strokeCap: StrokeCap.round),
                      )
                    : Text(context.localized.save),
              ),
            ],
          ),
        )
      ],
    );
  }
}

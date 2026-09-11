import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/library_search/library_search_model.dart';
import 'package:fladder/models/library_search/library_search_options.dart';
import 'package:fladder/providers/library_search_provider.dart';
import 'package:fladder/screens/library_search/widgets/library_sort_dialogue.dart';
import 'package:fladder/screens/seerr/widgets/seerr_filter_dialogs.dart';
import 'package:fladder/screens/shared/chips/category_chip.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/anchored_popover.dart';
import 'package:fladder/widgets/shared/button_group.dart';

class LibraryFilterChips extends ConsumerStatefulWidget {
  const LibraryFilterChips({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _LibraryFilterChipsState();
}

class _LibraryFilterChipsState extends ConsumerState<LibraryFilterChips> {
  @override
  Widget build(BuildContext context) {
    final uniqueKey = widget.key ?? UniqueKey();
    final libraryProvider = ref.watch(librarySearchProvider(uniqueKey).notifier);
    final groupBy = ref.watch(librarySearchProvider(uniqueKey).select((v) => v.filters.groupBy));
    final favourites = ref.watch(librarySearchProvider(uniqueKey).select((v) => v.filters.favourites));
    final recursive = ref.watch(librarySearchProvider(uniqueKey).select((v) => v.filters.recursive));
    final hideEmpty = ref.watch(librarySearchProvider(uniqueKey).select((v) => v.filters.hideEmptyShows));
    final librarySearchResults = ref.watch(librarySearchProvider(uniqueKey));
    final usePopover = AdaptiveLayout.inputDeviceOf(context) != InputDevice.touch;

    final chips = [
      if (librarySearchResults.folderOverwrite.isEmpty)
        CategoryChip(
          label: Text(context.localized.library(2)),
          items: librarySearchResults.views.sortByKey((value) => value.name),
          labelBuilder: (item) => Text(item.name),
          onSave: (value) => libraryProvider.setViews(value),
          onCancel: () => libraryProvider.setViews(librarySearchResults.views),
          onClear: () => libraryProvider.setViews(librarySearchResults.views.setAll(false)),
        )
      else if (librarySearchResults.folderOverwrite.length > 1)
        CategoryChip(
          label: Text(context.localized.mediaTypeFolder(2)),
          items: librarySearchResults.folderOverwrite.sortByKey((value) => value.name),
          labelBuilder: (item) => Text(item.name),
          onSave: (value) => libraryProvider.setFolderOverwrite(value),
          onCancel: () => libraryProvider.setFolderOverwrite(librarySearchResults.folderOverwrite),
          onClear: () => libraryProvider.setFolderOverwrite(librarySearchResults.folderOverwrite.setAll(false)),
        ),
      CategoryChip<FladderItemType>(
        label: Text(context.localized.type(librarySearchResults.filters.types.length)),
        items: librarySearchResults.filters.types.sortByKey((value) => value.label(context.localized)),
        activeIcon: IconsaxPlusBold.filter_tick,
        labelBuilder: (item) => Row(
          children: [
            Icon(item.icon),
            const SizedBox(width: 12),
            Text(item.label(context.localized)),
          ],
        ),
        onSave: (value) => libraryProvider.setTypes(value),
        onClear: () => libraryProvider.setTypes(librarySearchResults.filters.types.setAll(false)),
      ),
      // The watched/unwatched/resumable filter is one of the most used and
      // was buried at the end of the row under the puzzling name "Filters".
      CategoryChip<ItemFilter>(
        label: Text(context.localized.watchedState),
        activeIcon: IconsaxPlusBold.eye,
        items: librarySearchResults.filters.itemFilters,
        labelBuilder: (item) => Text(item.label(context)),
        onSave: (value) => libraryProvider.setFilters(value),
        onClear: () => libraryProvider.setFilters(librarySearchResults.filters.itemFilters.setAll(false)),
      ),
      // Provider changes already trigger the screen's refresh listener;
      // the extra context.refreshData() these chips used to call queued a
      // second full refetch per tap.
      ExpressiveButton(
        isSelected: favourites != null,
        icon: switch (favourites) {
          true => const Icon(IconsaxPlusBold.heart),
          false => const Icon(IconsaxPlusBold.heart_slash),
          null => null,
        },
        label: Text(context.localized.favorites),
        onLongPress: () => libraryProvider.setFavourites(null),
        onPressed: () {
          final newValue = switch (favourites) {
            true => false,
            false => null,
            null => true,
          };
          libraryProvider.setFavourites(newValue);
        },
      ),
      // Sort lived only in the bottom bar, which hides itself on scroll.
      _SortChip(
        usePopover: usePopover,
        libraryProvider: libraryProvider,
        librarySearchResults: librarySearchResults,
        uniqueKey: uniqueKey,
      ),
      if (librarySearchResults.filters.genres.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.genre(librarySearchResults.filters.genres.length)),
          activeIcon: IconsaxPlusBold.hierarchy_2,
          items: librarySearchResults.filters.genres,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setGenres(value),
          onCancel: () => libraryProvider.setGenres(librarySearchResults.filters.genres),
          onClear: () => libraryProvider.setGenres(librarySearchResults.filters.genres.setAll(false)),
        ),
      if (librarySearchResults.filters.years.isNotEmpty)
        _YearChip(
          usePopover: usePopover,
          libraryProvider: libraryProvider,
          librarySearchResults: librarySearchResults,
        ),
      if (librarySearchResults.filters.studios.isNotEmpty)
        CategoryChip<Studio>(
          label: Text(context.localized.studio(librarySearchResults.filters.studios.length)),
          activeIcon: IconsaxPlusBold.airdrop,
          items: librarySearchResults.filters.studios,
          labelBuilder: (item) => Text(item.name),
          searchLabel: (item) => item.name,
          onSave: (value) => libraryProvider.setStudios(value),
          onCancel: () => libraryProvider.setStudios(librarySearchResults.filters.studios),
          onClear: () => libraryProvider.setStudios(librarySearchResults.filters.studios.setAll(false)),
        ),
      if (librarySearchResults.filters.tags.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.label(librarySearchResults.filters.tags.length)),
          activeIcon: Icons.label_rounded,
          items: librarySearchResults.filters.tags,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setTags(value),
          onCancel: () => libraryProvider.setTags(librarySearchResults.filters.tags),
          onClear: () => libraryProvider.setTags(librarySearchResults.filters.tags.setAll(false)),
        ),
      _GroupChip(
        usePopover: usePopover,
        groupBy: groupBy,
        onChanged: libraryProvider.setGroupBy,
      ),
      if (librarySearchResults.filters.types[FladderItemType.series] == true)
        ExpressiveButton(
          isSelected: !hideEmpty,
          icon: !hideEmpty ? const Icon(IconsaxPlusBold.ghost) : null,
          label: Text(!hideEmpty ? context.localized.hideEmpty : context.localized.showEmpty),
          onPressed: libraryProvider.toggleEmptyShows,
        ),
      if (librarySearchResults.filters.officialRatings.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.rating(librarySearchResults.filters.officialRatings.length)),
          activeIcon: Icons.star_rate_rounded,
          items: librarySearchResults.filters.officialRatings,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setRatings(value),
          onCancel: () => libraryProvider.setRatings(librarySearchResults.filters.officialRatings),
          onClear: () => libraryProvider.setRatings(librarySearchResults.filters.officialRatings.setAll(false)),
        ),
      // Formerly "Recursive": whether items inside nested folders are shown
      // flattened. Rarely touched (the defaults already enable it for the
      // common library types), so it sits at the end under a name that says
      // what it does.
      ExpressiveButton(
        isSelected: recursive == true,
        icon: recursive == true ? const Icon(IconsaxPlusBold.tick_circle) : null,
        label: Text(context.localized.includeSubfolders),
        onPressed: () => libraryProvider.toggleRecursive(),
      ),
    ];

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Row(
        spacing: 4,
        children: chips.mapIndexed(
          (index, element) {
            final position = index == 0
                ? PositionContext.first
                : (index == chips.length - 1 ? PositionContext.last : PositionContext.middle);
            return PositionProvider(position: position, child: element);
          },
        ).toList(),
      ),
    );
  }
}

/// A chip with a drop-down arrow, the shape every chip that opens something
/// shares.
Widget _dropChip(
  BuildContext context, {
  required bool selected,
  required Widget label,
  Widget? icon,
  required VoidCallback onPressed,
  bool open = false,
}) {
  return ExpressiveButton(
    isSelected: selected,
    icon: icon,
    label: Row(
      spacing: 6,
      children: [
        label,
        Icon(open ? IconsaxPlusLinear.arrow_up_2 : IconsaxPlusLinear.arrow_down, size: 16),
      ],
    ),
    onPressed: onPressed,
  );
}

/// One row of a popover list, with a tick where it is the current choice.
class _PopoverOption extends StatelessWidget {
  final bool selected;
  final Widget label;
  final VoidCallback onTap;

  const _PopoverOption({required this.selected, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: selected,
      selectedTileColor: colors.primaryContainer.withValues(alpha: 0.5),
      title: label,
      trailing: selected ? Icon(IconsaxPlusBold.tick_circle, size: 18, color: colors.primary) : null,
      onTap: onTap,
    );
  }
}

Widget _popoverTitle(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );

class _SortChip extends StatelessWidget {
  final bool usePopover;
  final LibrarySearchNotifier libraryProvider;
  final LibrarySearchModel librarySearchResults;
  final Key uniqueKey;

  const _SortChip({
    required this.usePopover,
    required this.libraryProvider,
    required this.librarySearchResults,
    required this.uniqueKey,
  });

  @override
  Widget build(BuildContext context) {
    final current = librarySearchResults.filters.sortingOption;
    final order = librarySearchResults.filters.sortOrder;
    final isDefault = current == SortingOptions.sortName && order == SortingOrder.ascending;
    final label = Text(isDefault ? context.localized.sortBy : current.label(context));
    final icon = Icon(order == SortingOrder.ascending ? IconsaxPlusLinear.sort : IconsaxPlusBold.sort);

    if (!usePopover) {
      return ExpressiveButton(
        isSelected: !isDefault,
        icon: icon,
        label: label,
        onPressed: () async {
          final newOptions = await openSortByDialogue(
            context,
            libraryProvider: libraryProvider,
            uniqueKey: uniqueKey,
            options: (current, order),
          );
          if (newOptions != null) {
            if (newOptions.$1 != null) libraryProvider.setSortBy(newOptions.$1!);
            if (newOptions.$2 != null) libraryProvider.setSortOrder(newOptions.$2!);
          }
        },
      );
    }

    return AnchoredPopover(
      width: 280,
      maxHeight: 520,
      anchorBuilder: (context, controller) => _dropChip(
        context,
        selected: !isDefault,
        icon: icon,
        label: label,
        open: controller.isOpen,
        onPressed: controller.toggle,
      ),
      popoverBuilder: (context, controller) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _popoverTitle(context, context.localized.sortBy),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<SortingOrder>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: SortingOrder.values
                  .map((e) => ButtonSegment(
                        value: e,
                        label: Text(e.label(context)),
                        icon: Icon(e == SortingOrder.ascending
                            ? IconsaxPlusLinear.arrow_up_3
                            : IconsaxPlusLinear.arrow_down_1),
                      ))
                  .toList(),
              selected: {order},
              onSelectionChanged: (value) => libraryProvider.setSortOrder(value.first),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: SortingOptions.values
                  .map(
                    (e) => _PopoverOption(
                      selected: current == e,
                      label: Text(e.label(context)),
                      onTap: () => libraryProvider.setSortBy(e),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final bool usePopover;
  final GroupBy groupBy;
  final ValueChanged<GroupBy> onChanged;

  const _GroupChip({required this.usePopover, required this.groupBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = groupBy != GroupBy.none;
    final label = Text(selected ? groupBy.value(context) : context.localized.group);
    final icon = selected ? const Icon(IconsaxPlusBold.bag_tick) : null;

    if (!usePopover) {
      return ExpressiveButton(
        isSelected: selected,
        icon: icon,
        label: label,
        onPressed: () => _openGroupDialogue(context),
      );
    }

    return AnchoredPopover(
      width: 240,
      anchorBuilder: (context, controller) => _dropChip(
        context,
        selected: selected,
        icon: icon,
        label: label,
        open: controller.isOpen,
        onPressed: controller.toggle,
      ),
      popoverBuilder: (context, controller) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _popoverTitle(context, context.localized.groupBy),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: GroupBy.values
                  .map(
                    (group) => _PopoverOption(
                      selected: groupBy == group,
                      label: Text(group.value(context)),
                      onTap: () {
                        if (group != groupBy) onChanged(group);
                        controller.close();
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _openGroupDialogue(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.65,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(context.localized.groupBy),
                ...GroupBy.values.map(
                  (group) => CheckboxListTile(
                    value: groupBy == group,
                    onChanged: (_) {
                      if (group != groupBy) onChanged(group);
                      Navigator.pop(context);
                    },
                    title: Text(group.value(context)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _YearChip extends StatelessWidget {
  final bool usePopover;
  final LibrarySearchNotifier libraryProvider;
  final LibrarySearchModel librarySearchResults;

  const _YearChip({required this.usePopover, required this.libraryProvider, required this.librarySearchResults});

  @override
  Widget build(BuildContext context) {
    final range = librarySearchResults.yearRange;
    final selected = range.$1 != null || range.$2 != null;
    final label = Text(yearLabel(context, range));
    const icon = Icon(IconsaxPlusBold.calendar_1);

    if (!usePopover) {
      return ExpressiveButton(
        isSelected: selected,
        icon: icon,
        label: label,
        onPressed: () => openYearDialog(
          context,
          (first, last) => libraryProvider.setYearsRange(first, last),
          range,
          fullYearRange: librarySearchResults.availableYearRange,
        ),
      );
    }

    return AnchoredPopover(
      width: 320,
      anchorBuilder: (context, controller) => _dropChip(
        context,
        selected: selected,
        icon: icon,
        label: label,
        open: controller.isOpen,
        onPressed: controller.toggle,
      ),
      popoverBuilder: (context, controller) => _YearRangePanel(
        range: range,
        fullRange: librarySearchResults.availableYearRange,
        onChanged: (first, last) => libraryProvider.setYearsRange(first, last),
      ),
    );
  }
}

/// A slider over the years the library spans. Applied when the thumb is let
/// go, not while it moves - every stop would otherwise be a fetch.
class _YearRangePanel extends StatefulWidget {
  final (int? min, int? max) range;
  final (int min, int max) fullRange;
  final void Function(int? first, int? last) onChanged;

  const _YearRangePanel({required this.range, required this.fullRange, required this.onChanged});

  @override
  State<_YearRangePanel> createState() => _YearRangePanelState();
}

class _YearRangePanelState extends State<_YearRangePanel> {
  late RangeValues _values = RangeValues(
    (widget.range.$1 ?? widget.fullRange.$1).toDouble(),
    (widget.range.$2 ?? widget.fullRange.$2).toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    final min = widget.fullRange.$1.toDouble();
    final max = widget.fullRange.$2.toDouble();
    final divisions = (max - min).round().clamp(1, 200);
    final hasSelection = widget.range.$1 != null || widget.range.$2 != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _popoverTitle(context, context.localized.year(1))),
            if (hasSelection)
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 6),
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => _values = RangeValues(min, max));
                    widget.onChanged(null, null);
                  },
                  icon: const Icon(IconsaxPlusLinear.close_circle, size: 16),
                  label: Text(context.localized.clear),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_values.start.round().toString(), style: Theme.of(context).textTheme.titleMedium),
              Text(_values.end.round().toString(), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        RangeSlider(
          values: RangeValues(_values.start.clamp(min, max), _values.end.clamp(min, max)),
          min: min,
          max: max,
          divisions: divisions,
          labels: RangeLabels(_values.start.round().toString(), _values.end.round().toString()),
          onChanged: (values) => setState(() => _values = values),
          onChangeEnd: (values) {
            final first = values.start.round();
            final last = values.end.round();
            final whole = first == widget.fullRange.$1 && last == widget.fullRange.$2;
            widget.onChanged(whole ? null : first, whole ? null : last);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

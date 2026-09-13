import 'dart:math' as math;

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
import 'package:fladder/screens/seerr/widgets/seerr_filter_dialogs.dart';
import 'package:fladder/screens/shared/chips/category_chip.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/navigation_scaffold/components/navigation_body.dart';
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

    final chips = [
      if (librarySearchResults.folderOverwrite.isEmpty)
        CategoryChip(
          label: Text(context.localized.library(2)),
          items: librarySearchResults.views.sortByKey((value) => value.name),
          labelBuilder: (item) => Text(item.name),
          onSave: (value) => libraryProvider.setViews(value),
          defaults: libraryProvider.defaultViews,
        )
      else if (librarySearchResults.folderOverwrite.length > 1)
        CategoryChip(
          label: Text(context.localized.mediaTypeFolder(2)),
          items: librarySearchResults.folderOverwrite.sortByKey((value) => value.name),
          labelBuilder: (item) => Text(item.name),
          onSave: (value) => libraryProvider.setFolderOverwrite(value),
          defaults: libraryProvider.defaultFolderOverwrite,
        ),
      // The row runs from what narrows a library most often to what is
      // rarely touched: genre first, the kind of item near the end - a film
      // library is films, and the type chip mostly says so.
      if (librarySearchResults.filters.genres.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.genre(librarySearchResults.filters.genres.length)),
          activeIcon: IconsaxPlusBold.hierarchy_2,
          items: librarySearchResults.filters.genres,
          searchable: true,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setGenres(value),
          onClear: () => libraryProvider.setGenres(librarySearchResults.filters.genres.setAll(false)),
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
        libraryProvider: libraryProvider,
        librarySearchResults: librarySearchResults,
      ),
      if (librarySearchResults.filters.years.isNotEmpty)
        _YearChip(
          libraryProvider: libraryProvider,
          librarySearchResults: librarySearchResults,
        ),
      if (librarySearchResults.filters.studios.isNotEmpty)
        CategoryChip<Studio>(
          label: Text(context.localized.studio(librarySearchResults.filters.studios.length)),
          activeIcon: IconsaxPlusBold.airdrop,
          items: librarySearchResults.filters.studios,
          labelBuilder: (item) => Text(item.name),
          searchable: true,
          searchLabel: (item) => item.name,
          onSave: (value) => libraryProvider.setStudios(value),
          onClear: () => libraryProvider.setStudios(librarySearchResults.filters.studios.setAll(false)),
        ),
      if (librarySearchResults.filters.tags.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.label(librarySearchResults.filters.tags.length)),
          activeIcon: Icons.label_rounded,
          items: librarySearchResults.filters.tags,
          searchable: true,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setTags(value),
          onClear: () => libraryProvider.setTags(librarySearchResults.filters.tags.setAll(false)),
        ),
      if (librarySearchResults.filters.officialRatings.isNotEmpty)
        CategoryChip<String>(
          label: Text(context.localized.rating(librarySearchResults.filters.officialRatings.length)),
          activeIcon: Icons.star_rate_rounded,
          items: librarySearchResults.filters.officialRatings,
          searchable: true,
          labelBuilder: (item) => Text(item),
          onSave: (value) => libraryProvider.setRatings(value),
          onClear: () => libraryProvider.setRatings(librarySearchResults.filters.officialRatings.setAll(false)),
        ),
      _GroupChip(
        groupBy: groupBy,
        onChanged: libraryProvider.setGroupBy,
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
        defaults: libraryProvider.defaultTypes,
      ),
      if (librarySearchResults.filters.types[FladderItemType.series] == true)
        ExpressiveButton(
          isSelected: !hideEmpty,
          icon: !hideEmpty ? const Icon(IconsaxPlusBold.ghost) : null,
          label: Text(!hideEmpty ? context.localized.hideEmpty : context.localized.showEmpty),
          onPressed: libraryProvider.toggleEmptyShows,
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

    // The page's own policy, not Flutter's reading-order search: that search
    // found nothing to the left of the first chip and stopped there, where
    // every other row on a page hands left off its first control to the side
    // bar; and up from a chip it weighed the search field's outer group node
    // as heavily as the field, and could land on the one nothing draws.
    return FocusTraversalGroup(
      policy: GlobalFallbackTraversalPolicy(),
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

class _SortChip extends StatelessWidget {
  final LibrarySearchNotifier libraryProvider;
  final LibrarySearchModel librarySearchResults;

  const _SortChip({
    required this.libraryProvider,
    required this.librarySearchResults,
  });

  @override
  Widget build(BuildContext context) {
    final current = librarySearchResults.filters.sortingOption;
    final order = librarySearchResults.filters.sortOrder;
    final isDefault = current == SortingOptions.sortName && order == SortingOrder.ascending;
    final label = Text(isDefault ? context.localized.sortBy : current.label(context));
    final icon = Icon(order == SortingOrder.ascending ? IconsaxPlusLinear.sort : IconsaxPlusBold.sort);

    return AnchoredPopover(
      width: 320,
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
          PopoverHeader(title: Text(context.localized.sortBy)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<SortingOrder>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: SortingOrder.values
                  .map((e) => ButtonSegment(
                        value: e,
                        // One line whatever the language: "Descending" wrapped
                        // under its arrow at this width.
                        label: Text(e.label(context), maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
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
          // Every row built, not just the ones in view: the current choice
          // is where a pad's selection starts, and a lazy list would not
          // have built one below the fold to start on.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: SortingOptions.values.map((e) {
                  final option = PopoverOption(
                    selected: current == e,
                    label: Text(e.label(context)),
                    onTap: () => libraryProvider.setSortBy(e),
                  );
                  return current == e ? PopoverInitialFocus(child: option) : option;
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final GroupBy groupBy;
  final ValueChanged<GroupBy> onChanged;

  const _GroupChip({required this.groupBy, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = groupBy != GroupBy.none;
    final label = Text(selected ? groupBy.value(context) : context.localized.group);
    final icon = selected ? const Icon(IconsaxPlusBold.bag_tick) : null;

    return AnchoredPopover(
      width: 260,
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
          PopoverHeader(title: Text(context.localized.groupBy)),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: GroupBy.values.map((group) {
                  final option = PopoverOption(
                    selected: groupBy == group,
                    label: Text(group.value(context)),
                    onTap: () {
                      if (group != groupBy) onChanged(group);
                      controller.close();
                    },
                  );
                  return groupBy == group ? PopoverInitialFocus(child: option) : option;
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearChip extends StatelessWidget {
  final LibrarySearchNotifier libraryProvider;
  final LibrarySearchModel librarySearchResults;

  const _YearChip({required this.libraryProvider, required this.librarySearchResults});

  @override
  Widget build(BuildContext context) {
    final range = librarySearchResults.yearRange;
    final selected = range.$1 != null || range.$2 != null;
    final label = Text(yearLabel(context, range));
    const icon = Icon(IconsaxPlusBold.calendar_1);

    // A remote cannot drag a slider's thumbs, so it gets buttons and decades;
    // a pointer or a finger keeps the slider, which is quicker for them.
    final onPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;

    return AnchoredPopover(
      width: onPad ? 300 : 320,
      maxHeight: 480,
      anchorBuilder: (context, controller) => _dropChip(
        context,
        selected: selected,
        icon: icon,
        label: label,
        open: controller.isOpen,
        onPressed: controller.toggle,
      ),
      popoverBuilder: (context, controller) => onPad
          ? _YearRangePanel(
              range: range,
              fullRange: librarySearchResults.availableYearRange,
              onChanged: (first, last) => libraryProvider.setYearsRange(first, last),
            )
          : _YearSliderPanel(
              range: range,
              fullRange: librarySearchResults.availableYearRange,
              onChanged: (first, last) => libraryProvider.setYearsRange(first, last),
            ),
    );
  }
}

/// A slider over the years the library spans, for a pointer or a finger.
/// Applied when the thumb is let go, not while it moves - every stop would
/// otherwise be a fetch.
class _YearSliderPanel extends StatefulWidget {
  final (int? min, int? max) range;
  final (int min, int max) fullRange;
  final void Function(int? first, int? last) onChanged;

  const _YearSliderPanel({required this.range, required this.fullRange, required this.onChanged});

  @override
  State<_YearSliderPanel> createState() => _YearSliderPanelState();
}

class _YearSliderPanelState extends State<_YearSliderPanel> {
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
        PopoverHeader(
          title: Text(context.localized.year(1)),
          onClear: !hasSelection
              ? null
              : () {
                  setState(() => _values = RangeValues(min, max));
                  widget.onChanged(null, null);
                },
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

/// The years to show on a remote: a first and a last year that step one at
/// a time, and the decades the library spans, which set or widen the range a
/// decade at a time. A remote could not move a slider's thumbs at all.
///
/// A decade ticks when the range covers it. Picking one with nothing chosen
/// shows just that decade; one next to the range, or further out, widens the
/// range to take it in; one at either end of the range drops it again; one in
/// the middle narrows the range to it.
class _YearRangePanel extends StatefulWidget {
  final (int? min, int? max) range;
  final (int min, int max) fullRange;
  final void Function(int? first, int? last) onChanged;

  const _YearRangePanel({required this.range, required this.fullRange, required this.onChanged});

  @override
  State<_YearRangePanel> createState() => _YearRangePanelState();
}

class _YearRangePanelState extends State<_YearRangePanel> {
  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 400));

  /// The chosen range, or null for every year.
  late (int, int)? _range = widget.range.$1 == null && widget.range.$2 == null
      ? null
      : (widget.range.$1 ?? widget.fullRange.$1, widget.range.$2 ?? widget.fullRange.$2);
  bool _pending = false;

  int get _min => widget.fullRange.$1;
  int get _max => widget.fullRange.$2;

  @override
  void dispose() {
    if (_pending) {
      final range = _range;
      final onChanged = widget.onChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(range?.$1, range?.$2));
    }
    super.dispose();
  }

  void _set((int, int)? range) {
    // The whole span is no filter at all.
    final whole = range != null && range.$1 <= _min && range.$2 >= _max;
    setState(() {
      _range = whole ? null : range;
      _pending = true;
    });
    _debouncer.run(() {
      if (!mounted || !_pending) return;
      _pending = false;
      widget.onChanged(_range?.$1, _range?.$2);
    });
  }

  void _step({required bool first, required int by}) {
    final (from, to) = _range ?? (_min, _max);
    if (first) {
      _set(((from + by).clamp(_min, to), to));
    } else {
      _set((from, (to + by).clamp(from, _max)));
    }
  }

  (int, int) _decadeSpan(int decade) => (math.max(decade, _min), math.min(decade + 9, _max));

  bool _covers(int decade) {
    final range = _range;
    if (range == null) return false;
    final (start, end) = _decadeSpan(decade);
    return start >= range.$1 && end <= range.$2;
  }

  void _tapDecade(int decade) {
    final range = _range;
    final (start, end) = _decadeSpan(decade);
    if (range == null) return _set((start, end));
    final (from, to) = range;
    if (!_covers(decade)) return _set((math.min(from, start), math.max(to, end)));
    if (from == start && to == end) return _set(null);
    if (from == start) return _set((end + 1, to));
    if (to == end) return _set((from, start - 1));
    _set((start, end));
  }

  @override
  Widget build(BuildContext context) {
    final (from, to) = _range ?? (_min, _max);
    final decades = [for (var d = (_max ~/ 10) * 10; d >= (_min ~/ 10) * 10; d -= 10) d];
    final firstCovered = decades.where(_covers).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopoverHeader(
          title: Text(context.localized.year(1)),
          onClear: _range == null ? null : () => _set(null),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _YearStepper(
                value: from,
                onStep: (by) => _step(first: true, by: by),
              ),
              Text('-', style: Theme.of(context).textTheme.titleMedium),
              _YearStepper(
                value: to,
                onStep: (by) => _step(first: false, by: by),
              ),
            ],
          ),
        ),
        const Divider(),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: decades.map((decade) {
              final (start, end) = _decadeSpan(decade);
              final option = PopoverOption(
                label: Text(start == end ? '$start' : '$start - $end'),
                selected: _covers(decade),
                multiSelect: true,
                onTap: () => _tapDecade(decade),
              );
              final initial = firstCovered == null ? decade == decades.first : decade == firstCovered;
              return initial ? PopoverInitialFocus(child: option) : option;
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// A year with a button either side to step it down and up. The buttons
/// stay enabled at the ends of the range - a pad's selection on a button that
/// disabled itself would have nowhere to be - and simply do nothing there.
class _YearStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onStep;

  const _YearStepper({required this.value, required this.onStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => onStep(-1),
          icon: const Icon(IconsaxPlusLinear.minus),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style:
                Theme.of(context).textTheme.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        IconButton(
          onPressed: () => onStep(1),
          icon: const Icon(IconsaxPlusLinear.add),
        ),
      ],
    );
  }
}

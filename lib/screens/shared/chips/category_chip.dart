import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/widgets/shared/anchored_popover.dart';
import 'package:fladder/widgets/shared/button_group.dart';

/// A filter over a set of things: genres, studios, years and the like.
///
/// The list hangs right under the chip on every device - opening on hover
/// where there is a pointer - and every box ticked is applied as it is
/// ticked, see [AnchoredPopover].
class CategoryChip<T> extends StatelessWidget {
  final Map<T, bool> items;
  final Widget label;
  final Widget? dialogueTitle;
  final Widget Function(T item) labelBuilder;

  /// Whether a long list gets a search box. For lists that grow with the
  /// library - genres, studios, tags - not for a handful of fixed choices.
  final bool searchable;

  /// Plain-text form of an item, used by the search box. Defaults to
  /// `toString()`, which is right for String items.
  final String Function(T item)? searchLabel;
  final IconData? activeIcon;
  final Function(Map<T, bool> value)? onSave;

  /// What clear goes back to, for a filter whose resting state is not
  /// "nothing ticked": the libraries a page was opened on, or the kinds of
  /// item those libraries hold. Clearing either to nothing showed nothing.
  /// Without it clear unticks everything.
  final Map<T, bool>? defaults;
  final VoidCallback? onClear;

  const CategoryChip({
    required this.label,
    this.dialogueTitle,
    this.activeIcon,
    required this.items,
    required this.labelBuilder,
    this.searchable = false,
    this.searchLabel,
    this.onSave,
    this.defaults,
    this.onClear,
    super.key,
  });

  /// No defaults known yet - the page has not loaded them - is no defaults.
  Map<T, bool>? get _defaults => defaults?.included.isNotEmpty == true ? defaults : null;

  bool get _atRest {
    final resting = _defaults;
    if (resting == null) return items.included.isEmpty;
    return setEquals(items.included.toSet(), resting.included.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final selection = items.included.isNotEmpty;
    final canClear = !_atRest && (_defaults != null ? onSave != null : onClear != null);

    return AnchoredPopover(
      anchorBuilder: (context, controller) => ExpressiveButton(
        isSelected: selection,
        icon: selection ? Icon(activeIcon ?? IconsaxPlusBold.archive_tick) : null,
        label: Row(
          spacing: 6,
          children: [
            label,
            Icon(
              controller.isOpen ? IconsaxPlusLinear.arrow_up_2 : IconsaxPlusLinear.arrow_down,
              size: 16,
            )
          ],
        ),
        onPressed: items.isNotEmpty ? controller.toggle : null,
      ),
      popoverBuilder: (context, controller) => _CategoryPanel<T>(
        title: dialogueTitle ?? label,
        items: items,
        labelBuilder: labelBuilder,
        searchable: searchable,
        searchLabel: searchLabel,
        onChanged: (value) => onSave?.call(value),
        onClear: !canClear
            ? null
            : () {
                controller.close();
                final resting = _defaults;
                resting != null ? onSave?.call(Map.of(resting)) : onClear?.call();
              },
      ),
    );
  }
}

/// The list under the chip: a title, a clear button while there is anything
/// to clear, and the choices.
///
/// A tick shows the moment it is made and the row stays where it is; the
/// filter follows a moment after the last tick, so three quick ticks cost one
/// fetch. On a long list what was ticked when the panel opened is repeated
/// at the top, so it can be found without scrolling - and it stays there,
/// ticked or not, until the panel closes: rows appearing and disappearing
/// above the one being looked at pushed the whole list out from under the
/// finger and the selection.
class _CategoryPanel<T> extends StatefulWidget {
  final Widget title;
  final Map<T, bool> items;
  final Widget Function(T item) labelBuilder;
  final bool searchable;
  final String Function(T item)? searchLabel;
  final ValueChanged<Map<T, bool>> onChanged;
  final VoidCallback? onClear;

  const _CategoryPanel({
    required this.title,
    required this.items,
    required this.labelBuilder,
    required this.searchable,
    required this.searchLabel,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  @override
  State<_CategoryPanel<T>> createState() => _CategoryPanelState<T>();
}

class _CategoryPanelState<T> extends State<_CategoryPanel<T>> {
  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 300));
  late Map<T, bool> _current = Map.of(widget.items);
  late final List<T> _tickedWhenOpened = widget.items.included;

  /// Ticks made here that the filter has not been handed yet.
  bool _pending = false;
  String _query = '';

  @override
  void didUpdateWidget(covariant _CategoryPanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.items, widget.items)) return;
    // The applied map coming back, or the list itself changing under the
    // panel. Ticks not yet handed on win over what comes back.
    _current = {
      for (final entry in widget.items.entries)
        entry.key: _pending && _current.containsKey(entry.key) ? _current[entry.key]! : entry.value,
    };
  }

  @override
  void dispose() {
    // Whatever was ticked last still counts when the panel goes - applied
    // after this frame, since the panel is taken down in the middle of one.
    if (_pending) {
      final value = Map.of(_current);
      final onChanged = widget.onChanged;
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(value));
    }
    super.dispose();
  }

  void _toggle(T key) {
    setState(() {
      _current[key] = !(_current[key] ?? false);
      _pending = true;
    });
    _debouncer.run(() {
      if (!mounted || !_pending) return;
      _pending = false;
      widget.onChanged(Map.of(_current));
    });
  }

  String _textOf(T item) => (widget.searchLabel ?? (e) => e.toString())(item);

  @override
  Widget build(BuildContext context) {
    // Genre/studio/tag lists routinely run past a hundred entries; scrolling
    // an unsearchable list that long is the worst part of filtering. A short
    // one reads faster than it can be searched, and has no need of its ticks
    // repeated at the top either.
    final long = widget.items.length > 10;
    final searchable = widget.searchable && long;
    final query = _query.trim().toLowerCase();
    final keys = widget.items.keys.where((key) => query.isEmpty || _textOf(key).toLowerCase().contains(query));
    final pinned = long && query.isEmpty ? _tickedWhenOpened.where(_current.containsKey).toList() : <T>[];

    Widget option(T key, {bool initial = false}) {
      final row = PopoverOption(
        label: widget.labelBuilder(key),
        selected: _current[key] ?? false,
        multiSelect: true,
        onTap: () => _toggle(key),
      );
      return initial ? PopoverInitialFocus(child: row) : row;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PopoverHeader(title: widget.title, onClear: widget.onClear),
        if (searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1),
                hintText: context.localized.search,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              if (pinned.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                  child: Text(context.localized.active, style: Theme.of(context).textTheme.labelLarge),
                ),
                for (final (index, key) in pinned.indexed) option(key, initial: index == 0),
                const Divider(),
              ],
              for (final (index, key) in keys.indexed) option(key, initial: pinned.isEmpty && index == 0),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/debouncer.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/widgets/shared/anchored_popover.dart';
import 'package:fladder/widgets/shared/button_group.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/modal_side_sheet.dart';

/// A filter over a set of things: genres, studios, years and the like.
///
/// With a pointer or a remote the list hangs right under the chip - opening
/// on hover where there is a pointer - and every box ticked is applied as it
/// is ticked, see [AnchoredPopover]. A touch screen gets the sheet it always
/// had.
class CategoryChip<T> extends StatelessWidget {
  final Map<T, bool> items;
  final Widget label;
  final Widget? dialogueTitle;
  final Widget Function(T item) labelBuilder;

  /// Plain-text form of an item, used by the editor's search box on long
  /// lists. Defaults to `toString()`, which is right for String items.
  final String Function(T item)? searchLabel;
  final IconData? activeIcon;
  final Function(Map<T, bool> value)? onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onClear;
  final VoidCallback? onDismiss;
  const CategoryChip({
    required this.label,
    this.dialogueTitle,
    this.activeIcon,
    required this.items,
    required this.labelBuilder,
    this.searchLabel,
    this.onSave,
    this.onCancel,
    this.onClear,
    this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final selection = items.included.isNotEmpty;
    final usePopover = AdaptiveLayout.inputDeviceOf(context) != InputDevice.touch;

    Widget chip({VoidCallback? onPressed, bool open = false}) => ExpressiveButton(
          isSelected: selection,
          icon: selection ? Icon(activeIcon ?? IconsaxPlusBold.archive_tick) : null,
          label: Row(
            spacing: 6,
            children: [
              label,
              Icon(
                open ? IconsaxPlusLinear.arrow_up_2 : IconsaxPlusLinear.arrow_down,
                size: 16,
              )
            ],
          ),
          onPressed: items.isNotEmpty ? onPressed : null,
        );

    if (!usePopover) {
      return chip(
        onPressed: () async {
          final newEntry = await openActionSheet(context);
          if (newEntry != null) {
            onSave?.call(newEntry);
          }
        },
      );
    }

    return AnchoredPopover(
      anchorBuilder: (context, controller) => chip(onPressed: controller.toggle, open: controller.isOpen),
      popoverBuilder: (context, controller) => _PopoverContent<T>(
        title: dialogueTitle ?? label,
        items: items,
        labelBuilder: labelBuilder,
        searchLabel: searchLabel,
        onChanged: (value) => onSave?.call(value),
        onClear: onClear == null
            ? null
            : () {
                controller.close();
                onClear!();
              },
      ),
    );
  }

  Future<Map<T, bool>?> openActionSheet(BuildContext context) async {
    Map<T, bool>? newEntry;
    List<Widget> actions() => [
          FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();
              newEntry = null;
              onCancel?.call();
            },
            child: Text(context.localized.cancel),
          ),
          if (onClear != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                newEntry = null;
                onClear!();
              },
              icon: const Icon(IconsaxPlusLinear.back_square),
              label: Text(context.localized.clear),
            )
        ].addInBetween(const SizedBox(width: 6));
    Widget header(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Material(
              color: Colors.transparent,
              textStyle: Theme.of(context).textTheme.titleLarge,
              child: dialogueTitle ?? label,
            ),
            Row(
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                    newEntry = null;
                    onCancel?.call();
                  },
                  child: Text(context.localized.cancel),
                ),
                if (onClear != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      newEntry = null;
                      onClear!();
                    },
                    icon: const Icon(IconsaxPlusLinear.back_square),
                    label: Text(context.localized.clear),
                  )
              ].addInBetween(const SizedBox(width: 6)),
            ),
          ],
        );

    if (AdaptiveLayout.viewSizeOf(context) != ViewSize.phone) {
      await showModalSideSheet(
        context,
        addDivider: true,
        header: dialogueTitle ?? label,
        actions: actions(),
        content: CategoryChipEditor(
            labelBuilder: labelBuilder,
            searchLabel: searchLabel,
            items: items,
            onChanged: (value) {
              newEntry = value;
            }),
        onDismiss: () {
          if (newEntry != null) {
            onSave?.call(newEntry!);
          }
        },
      );
    } else {
      await showBottomSheetPill(
        context: context,
        content: (context, scrollController) => ListView(
          shrinkWrap: true,
          controller: scrollController,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: header(context),
            ),
            const Divider(),
            CategoryChipEditor(
                labelBuilder: labelBuilder,
                searchLabel: searchLabel,
                controller: scrollController,
                items: items,
                onChanged: (value) => newEntry = value),
          ],
        ),
        onDismiss: () {
          if (newEntry != null) {
            onSave?.call(newEntry!);
          }
        },
      );
    }
    return newEntry;
  }
}

/// The list under the chip: a title, a clear button while anything is
/// ticked, and the boxes. Ticks are applied a moment after the last one, so
/// three quick ticks cost one fetch.
class _PopoverContent<T> extends StatefulWidget {
  final Widget title;
  final Map<T, bool> items;
  final Widget Function(T item) labelBuilder;
  final String Function(T item)? searchLabel;
  final ValueChanged<Map<T, bool>> onChanged;
  final VoidCallback? onClear;

  const _PopoverContent({
    required this.title,
    required this.items,
    required this.labelBuilder,
    required this.searchLabel,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  @override
  State<_PopoverContent<T>> createState() => _PopoverContentState<T>();
}

class _PopoverContentState<T> extends State<_PopoverContent<T>> {
  final Debouncer _debouncer = Debouncer(const Duration(milliseconds: 400));
  Map<T, bool>? _pending;

  @override
  void dispose() {
    // Whatever was ticked last still counts when the panel goes - applied
    // after this frame, since the panel is taken down in the middle of one.
    final pending = _pending;
    final onChanged = widget.onChanged;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(pending));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.items.included.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
                  child: widget.title,
                ),
              ),
              if (hasSelection && widget.onClear != null)
                TextButton.icon(
                  onPressed: widget.onClear,
                  icon: const Icon(IconsaxPlusLinear.close_circle, size: 16),
                  label: Text(context.localized.clear),
                ),
            ],
          ),
        ),
        Flexible(
          child: CategoryChipEditor<T>(
            items: widget.items,
            labelBuilder: widget.labelBuilder,
            searchLabel: widget.searchLabel,
            dense: true,
            onChanged: (value) {
              _pending = value;
              _debouncer.run(() {
                final pending = _pending;
                _pending = null;
                if (pending != null && mounted) widget.onChanged(pending);
              });
            },
          ),
        ),
      ],
    );
  }
}

class CategoryChipEditor<T> extends StatefulWidget {
  final Map<T, bool> items;
  final Widget Function(T item) labelBuilder;
  final String Function(T item)? searchLabel;
  final Function(Map<T, bool> value) onChanged;
  final ScrollController? controller;

  /// Tighter rows, for a panel rather than a sheet.
  final bool dense;
  const CategoryChipEditor({
    required this.items,
    required this.labelBuilder,
    this.searchLabel,
    required this.onChanged,
    this.controller,
    this.dense = false,
    super.key,
  });

  @override
  State<CategoryChipEditor<T>> createState() => _CategoryChipEditorState<T>();
}

class _CategoryChipEditorState<T> extends State<CategoryChipEditor<T>> {
  late Map<T, bool?> currentState = Map.fromEntries(widget.items.entries);
  String _query = '';

  String _textOf(T item) => (widget.searchLabel ?? (e) => e.toString())(item);

  @override
  void didUpdateWidget(covariant CategoryChipEditor<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A panel that stays open while its ticks are applied is handed the
    // applied map back; the local copy follows it, so nothing snaps back.
    if (!identical(oldWidget.items, widget.items)) {
      currentState = Map.fromEntries(widget.items.entries);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Genre/studio/tag lists routinely run past a hundred entries; scrolling
    // an unsearchable checkbox list that long is the worst part of filtering.
    final searchable = widget.items.length > 10;
    final query = _query.trim().toLowerCase();
    Iterable<MapEntry<T, bool>> activeItems = widget.items.entries.where((element) => element.value);
    Iterable<MapEntry<T, bool>> otherItems = widget.items.entries
        .where((element) => !element.value && (query.isEmpty || _textOf(element.key).toLowerCase().contains(query)));
    final visualDensity = widget.dense ? VisualDensity.compact : VisualDensity.standard;
    return ListView(
      shrinkWrap: true,
      controller: widget.controller,
      padding: widget.dense ? const EdgeInsets.only(bottom: 8) : null,
      children: [
        if (searchable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        if (activeItems.isNotEmpty == true) ...{
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              context.localized.active,
              style: widget.dense ? Theme.of(context).textTheme.labelLarge : Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ...activeItems.mapIndexed((index, element) {
            return Builder(builder: (context) {
              return CheckboxListTile(
                value: currentState[element.key],
                title: widget.labelBuilder(element.key),
                visualDensity: visualDensity,
                dense: widget.dense,
                onFocusChange: (value) {
                  if (value) {
                    context.ensureVisible();
                  }
                },
                fillColor: WidgetStateProperty.resolveWith(
                  (states) {
                    if (currentState[element.key] == null) {
                      return Colors.redAccent;
                    }
                    return null;
                  },
                ),
                tristate: true,
                onChanged: (value) => updateKey(MapEntry(element.key, value == null ? null : element.value)),
              );
            });
          }),
          const Divider(),
        },
        ...otherItems.mapIndexed((index, element) {
          return Builder(builder: (context) {
            return CheckboxListTile(
              value: currentState[element.key],
              title: widget.labelBuilder(element.key),
              visualDensity: visualDensity,
              dense: widget.dense,
              onFocusChange: (value) {
                if (value) {
                  context.ensureVisible();
                }
              },
              fillColor: WidgetStateProperty.resolveWith(
                (states) {
                  if (currentState[element.key] == null || states.contains(WidgetState.selected)) {
                    return Colors.greenAccent;
                  }
                  return null;
                },
              ),
              tristate: true,
              onChanged: (value) => updateKey(MapEntry(element.key, value != false ? null : element.value)),
            );
          });
        }),
      ],
    );
  }

  void updateKey(MapEntry<T, bool?> entry) {
    setState(() {
      currentState.update(
        entry.key,
        (value) => entry.value,
      );
    });
    widget.onChanged(Map.from(currentState.map(
      (key, value) {
        final origKey = widget.items[key] == true;
        return MapEntry(key, origKey ? (value == null ? false : origKey) : (value == null ? true : origKey));
      },
    )));
  }
}

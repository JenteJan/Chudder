import 'package:flutter/material.dart';

import 'package:fladder/util/position_provider.dart';

class ExpressiveButtonGroup<T> extends StatelessWidget {
  final List<ButtonGroupOption<T>> options;
  final Set<T> selectedValues;
  final ValueChanged<Set<T>> onSelected;
  final bool multiSelection;

  const ExpressiveButtonGroup({
    super.key,
    required this.options,
    required this.selectedValues,
    required this.onSelected,
    this.multiSelection = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      spacing: 2,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(
        options.length,
        (index) {
          final option = options[index];
          final isSelected = selectedValues.contains(option.value);

          final position = index == 0
              ? PositionContext.first
              : (index == options.length - 1 ? PositionContext.last : PositionContext.middle);

          return PositionProvider(
            position: position,
            child: ExpressiveButton(
              isSelected: isSelected,
              roundWhenSelected: true,
              label: option.child,
              icon: isSelected ? option.selected ?? const Icon(Icons.check_rounded) : option.icon,
              onPressed: () {
                final newSet = Set<T>.from(selectedValues);
                if (multiSelection) {
                  isSelected ? newSet.remove(option.value) : newSet.add(option.value);
                } else {
                  newSet
                    ..clear()
                    ..add(option.value);
                }
                onSelected(newSet);
              },
            ),
          );
        },
      ),
    );
  }
}

class ExpressiveButton extends StatelessWidget {
  const ExpressiveButton({
    super.key,
    required this.isSelected,
    required this.label,
    this.icon,
    required this.onPressed,
    this.onLongPress,
    this.roundWhenSelected = false,
  });

  final bool? isSelected;

  /// Whether a selected button rounds into a pill whatever its place in the
  /// row. Off for the filter bars: a row of joined chips where every selected
  /// one turned round no longer read as one bar. A segmented choice, where
  /// the one picked is the point, keeps it.
  final bool roundWhenSelected;
  final Widget label;
  final Widget? icon;
  final Function()? onPressed;
  final Function()? onLongPress;

  @override
  Widget build(BuildContext context) {
    final position = PositionProvider.of(context);
    final round = roundWhenSelected && isSelected == true;
    final borderRadius = BorderRadiusDirectional.horizontal(
      start: round || (position?.isFirst ?? false) ? const Radius.circular(16) : const Radius.circular(4),
      end: round || (position?.isLast ?? false) ? const Radius.circular(16) : const Radius.circular(4),
    );
    return ElevatedButton.icon(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: borderRadius)),
        elevation: const WidgetStatePropertyAll(0),
        // Resting colours only; selected, the theme turns the button inside
        // out and rings it like every other.
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
            ? null
            : isSelected == true
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest),
        foregroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
            ? null
            : isSelected == true
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant),
        textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelLarge),
        visualDensity: VisualDensity.comfortable,
        padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
      ),
      onPressed: onPressed,
      onLongPress: onLongPress,
      label: label,
      icon: icon,
    );
  }
}

class ButtonGroupOption<T> {
  final T value;
  final Icon? icon;
  final Icon? selected;
  final Widget child;

  const ButtonGroupOption({
    required this.value,
    this.icon,
    this.selected,
    required this.child,
  });
}

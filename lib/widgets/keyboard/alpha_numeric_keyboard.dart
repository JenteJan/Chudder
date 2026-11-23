import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/widgets/keyboard/keyboard_localization.dart';

class AlphaNumericKeyboard extends ConsumerStatefulWidget {
  final void Function(String character) onCharacter;
  final TextInputType keyboardType;
  final TextInputAction keyboardActionType;
  final VoidCallback onBackspace;

  /// Moves the caret by that many characters; without it there are no
  /// arrow keys.
  final void Function(int by)? onCursor;
  final VoidCallback onClear;
  final VoidCallback onDone;

  const AlphaNumericKeyboard({
    required this.onCharacter,
    this.keyboardType = TextInputType.name,
    this.keyboardActionType = TextInputAction.done,
    required this.onBackspace,
    this.onCursor,
    required this.onClear,
    required this.onDone,
    super.key,
  });

  @override
  ConsumerState<AlphaNumericKeyboard> createState() => _AlphaNumericKeyboardState();
}

class _AlphaNumericKeyboardState extends ConsumerState<AlphaNumericKeyboard> {
  static final _numericKeyboardTypes = {
    TextInputType.number,
    TextInputType.phone,
    const TextInputType.numberWithOptions(decimal: true, signed: false),
    const TextInputType.numberWithOptions(decimal: false, signed: true),
    const TextInputType.numberWithOptions(decimal: true, signed: true),
  };

  bool usingAlpha = true;
  bool shift = false;
  late TextInputType type = widget.keyboardType;
  late TextInputAction actionType = widget.keyboardActionType;

  bool get isNumericKeyboard => _numericKeyboardTypes.contains(type);

  List<List<String>> activeLayout(Locale locale) {
    if (isNumericKeyboard) {
      return [
        ['1', '2', '3', '⌫'],
        ['4', '5', '6', ','],
        ['7', '8', '9', '.'],
        ['', '0', ''],
      ];
    }

    final localeLayouts = KeyboardLayouts.layouts.containsKey(locale.languageCode)
        ? KeyboardLayouts.layouts[locale.languageCode]!
        : KeyboardLayouts.layouts['en']!;
    return usingAlpha ? localeLayouts[KeyboardLayer.alpha]! : localeLayouts[KeyboardLayer.numericExtra]!;
  }

  /// A label in the button's own colour. The text theme's styles carry a
  /// colour of their own, and a label wearing it stayed pale on the key the
  /// selection had turned inside out - white on white.
  TextStyle get _keyLabelStyle =>
      TextStyle(fontSize: Theme.of(context).textTheme.titleLarge?.fontSize, fontWeight: FontWeight.bold);

  /// The key's resting colour only; selected, the theme turns the key inside
  /// out - ring colour behind, surface colour on top - like every button.
  WidgetStateProperty<Color?> _resting(Color? color) =>
      WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused) ? null : color);

  Widget buildKey(String label, {required double height, bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: ExcludeFocus(
        excluding: label.isEmpty,
        child: SizedBox(
          height: height,
          child: label.isEmpty
              ? null
              : ElevatedButton(
                  autofocus: autofocus,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                  ).copyWith(foregroundColor: _resting(Theme.of(context).colorScheme.onSurface)),
                  onPressed: () {
                    switch (label) {
                      case '⌫':
                        widget.onBackspace();
                        break;
                      case '123':
                      case 'ABC':
                        setState(() => usingAlpha = !usingAlpha);
                        break;
                      default:
                        widget.onCharacter(shift ? label.toUpperCase() : label.toLowerCase());
                    }
                  },
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: switch (label) {
                      '⌫' => const Icon(Icons.backspace_rounded, size: 28),
                      _ => Text(
                        shift ? label.toUpperCase() : label.toLowerCase(),
                        style: _keyLabelStyle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    },
                  ),
                ),
        ),
      ),
    );
  }

  Widget buildAction(KeyboardActions action, double height) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: SizedBox(
        height: height,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(shape: FladderTheme.smallShape, padding: const EdgeInsets.all(6)).copyWith(
            backgroundColor: _resting(switch (action) {
              KeyboardActions.shift => shift ? Theme.of(context).colorScheme.primary : null,
              _ => null,
            }),
            iconColor: _resting(switch (action) {
              KeyboardActions.shift => shift ? Theme.of(context).colorScheme.onPrimary : null,
              _ => null,
            }),
          ),
          onPressed: () {
            switch (action) {
              case KeyboardActions.space:
                widget.onCharacter(" ");
                break;
              case KeyboardActions.clear:
                widget.onClear();
                break;
              case KeyboardActions.action:
                widget.onDone();
                break;
              case KeyboardActions.cursorLeft:
                widget.onCursor?.call(-1);
                break;
              case KeyboardActions.cursorRight:
                widget.onCursor?.call(1);
                break;
              case KeyboardActions.shift:
                setState(() {
                  shift = !shift;
                });
                break;
            }
          },
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: switch (action) {
              KeyboardActions.action => Icon(switch (actionType) {
                TextInputAction.next => IconsaxPlusBold.next,
                TextInputAction.done => Icons.check_rounded,
                TextInputAction.send => IconsaxPlusBold.send_1,
                _ => IconsaxPlusBold.send_1,
              }, size: 28),
              KeyboardActions.shift => const Icon(Icons.keyboard_capslock_rounded, size: 28),
              KeyboardActions.cursorLeft => const Icon(Icons.chevron_left_rounded, size: 32),
              KeyboardActions.cursorRight => const Icon(Icons.chevron_right_rounded, size: 32),
              _ => Text(action.label(context).toUpperCase(), style: _keyLabelStyle, maxLines: 1),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(
      clientSettingsProvider.select(
        (value) => value.selectedLocale ?? WidgetsBinding.instance.platformDispatcher.locale,
      ),
    );
    final rows = activeLayout(language);
    final columns = rows.fold<int>(0, (most, row) => row.length > most ? row.length : most);

    final helperButtons = switch (type) {
      TextInputType.url => ["https://", "http://", ".", "://", ".com", ".nl"],
      TextInputType.emailAddress => ["@gmail.com", "@hotmail.com"],
      _ => <String>[],
    };

    final actions = KeyboardActions.values
        .where(
          (action) =>
              widget.onCursor != null ||
              (action != KeyboardActions.cursorLeft && action != KeyboardActions.cursorRight),
        )
        .toList();

    // The keys fill the keyboard's width; their height is what the screen
    // has room for, between a small key and a comfortable one.
    return LayoutBuilder(
      builder: (context, constraints) {
        const helperHeight = 44.0;
        final reserved = (helperButtons.isNotEmpty ? helperHeight + 6 + 16 : 0) + 12 * 2;
        final available = constraints.maxHeight.isFinite ? constraints.maxHeight - reserved : double.infinity;
        // The keys' rows and the actions' row share what is left.
        final keyHeight = ((available / (rows.length + 1)) - 6).clamp(34.0, 60.0);

        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int r = 0; r < rows.length; r++)
                    Row(
                      children: [
                        for (int c = 0; c < columns; c++)
                          Expanded(
                            child: buildKey(
                              c < rows[r].length ? rows[r][c] : '',
                              height: keyHeight,
                              autofocus: r == 0 && c == 0,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (helperButtons.isNotEmpty) ...[
                Row(
                  children: helperButtons
                      .map(
                        (e) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: SizedBox(
                              height: helperHeight,
                              child: FilledButton.tonal(
                                onPressed: () => widget.onCharacter(e),
                                style: FilledButton.styleFrom(
                                  shape: FladderTheme.smallShape,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                child: FittedBox(fit: BoxFit.scaleDown, child: Text(e, maxLines: 1)),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const Divider(height: 4),
              ],
              Row(
                children: [
                  for (final action in actions)
                    Expanded(
                      flex: action == KeyboardActions.space ? 3 : (action == KeyboardActions.clear ? 2 : 1),
                      child: buildAction(action, keyHeight),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

enum KeyboardActions {
  shift,
  cursorLeft,
  space,
  cursorRight,
  clear,
  action;

  const KeyboardActions();

  String label(BuildContext context) {
    return switch (this) {
      KeyboardActions.space => "Space",
      KeyboardActions.clear => "Clear",
      KeyboardActions.action => "Action",
      KeyboardActions.shift => "Shift",
      KeyboardActions.cursorLeft => "Left",
      KeyboardActions.cursorRight => "Right",
    };
  }
}

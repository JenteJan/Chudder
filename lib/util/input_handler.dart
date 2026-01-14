import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/settings/key_combinations.dart';
import 'package:fladder/screens/settings/widgets/key_listener.dart';
import 'package:fladder/util/focus_helper.dart';
import 'package:fladder/util/platform_helper.dart';

class InputHandler<T> extends ConsumerStatefulWidget {
  final bool autoFocus;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final bool Function(T result)? keyMapResult;
  final Map<T, KeyCombination>? keyMap;
  final Widget child;
  const InputHandler({
    required this.child,
    this.autoFocus = true,
    this.onKeyEvent,
    this.keyMapResult,
    this.keyMap,
    super.key,
  });

  @override
  ConsumerState<InputHandler> createState() => _InputHandlerState<T>();
}

class _InputHandlerState<T> extends ConsumerState<InputHandler<T>> {
  final focusNode = FocusNode();

  LogicalKeyboardKey? pressedModifier;

  @override
  void initState() {
    super.initState();
    // Focus on start
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autoFocus,
      focusNode: focusNode,
      skipTraversal: true,
      onFocusChange: (value) {
        // On Tizen, don't steal focus back - let child widgets (buttons) keep focus for D-pad navigation
        if (PlatformHelper.isTizen) return;

        final inputFieldFocus = isEditableTextFocused();
        if (!focusNode.hasFocus && widget.autoFocus && !inputFieldFocus) {
          focusNode.requestFocus();
        }
      },
      onKeyEvent: (node, event) {
        // If custom onKeyEvent is provided, try it first
        if (widget.onKeyEvent != null) {
          final result = widget.onKeyEvent!(node, event);
          // If handled or skipRemainingHandlers, don't process keyMap
          if (result != KeyEventResult.ignored) {
            return result;
          }
        }
        // Fall back to keyMap processing
        return _onKey(event);
      },
      child: widget.child,
    );
  }

  // Arrow keys that should be skipped on Tizen to allow D-pad navigation
  static final _tizenNavigationKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };

  KeyEventResult _onKey(KeyEvent value) {
    if (changingShortCut) return KeyEventResult.ignored;

    // On Tizen, skip arrow key processing in keyMap - let Tizen handler or focus system handle them
    if (PlatformHelper.isTizen && _tizenNavigationKeys.contains(value.logicalKey)) {
      return KeyEventResult.ignored;
    }

    final keyMap = widget.keyMap?.entries.nonNulls.toList() ?? [];
    if (value is KeyDownEvent || value is KeyRepeatEvent) {
      if (KeyCombination.modifierKeys.contains(value.logicalKey)) {
        pressedModifier = value.logicalKey;
      }

      for (var entry in keyMap) {
        final hotKey = entry.key;
        final keyCombination = entry.value;

        bool isMainKeyPressed = value.logicalKey == keyCombination.key;
        bool isModifierKeyPressed = pressedModifier == keyCombination.modifier;

        bool isAltKeyPressed = value.logicalKey == keyCombination.altKey;

        bool isAltModifierKeyPressed = pressedModifier == keyCombination.altModifier;

        if ((isMainKeyPressed && isModifierKeyPressed) || isAltKeyPressed && isAltModifierKeyPressed) {
          if (widget.keyMapResult?.call(hotKey) ?? false) {
            return KeyEventResult.handled;
          } else {
            return KeyEventResult.ignored;
          }
        }
      }
    } else if (value is KeyUpEvent) {
      if (KeyCombination.modifierKeys.contains(value.logicalKey)) {
        pressedModifier = null;
      }
    }
    return KeyEventResult.ignored;
  }
}

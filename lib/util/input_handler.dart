import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/settings/key_combinations.dart';
import 'package:chudder/screens/settings/widgets/key_listener.dart';
import 'package:chudder/util/focus_helper.dart';

/// A part of the screen that keeps the keys to itself while it holds the
/// focus, such as a panel laid over the player.
///
/// Every [InputHandler] outside it stands aside meanwhile - the raw ones too,
/// which otherwise run before focus is asked at all. Space then presses the
/// focused button instead of pausing the film, and the arrows walk through
/// the panel instead of seeking. Handlers inside it carry on as usual.
///
/// While [active], it takes the focus: onto whatever inside asks for
/// autofocus, or else onto [home] (a node inside that holds the keys without
/// showing a selection). When it stops being active, the focus goes back to
/// wherever it was taken from.
class KeyGuard extends StatefulWidget {
  final bool active;
  final FocusNode? home;
  final Widget child;
  const KeyGuard({required this.active, required this.child, this.home, super.key});

  static final Set<FocusScopeNode> _holding = {};

  /// Whether any guard holds the focus: code that moves the focus about on
  /// its own (controls fading out) leaves it where it is then.
  static bool get holdingFocus => _holding.any((scope) => scope.hasFocus);

  /// Whether a guard other than the one around [context] holds the focus.
  static bool standsAside(BuildContext context) {
    if (_holding.isEmpty || !context.mounted) return false;
    final own = context.findAncestorStateOfType<_KeyGuardState>()?._scope;
    return _holding.any((scope) => scope != own && scope.hasFocus);
  }

  @override
  State<KeyGuard> createState() => _KeyGuardState();
}

class _KeyGuardState extends State<KeyGuard> {
  final FocusScopeNode _scope = FocusScopeNode(debugLabel: 'KeyGuard');
  FocusNode? _takenFrom;

  @override
  void initState() {
    super.initState();
    if (widget.active) _activate();
  }

  @override
  void didUpdateWidget(covariant KeyGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _activate();
    if (!widget.active && oldWidget.active) _deactivate();
  }

  void _activate() {
    KeyGuard._holding.add(_scope);
    final current = FocusManager.instance.primaryFocus;
    if (current != null && !current.ancestors.contains(_scope)) _takenFrom = current;
    // After the autofocus inside has had its turn, which comes in a microtask
    // after the frame: taking the focus any earlier left that autofocus
    // finding the scope already served, and the remote's first stop (the line
    // nearest the pause, "Now") never got it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (!mounted || !widget.active || _scope.hasFocus) return;
        (widget.home ?? _scope).requestFocus();
      });
    });
  }

  void _deactivate() {
    KeyGuard._holding.remove(_scope);
    final back = _takenFrom;
    _takenFrom = null;
    if (!_scope.hasFocus) return;
    if (back != null && back.context?.mounted == true && back.canRequestFocus) {
      back.requestFocus();
    } else {
      _scope.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  @override
  void dispose() {
    if (widget.active) _deactivate();
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FocusScope(node: _scope, child: widget.child);
}

class InputHandler<T> extends ConsumerStatefulWidget {
  final bool autoFocus;
  final bool listenRawKeyboard;
  final bool ignoreWhenTextFieldFocused;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final bool Function(T result)? keyMapResult;
  final Map<T, KeyCombination>? keyMap;

  /// The node the handler listens on, when the caller needs to place the
  /// focus there itself; see [KeyGuard.home].
  final FocusNode? focusNode;
  final Widget child;
  const InputHandler({
    required this.child,
    this.focusNode,
    this.autoFocus = true,
    this.listenRawKeyboard = false,
    this.ignoreWhenTextFieldFocused = true,
    this.onKeyEvent,
    this.keyMapResult,
    this.keyMap,
    super.key,
  });

  @override
  ConsumerState<InputHandler> createState() => _InputHandlerState<T>();
}

class _InputHandlerState<T> extends ConsumerState<InputHandler<T>> {
  static final List<_InputHandlerState<dynamic>> _hardwareHandlers = [];
  static bool _hardwareListening = false;

  static bool _handleHardwareKey(KeyEvent event) {
    for (final handler in _hardwareHandlers.toList().reversed) {
      if (!handler.mounted) continue;
      if (handler.widget.ignoreWhenTextFieldFocused && isEditableTextFocused()) {
        continue;
      }
      final result = handler._onHardwareKey(event);
      if (result == KeyEventResult.handled || result == KeyEventResult.skipRemainingHandlers) {
        return true;
      }
    }
    return false;
  }

  void _registerHardwareKeyboard() {
    _hardwareHandlers.add(this);
    if (!_hardwareListening) {
      HardwareKeyboard.instance.addHandler(_handleHardwareKey);
      _hardwareListening = true;
    }
  }

  void _unregisterHardwareKeyboard() {
    _hardwareHandlers.remove(this);
    if (_hardwareHandlers.isEmpty && _hardwareListening) {
      HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
      _hardwareListening = false;
    }
  }

  final _ownFocusNode = FocusNode();
  FocusNode get focusNode => widget.focusNode ?? _ownFocusNode;

  LogicalKeyboardKey? pressedModifier;

  @override
  void initState() {
    super.initState();
    if (widget.listenRawKeyboard) {
      _registerHardwareKeyboard();
    }
  }

  @override
  void dispose() {
    _unregisterHardwareKeyboard();
    _ownFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listenRawKeyboard) {
      return widget.child;
    } else {
      return Focus(
        autofocus: widget.autoFocus,
        focusNode: focusNode,
        skipTraversal: true,
        onFocusChange: (value) {
          final inputFieldFocus = isEditableTextFocused();
          final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
          if (!focusNode.hasFocus && widget.autoFocus && !inputFieldFocus && isCurrent) {
            focusNode.requestFocus();
          }
        },
        onKeyEvent: (node, event) {
          // Typing inside the page (the subtitle line search in the player)
          // bubbles up here too: the letters and space are the text's.
          if (widget.ignoreWhenTextFieldFocused && isEditableTextFocused()) return KeyEventResult.ignored;
          if (KeyGuard.standsAside(context)) return KeyEventResult.ignored;
          if (widget.onKeyEvent != null) {
            final result = widget.onKeyEvent!(node, event);
            if (result != KeyEventResult.ignored) {
              return result;
            }
          }
          return _onKey(event);
        },
        child: widget.child,
      );
    }
  }

  KeyEventResult _onKey(KeyEvent value) {
    return _handleLogicalKey(
      logicalKey: value.logicalKey,
      isDown: value is KeyDownEvent,
      isRepeat: value is KeyRepeatEvent,
      isUp: value is KeyUpEvent,
    );
  }

  KeyEventResult _onHardwareKey(KeyEvent value) {
    if (!widget.listenRawKeyboard) return KeyEventResult.ignored;
    // Not while something is open on top of it. A raw keyboard handler is
    // global - it runs before focus is consulted and knows nothing about
    // routes - so the player went on seeking and changing volume underneath
    // whatever dialog was being read, which is what made focus look as though
    // it had fallen through to the page behind.
    if (!mounted) return KeyEventResult.ignored;
    if (ModalRoute.of(context)?.isCurrent == false) return KeyEventResult.ignored;
    if (KeyGuard.standsAside(context)) return KeyEventResult.ignored;
    return _handleLogicalKey(
      logicalKey: value.logicalKey,
      isDown: value is KeyDownEvent,
      isRepeat: value is KeyRepeatEvent,
      isUp: value is KeyUpEvent,
    );
  }

  KeyEventResult _handleLogicalKey({
    required LogicalKeyboardKey logicalKey,
    required bool isDown,
    required bool isRepeat,
    required bool isUp,
  }) {
    if (changingShortCut) return KeyEventResult.ignored;

    final keyMap = widget.keyMap?.entries.nonNulls.toList() ?? [];
    if (isDown || isRepeat) {
      if (KeyCombination.modifierKeys.contains(logicalKey)) {
        pressedModifier = logicalKey;
      }

      for (var entry in keyMap) {
        final hotKey = entry.key;
        final keyCombination = entry.value;

        bool isMainKeyPressed = logicalKey == keyCombination.key;
        bool isModifierKeyPressed = KeyCombination.modifierMatches(pressedModifier, keyCombination.modifier);

        bool isAltKeyPressed = logicalKey == keyCombination.altKey;

        bool isAltModifierKeyPressed = KeyCombination.modifierMatches(pressedModifier, keyCombination.altModifier);

        if ((isMainKeyPressed && isModifierKeyPressed) || isAltKeyPressed && isAltModifierKeyPressed) {
          if (widget.keyMapResult?.call(hotKey) ?? false) {
            return KeyEventResult.handled;
          } else {
            return KeyEventResult.ignored;
          }
        }
      }
    } else if (isUp) {
      if (KeyCombination.modifierKeys.contains(logicalKey)) {
        pressedModifier = null;
      }
    }
    return KeyEventResult.ignored;
  }
}

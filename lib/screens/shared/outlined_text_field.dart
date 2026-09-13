import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/widgets/shared/focus_ring.dart';
import 'package:fladder/widgets/keyboard/slide_in_keyboard.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';

/// Asks a field to take the selection again, some time after it was built.
///
/// [OutlinedTextField.autoFocus] fires once, when the field is first built;
/// a field on a page that stays alive - the Search tab's, which keeps its
/// results while another tab is showing - is built once and shown many
/// times. Whoever knows when it is shown again holds one of these and asks.
class TextFieldFocusTrigger extends ChangeNotifier {
  void request() => notifyListeners();
}

class OutlinedTextField extends ConsumerStatefulWidget {
  final String? label;
  final String? subLabel;
  final FocusNode? focusNode;
  final bool autoFocus;

  /// Fires to give the field the selection the way [autoFocus] does on its
  /// first build. See [TextFieldFocusTrigger].
  final Listenable? focusTrigger;

  /// The field's corners, and its ring's. The app's small shape unless the
  /// field sits in something that clips it another way - the search bar in
  /// the library toolbar, whose corners follow its place in the row.
  final BorderRadiusGeometry? borderRadius;
  final TextEditingController? controller;
  final int maxLines;
  final Function()? onTap;
  final Function(String value)? onChanged;
  final Function(String value)? onSubmitted;
  final FutureOr<List<String>> Function(String query)? searchQuery;
  final List<String>? autoFillHints;
  final List<TextInputFormatter>? inputFormatters;
  final bool autocorrect;
  final TextStyle? style;
  final double borderWidth;
  final Color? fillColor;
  final TextAlign textAlign;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final InputDecoration? decoration;
  final String? placeHolder;
  final String? suffix;
  final String? errorText;
  final bool? enabled;

  const OutlinedTextField({
    this.label,
    this.subLabel,
    this.focusNode,
    this.autoFocus = false,
    this.focusTrigger,
    this.borderRadius,
    this.controller,
    this.maxLines = 1,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.searchQuery,
    this.fillColor,
    this.style,
    this.borderWidth = 1,
    this.textAlign = TextAlign.start,
    this.autoFillHints,
    this.inputFormatters,
    this.autocorrect = true,
    this.keyboardType,
    this.textInputAction,
    this.errorText,
    this.placeHolder,
    this.decoration,
    this.suffix,
    this.enabled,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _OutlinedTextFieldState();
}

class _OutlinedTextFieldState extends ConsumerState<OutlinedTextField> {
  late final bool _ownsController = widget.controller == null;
  late final TextEditingController controller = widget.controller ?? TextEditingController();
  late final bool _ownsTextFocus = widget.focusNode == null;
  late final FocusNode _textFocus = widget.focusNode ?? FocusNode();
  late final FocusNode _wrapperFocus = FocusNode()
    ..addListener(() {
      setState(() {
        hasFocus = _wrapperFocus.hasFocus;
        if (hasFocus) {
          context.ensureVisible();
          if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer) {
            _textFocus.requestFocus();
          }
        }
      });
    });

  bool hasFocus = false;
  bool keyboardFocus = false;

  @override
  void didUpdateWidget(covariant OutlinedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusTrigger, widget.focusTrigger)) {
      oldWidget.focusTrigger?.removeListener(focus);
      widget.focusTrigger?.addListener(focus);
    }
  }

  @override
  void dispose() {
    widget.focusTrigger?.removeListener(focus);
    if (_ownsTextFocus) {
      _textFocus.dispose();
    }
    if (_ownsController) {
      controller.dispose();
    }
    _wrapperFocus.dispose();
    super.dispose();
  }

  /// Gives the field the selection: on a pad with the app's own keyboard the
  /// wrapper that opens it on Select, otherwise the text itself, with its
  /// caret and whatever keyboard the platform brings.
  void focus() {
    if (!mounted) return;
    final useCustomKeyboard = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad &&
        ref.read(clientSettingsProvider.select((value) => !value.useSystemIME));
    if (useCustomKeyboard) {
      _wrapperFocus.requestFocus();
    } else {
      _textFocus.requestFocus();
    }
  }

  bool _obscureText = true;
  void _toggle() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  Color getColor() {
    if (widget.errorText != null) return Theme.of(context).colorScheme.errorContainer;
    return Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
  }

  @override
  void initState() {
    super.initState();
    widget.focusTrigger?.addListener(focus);
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => focus());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPasswordField = widget.keyboardType == TextInputType.visiblePassword;
    final useCustomKeyboard = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad &&
        ref.watch(clientSettingsProvider.select((value) => !value.useSystemIME));

    final textField = TextField(
      controller: controller,
      onChanged: widget.onChanged,
      focusNode: _textFocus,
      onTap: widget.onTap,
      readOnly: useCustomKeyboard,
      autofillHints: widget.autoFillHints,
      keyboardType: widget.keyboardType,
      autocorrect: widget.autocorrect,
      onSubmitted: widget.onSubmitted != null
          ? (value) {
              widget.onSubmitted?.call(value);
              if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad) return;
              Future.microtask(() async {
                await Future.delayed(const Duration(milliseconds: 125));
                _wrapperFocus.requestFocus();
              });
            }
          : null,
      textInputAction: widget.textInputAction,
      obscureText: isPasswordField ? _obscureText : false,
      style: widget.style,
      maxLines: widget.maxLines,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      canRequestFocus: true,
      decoration: widget.decoration ??
          InputDecoration(
            border: InputBorder.none,
            filled: widget.fillColor != null,
            fillColor: widget.fillColor,
            labelText: widget.label,
            suffix: widget.suffix != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(widget.suffix!),
                  )
                : null,
            hintText: widget.placeHolder,
            // errorText: widget.errorText,
            suffixIcon: isPasswordField
                ? InkWell(
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(5),
                    child: Icon(
                      _obscureText ? Icons.visibility : Icons.visibility_off,
                      size: 16.0,
                    ),
                  )
                : null,
          ),
    );

    final borderRadius = widget.borderRadius ?? FladderTheme.smallShape.borderRadius;
    return Column(
      children: [
        FocusRing(
          visible: hasFocus || keyboardFocus,
          borderRadius: borderRadius,
          duration: const Duration(milliseconds: 175),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 175),
            decoration: BoxDecoration(
              // A fill given is drawn whether or not the field brings its own
              // decoration; without either, the default fill.
              color: widget.fillColor ?? (widget.decoration == null ? getColor() : null),
              borderRadius: borderRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: IgnorePointer(
                ignoring: widget.enabled == false,
                child: KeyboardListener(
                  focusNode: _wrapperFocus,
                  onKeyEvent: (KeyEvent event) async {
                    if (keyboardFocus || AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad) return;
                    if (event is KeyDownEvent && acceptKeys.contains(event.logicalKey)) {
                      if (_textFocus.hasFocus) {
                        _wrapperFocus.requestFocus();
                      } else if (_wrapperFocus.hasFocus) {
                        if (useCustomKeyboard) {
                          await openKeyboard(
                            context,
                            controller,
                            inputType: widget.keyboardType,
                            inputAction: widget.textInputAction,
                            searchQuery: widget.searchQuery,
                            onChanged: () {
                              widget.onChanged?.call(controller.text);
                            },
                          );
                          widget.onSubmitted?.call(controller.text);
                          setState(() {
                            keyboardFocus = false;
                          });
                          _wrapperFocus.requestFocus();
                        } else {
                          _textFocus.requestFocus();
                        }
                      }
                    }
                  },
                  child: ExcludeFocusTraversal(
                    child: textField,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.subLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.subLabel!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        AnimatedFadeSize(
          child: widget.errorText != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.errorText ?? "",
                    style:
                        Theme.of(context).textTheme.labelMedium?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                )
              : Container(),
        ),
      ],
    );
  }
}

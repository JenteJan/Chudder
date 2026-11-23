import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/screens/shared/animated_fade_size.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/keyboard/alpha_numeric_keyboard.dart';

ValueNotifier<bool> isKeyboardOpen = ValueNotifier<bool>(false);

/// The share of the screen the keyboard takes: enough for its keys at
/// nearly their own size (about 640 wide), never under a quarter of the
/// screen, never over 45% of it.
double keyboardWidthFactor(double screenWidth) {
  if (screenWidth <= 0) return 0.25;
  return (640 / screenWidth).clamp(0.25, 0.45);
}

class CustomKeyboardWrapper extends StatelessWidget {
  final Widget child;
  const CustomKeyboardWrapper({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      // Right: the page makes room on the side the keyboard slides in from,
      // whatever constraints it is given.
      alignment: Alignment.centerRight,
      child: ValueListenableBuilder(
        valueListenable: isKeyboardOpen,
        builder: (context, value, _) {
          return AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 175),
            widthFactor: value ? 1.0 - keyboardWidthFactor(MediaQuery.sizeOf(context).width) : 1.0,
            heightFactor: 1.0,
            alignment: Alignment.centerRight,
            child: child,
          );
        },
      ),
    );
  }
}

Future<T?> openKeyboard<T>(
  BuildContext context,
  TextEditingController controller, {
  TextInputType? inputType,
  TextInputAction? inputAction,
  FutureOr<List<String>> Function(String query)? searchQuery,
  VoidCallback? onChanged,
}) async {
  isKeyboardOpen.value = true;
  await showGeneralDialog(
    context: context,
    transitionDuration: const Duration(milliseconds: 175),
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    barrierLabel: 'Custom keyboard',
    useRootNavigator: true,
    fullscreenDialog: true,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween(begin: const Offset(-1, 0), end: const Offset(0, 0)).animate(animation),
        child: child,
      );
    },
    pageBuilder: (context, animation1, animation2) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _SlideInKeyboard(
          controller: controller,
          onChanged: onChanged ?? () {},
          onClose: () {
            context.router.pop();
            isKeyboardOpen.value = false;
            return null;
          },
          inputType: inputType,
          inputAction: inputAction,
          searchQuery: searchQuery,
        ),
      );
    },
  );
  isKeyboardOpen.value = false;
  return null;
}

class _SlideInKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final Function() onChanged;
  final Function() onClose;
  final TextInputType? inputType;
  final TextInputAction? inputAction;
  final FutureOr<List<String>> Function(String query)? searchQuery;
  const _SlideInKeyboard({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.inputType,
    this.inputAction,
    this.searchQuery,
  });

  @override
  State<_SlideInKeyboard> createState() => __SlideInKeyboardState();
}

class __SlideInKeyboardState extends State<_SlideInKeyboard> {
  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final factor = keyboardWidthFactor(MediaQuery.sizeOf(context).width);
    final width = MediaQuery.sizeOf(context).width * factor;
    return FractionallySizedBox(
      widthFactor: factor,
      heightFactor: 1.0,
      child: Padding(
        padding: padding.copyWith(left: (padding.left - width).clamp(0, padding.left)),
        child: Container(
          height: double.infinity,
          color: Theme.of(context).colorScheme.surface,
          child: _CustomKeyboardView(
            controller: widget.controller,
            onChanged: widget.onChanged,
            onClose: widget.onClose,
            keyboardType: widget.inputType,
            keyboardActionType: widget.inputAction,
            searchQuery: widget.searchQuery,
          ),
        ),
      ),
    );
  }
}

class _CustomKeyboardView extends StatefulWidget {
  final TextEditingController controller;
  final TextInputAction? keyboardActionType;
  final TextInputType? keyboardType;

  final VoidCallback onChanged;
  final VoidCallback onClose;
  final FutureOr<List<String>> Function(String query)? searchQuery;

  const _CustomKeyboardView({
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.keyboardActionType,
    this.keyboardType,
    this.searchQuery,
  });

  @override
  State<_CustomKeyboardView> createState() => _CustomKeyboardViewState();
}

class _CustomKeyboardViewState extends State<_CustomKeyboardView> {
  final FocusScopeNode scope = FocusScopeNode();

  ValueNotifier<List<String>> searchQueryResults = ValueNotifier([]);

  final FocusNode internalTextField = FocusNode();
  final FocusNode keyboardOpenFocusNode = FocusNode();

  TextEditingController get controller => widget.controller;

  /// Where the keys type: the controller's caret, or the end of the text
  /// when it has none.
  int get cursor {
    final offset = controller.selection.baseOffset;
    return offset < 0 || offset > controller.text.length ? controller.text.length : offset;
  }

  void _edit(String text, int newCursor) {
    setState(() {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: newCursor.clamp(0, text.length)),
      );
    });
    widget.onChanged();
    startUpdate(controller.text);
  }

  void insert(String value) {
    final text = controller.text;
    final at = cursor;
    _edit(text.substring(0, at) + value + text.substring(at), at + value.length);
  }

  void backspace() {
    final text = controller.text;
    final at = cursor;
    if (at == 0) return;
    _edit(text.substring(0, at - 1) + text.substring(at), at - 1);
  }

  void moveCursor(int by) {
    setState(() {
      controller.selection = TextSelection.collapsed(offset: (cursor + by).clamp(0, controller.text.length));
    });
  }

  Future<void> startUpdate(String text) async {
    final query = widget.controller.text;
    final newValues = await widget.searchQuery?.call(query) ?? [];
    // Answers can come back in any order. One for text that has changed since
    // is for a search nobody is looking at any more.
    if (!mounted || widget.controller.text != query) return;
    searchQueryResults.value = newValues;
  }

  @override
  void initState() {
    super.initState();
    internalTextField.addListener(_focusChanged);
    WidgetsBinding.instance.addPostFrameCallback((value) {
      startUpdate(widget.controller.text);
    });
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    internalTextField.removeListener(_focusChanged);
    scope.dispose();
    internalTextField.dispose();
    keyboardOpenFocusNode.dispose();
    searchQueryResults.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!scope.hasFocus) {
      scope.requestFocus();
    }
    final obscure = widget.keyboardType == TextInputType.visiblePassword;
    final textStyle = Theme.of(context).textTheme.titleLarge;
    return FocusScope(
      node: scope,
      autofocus: true,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            ExcludeFocusTraversal(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  // The device keyboard types into a real field, which is
                  // always there to be focused; until it is, the keys here
                  // type at a caret drawn over it.
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Opacity(
                        opacity: internalTextField.hasFocus ? 1 : 0,
                        child: TextField(
                          focusNode: internalTextField,
                          controller: widget.controller,
                          showCursor: true,
                          keyboardType: widget.keyboardType,
                          textInputAction: widget.keyboardActionType,
                          obscureText: obscure,
                          onChanged: (value) {
                            setState(() {
                              widget.onChanged();
                              startUpdate(value);
                            });
                          },
                          onSubmitted: (value) {
                            internalTextField.unfocus();
                            keyboardOpenFocusNode.requestFocus();
                            setState(() {
                              widget.onChanged();
                              startUpdate(value);
                            });
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: textStyle,
                        ),
                      ),
                      if (!internalTextField.hasFocus)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _CaretText(
                              text: obscure ? '•' * controller.text.length : controller.text,
                              cursor: cursor,
                              style: textStyle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.searchQuery != null)
              ValueListenableBuilder(
                valueListenable: searchQueryResults,
                builder: (context, values, child) => _SearchResults(
                  results: values,
                  query: widget.controller.text,
                  onTap: (value) {
                    widget.controller.text = value;
                    widget.onChanged();
                    widget.onClose();
                  },
                ),
              ),
            Flexible(
              child: AlphaNumericKeyboard(
                // Every key tells the field, as typing on a real keyboard
                // does: a page that filters as it is typed into - Settings -
                // showed nothing until the keyboard closed.
                onCharacter: insert,
                keyboardType: widget.keyboardType ?? TextInputType.name,
                keyboardActionType: widget.keyboardActionType ?? TextInputAction.done,
                onBackspace: backspace,
                onCursor: moveCursor,
                onClear: () => _edit('', 0),
                onDone: widget.onClose,
              ),
            ),
            Center(
              child: TextButton.icon(
                focusNode: keyboardOpenFocusNode,
                onPressed: () => internalTextField.requestFocus(),
                icon: const Icon(IconsaxPlusLinear.keyboard, size: 18),
                label: Text(context.localized.openImeKeyboard),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The text being typed, with the caret where the keys will type.
class _CaretText extends StatelessWidget {
  final String text;
  final int cursor;
  final TextStyle? style;
  const _CaretText({required this.text, required this.cursor, this.style});

  @override
  Widget build(BuildContext context) {
    final at = cursor.clamp(0, text.length);
    final height = (style?.fontSize ?? 22) * 1.2;
    // Text reads from the left; only once it is longer than the field does
    // it scroll, keeping its end - where typing happens - in view.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: at == text.length,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Align(alignment: Alignment.centerLeft, widthFactor: 1, child: _text(context, at, height)),
        ),
      ),
    );
  }

  Widget _text(BuildContext context, int at, double height) {
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, at)),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 2,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          TextSpan(text: text.substring(at)),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<String> results;
  final String query;
  final Function(String value) onTap;
  const _SearchResults({required this.results, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final minHeight = MediaQuery.sizeOf(context).height * 0.25;
    return AnimatedFadeSize(
      alignment: Alignment.topCenter,
      child: results.isNotEmpty && query.isNotEmpty
          ? ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  ...results.map(
                    (result) => FocusButton(
                      onTap: () => onTap(result),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            spacing: 8,
                            children: [
                              const Icon(IconsaxPlusLinear.arrow_right),
                              Flexible(
                                child: Text(
                                  result,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : SizedBox(
              height: minHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 8,
                children: [
                  const Icon(IconsaxPlusLinear.search_normal_1),
                  Text(context.localized.noResults, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
    );
  }
}

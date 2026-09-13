import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/screens/shared/detail_scaffold.dart';
import 'package:chudder/theme.dart';

class ThemeOverwrite extends ConsumerStatefulWidget {
  const ThemeOverwrite({
    super.key,
    this.image,
    this.color,
    required this.child,
  });

  final ImageProvider? image;
  final Color? color;
  final Widget Function(BuildContext) child;

  @override
  ConsumerState<ThemeOverwrite> createState() => _ThemeOverwriteState();
}

class _ThemeOverwriteState extends ConsumerState<ThemeOverwrite> {
  Color? _dominantColor;

  /// The theme last built and what it was built from.
  ///
  /// [ColorScheme.fromSeed] is a full HCT solve and [FladderTheme.theme] builds
  /// every component's style on top of the result. Both used to run in `build`,
  /// which is once per rebuild of the page underneath - and a window being
  /// dragged to a new size is a rebuild every frame.
  (Color?, Object?, Brightness, Color?)? _themeKey;
  ThemeData? _theme;

  @override
  void initState() {
    super.initState();
    if (widget.image != null) _fetchColor(widget.image!);
  }

  @override
  void didUpdateWidget(ThemeOverwrite old) {
    super.didUpdateWidget(old);
    if (widget.image != old.image) {
      _dominantColor = null;
      if (widget.image != null) _fetchColor(widget.image!);
    }
  }

  Future<void> _fetchColor(ImageProvider image) async {
    final color = await getDominantColor(image);
    if (!mounted || widget.image != image) return;
    setState(() => _dominantColor = color);
  }

  @override
  Widget build(BuildContext context) {
    final deriveColorFromItem = ref.watch(clientSettingsProvider.select((value) => value.deriveColorsFromItem));
    if (!deriveColorFromItem) return widget.child(context);

    final schemeVariant = ref.watch(clientSettingsProvider.select((value) => value.schemeVariant));
    final amoledBlack = ref.watch(clientSettingsProvider.select((value) => value.amoledBlack));
    final isDarkTheme = Theme.brightnessOf(context) == Brightness.dark;
    final effectiveColor = widget.image != null ? _dominantColor : widget.color;
    final amoledOverwrite = amoledBlack && isDarkTheme ? Colors.black : null;

    final brightness = Theme.brightnessOf(context);
    final key = (effectiveColor, schemeVariant, brightness, amoledOverwrite);

    // Only when one of the four things it is made of has actually changed.
    if (_themeKey != key || _theme == null) {
      final newColorScheme = effectiveColor != null
          ? ColorScheme.fromSeed(
              seedColor: effectiveColor,
              brightness: brightness,
              dynamicSchemeVariant: schemeVariant,
            )
          : null;

      _theme = newColorScheme != null
          ? FladderTheme.theme(newColorScheme, schemeVariant).copyWith(
              scaffoldBackgroundColor: amoledOverwrite,
              cardColor: amoledOverwrite,
              canvasColor: amoledOverwrite,
              colorScheme: newColorScheme.copyWith(
                surface: amoledOverwrite,
                surfaceContainerHighest: amoledOverwrite,
                surfaceContainerLow: amoledOverwrite,
              ),
            )
          : Theme.of(context).copyWith(
              scaffoldBackgroundColor: amoledOverwrite,
              cardColor: amoledOverwrite,
              canvasColor: amoledOverwrite,
            );
      _themeKey = key;
    }

    final themeData = _theme!;

    return Theme(
      data: themeData,
      child: Builder(builder: (context) => widget.child(context)),
    );
  }
}

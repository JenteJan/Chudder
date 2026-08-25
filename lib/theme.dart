import 'package:flutter/material.dart';

import 'package:chinese_font_library/chinese_font_library.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'package:fladder/theme/fonts.dart';
import 'package:fladder/util/custom_color_themes.dart';

ColorScheme? generateDynamicColourSchemes(ColorScheme? theme, DynamicSchemeVariant dynamicSchemeVariant) {
  if (theme == null) return null;
  var base = ColorScheme.fromSeed(
    seedColor: theme.primary,
    dynamicSchemeVariant: dynamicSchemeVariant,
    brightness: theme.brightness,
  );

  var newScheme = _insertAdditionalColours(base);

  return newScheme.harmonized();
}

ColorScheme _insertAdditionalColours(ColorScheme scheme) => scheme.copyWith(
      surface: scheme.surface,
      surfaceDim: scheme.surfaceDim,
      surfaceBright: scheme.surfaceBright,
      surfaceContainerLowest: scheme.surfaceContainerLowest,
      surfaceContainerLow: scheme.surfaceContainerLow,
      surfaceContainer: scheme.surfaceContainer,
      surfaceContainerHigh: scheme.surfaceContainerHigh,
      surfaceContainerHighest: scheme.surfaceContainerHighest,
    );

/// Folds a second brand colour into a scheme grown from the first.
///
/// Material would have an accent land on secondary and tertiary. This app asks
/// for those five times between them and for the container roles more than
/// sixty, so an accent confined to where Material intends it would never
/// actually be seen. It takes the container families too, which is where a
/// second colour shows up in this app: the selected navigation pill, the chips
/// on a detail page, filled tonal buttons.
///
/// Every role is lifted from a single accent-seeded scheme, so each colour
/// arrives with the `on` colour Material paired to it and contrast survives the
/// swap. Applied after harmonisation on purpose — harmonising drags colours
/// toward the primary, which is exactly what would mute the yellow.
ColorScheme applyAccent(ColorScheme base, Color accent, DynamicSchemeVariant variant) {
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: base.brightness,
    dynamicSchemeVariant: variant,
  );
  return base.copyWith(
    primaryContainer: scheme.primaryContainer,
    onPrimaryContainer: scheme.onPrimaryContainer,
    secondary: scheme.primary,
    onSecondary: scheme.onPrimary,
    secondaryContainer: scheme.primaryContainer,
    onSecondaryContainer: scheme.onPrimaryContainer,
    tertiary: scheme.primary,
    onTertiary: scheme.onPrimary,
    tertiaryContainer: scheme.primaryContainer,
    onTertiaryContainer: scheme.onPrimaryContainer,
  );
}

class FladderTheme {
  static RoundedRectangleBorder get smallShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  static RoundedRectangleBorder get defaultShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  static RoundedRectangleBorder get largeShape => RoundedRectangleBorder(borderRadius: BorderRadius.circular(32));

  /// Marks the item you are on, drawn around the picture rather than as a dot
  /// beside the label. The label is the last place the eye goes on a poster —
  /// a mark there is read after the thing it is marking, if at all.
  static BoxDecoration currentItemDecoration(BuildContext context) => BoxDecoration(
        borderRadius: FladderTheme.smallShape.borderRadius,
        border: Border.all(width: 3, color: Theme.of(context).colorScheme.primary),
      );

  static BoxDecoration get defaultPosterDecoration => BoxDecoration(
        borderRadius: FladderTheme.smallShape.borderRadius,
        border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
      );

  static ThemeData theme(
    ColorScheme? colorScheme,
    DynamicSchemeVariant dynamicSchemeVariant, {
    Color? accent,
  }) {
    final ColorScheme? generated = generateDynamicColourSchemes(colorScheme, dynamicSchemeVariant);
    final ColorScheme? scheme =
        generated != null && accent != null ? applyAccent(generated, accent, dynamicSchemeVariant) : generated;

    // What a focused button wears.
    //
    // In the accent rather than a container tone. It used to be drawn in
    // onPrimaryContainer, which is itself one of the shades buttons are filled
    // with - so on a tonal button the ring was very nearly the colour of the
    // thing it was meant to be marking out. The accent belongs to no button
    // fill, which is what makes it legible on all of them.
    final buttonSides = WidgetStateProperty.resolveWith(
      (states) {
        return BorderSide(
          width: 3,
          color:
              scheme?.primary.withValues(alpha: states.contains(WidgetState.focused) ? 1.0 : 0.0) ?? Colors.transparent,
        );
      },
    );

    // A filled button is already wearing the accent, so its ring is drawn in
    // the colour that sits on top of that instead. One ring colour cannot
    // contrast with every fill - a button whose fill is the ring's own colour
    // shows no ring at all - so each family gets the one that contrasts with
    // what it is filled with.
    final filledButtonSides = WidgetStateProperty.resolveWith(
      (states) {
        return BorderSide(
          width: 3,
          color: scheme?.onPrimary.withValues(alpha: states.contains(WidgetState.focused) ? 1.0 : 0.0) ??
              Colors.transparent,
        );
      },
    );

    // And the button itself takes on some of that colour, so focus reads even
    // where the ring runs against something of a similar tone.
    final focusTint = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.focused) ? scheme?.primary.withValues(alpha: 0.22) : null,
    );

    final textTheme = FladderFonts.rubikTextTheme(
      const TextTheme(),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      sliderTheme: SliderThemeData(
        trackHeight: 8,
        thumbColor: colorScheme?.onSurface,
        valueIndicatorColor: colorScheme?.primaryContainer,
        valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
        valueIndicatorTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme?.onPrimaryContainer,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 3,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: smallShape,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: FladderTheme.defaultShape.borderRadius),
        collapsedShape: RoundedRectangleBorder(borderRadius: FladderTheme.defaultShape.borderRadius),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme?.secondaryContainer,
        foregroundColor: scheme?.onSecondaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme?.secondary,
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(borderRadius: FladderTheme.defaultShape.borderRadius),
        elevation: 5,
        dismissDirection: DismissDirection.horizontal,
      ),
      tooltipTheme: TooltipThemeData(
        textAlign: TextAlign.center,
        waitDuration: const Duration(milliseconds: 500),
        textStyle: TextStyle(
          color: scheme?.onSurface,
        ),
        decoration: BoxDecoration(
          borderRadius: defaultShape.borderRadius,
          color: scheme?.surface,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check_rounded);
          }
          return null;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      navigationBarTheme: const NavigationBarThemeData(),
      dialogTheme: DialogThemeData(shape: defaultShape),
      scrollbarTheme: ScrollbarThemeData(
          radius: const Radius.circular(16),
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return colorScheme?.primary;
            }
            return null;
          })),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme?.surface,
      ),
      buttonTheme: ButtonThemeData(shape: defaultShape),
      chipTheme: ChipThemeData(
        side: BorderSide(width: 1, color: scheme?.onSurface.withValues(alpha: 0.05) ?? Colors.white),
        shape: defaultShape,
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: defaultShape,
        color: scheme?.secondaryContainer,
        iconColor: scheme?.onSecondaryContainer,
        surfaceTintColor: scheme?.onSecondaryContainer,
      ),
      listTileTheme: ListTileThemeData(
        shape: defaultShape,
      ),
      dividerTheme: DividerThemeData(
        indent: 6,
        endIndent: 6,
        color: scheme?.onSurface.withAlpha(30),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((state) {
            if (state.contains(WidgetState.selected)) {
              return scheme?.primaryContainer;
            }
            return scheme?.surfaceContainer;
          }),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 8, horizontal: 12)),
          elevation: const WidgetStatePropertyAll(5),
          side: const WidgetStatePropertyAll(BorderSide.none),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(smallShape),
          side: buttonSides,
          overlayColor: focusTint,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(smallShape),
          side: buttonSides,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(smallShape),
          side: filledButtonSides,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(smallShape),
          side: buttonSides,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(smallShape),
          side: buttonSides,
        ),
      ),
      textTheme: textTheme.copyWith(
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static ColorScheme defaultScheme(Brightness brightness) {
    return ColorScheme.fromSeed(seedColor: ColorThemes.fladder.color, brightness: brightness);
  }

  /// Apply Chinese system font to a light theme (for Windows, macOS, Android, iOS)
  static ThemeData applyChineseFontToTheme({
    required ThemeData lightTheme,
    required ThemeData darkTheme,
  }) {
    return lightTheme.copyWith(
      textTheme: lightTheme.textTheme.useSystemChineseFont(Brightness.light),
      primaryTextTheme: lightTheme.primaryTextTheme.useSystemChineseFont(
        Brightness.light,
      ),
    );
  }

  /// Apply Chinese system font to a dark theme (for Windows, macOS, Android, iOS)
  static ThemeData applyChineseFontToDarkTheme({required ThemeData darkTheme}) {
    return darkTheme.copyWith(
      textTheme: darkTheme.textTheme.useSystemChineseFont(Brightness.dark),
      primaryTextTheme: darkTheme.primaryTextTheme.useSystemChineseFont(
        Brightness.dark,
      ),
    );
  }
}

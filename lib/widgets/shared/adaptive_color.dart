import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:material_color_utilities/material_color_utilities.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/themes_data.dart';

class AdaptiveColor extends ConsumerStatefulWidget {
  final Widget Function(ThemeData dark, ThemeData light) child;
  const AdaptiveColor({required this.child, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => AdaptiveColorState();
}

class AdaptiveColorState extends ConsumerState<AdaptiveColor> with WidgetsBindingObserver {
  ColorScheme? _light;
  ColorScheme? _dark;

  // The type DynamicColorPlugin.getCorePalette hands out; material_color_utilities
  // has deprecated it, dynamic_color has not moved yet.
  // ignore: deprecated_member_use
  CorePalette? _corePalette;

  /// The last pair built, with what it was built from.
  ///
  /// Building a theme is six seed-colour schemes, each a tone-mapping pass
  /// through HCT space, and they were built on every rebuild of this widget
  /// whether or not anything they depend on had changed.
  (Object, ThemeData, ThemeData)? _built;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchColors();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchColors();
    }
  }

  Future<void> _fetchColors() async {
    try {
      final corePalette = await DynamicColorPlugin.getCorePalette();
      if (corePalette == _corePalette) {
        return;
      }
      _corePalette = corePalette;
      if (corePalette != null && mounted) {
        setState(() {
          _light = corePalette.toColorScheme(brightness: Brightness.light);
          _dark = corePalette.toColorScheme(brightness: Brightness.dark);
        });
        return;
      }
    } on PlatformException {
      if (kDebugMode) debugPrint('dynamic_color: Failed to obtain core palette.');
    }

    try {
      final accentColor = await DynamicColorPlugin.getAccentColor();
      if (accentColor != null && mounted) {
        setState(() {
          _light = ColorScheme.fromSeed(seedColor: accentColor, brightness: Brightness.light);
          _dark = ColorScheme.fromSeed(seedColor: accentColor, brightness: Brightness.dark);
        });
        return;
      }
    } on PlatformException {
      if (kDebugMode) debugPrint('dynamic_color: Failed to obtain accent color.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLinux = defaultTargetPlatform == TargetPlatform.linux;
    final themeColor = ref.watch(clientSettingsProvider.select((value) => value.themeColor));
    final schemeVariant = ref.watch(clientSettingsProvider.select((value) => value.schemeVariant));
    final singleColor = ref.watch(clientSettingsProvider.select((value) => value.singleColorTheme));
    // Only a chosen preset carries a second colour; a scheme handed to us by
    // the system is whatever the system decided it is.
    final accent = themeColor?.accentFor(singleColor: singleColor);

    final key = (themeColor, schemeVariant, singleColor, _light, _dark, isLinux);
    final built = _built;
    final ThemeData lightTheme;
    final ThemeData darkTheme;
    if (built != null && built.$1 == key) {
      lightTheme = built.$2;
      darkTheme = built.$3;
    } else {
      final baseLightTheme = themeColor == null
          ? FladderTheme.theme(_light ?? FladderTheme.defaultScheme(Brightness.light), schemeVariant)
          : FladderTheme.theme(themeColor.schemeLight, schemeVariant, accent: accent);

      final baseDarkTheme = themeColor == null
          ? FladderTheme.theme(_dark ?? FladderTheme.defaultScheme(Brightness.dark), schemeVariant)
          : FladderTheme.theme(themeColor.schemeDark, schemeVariant, accent: accent);

      // Apply fonts
      lightTheme = isLinux
          ? baseLightTheme
          : FladderTheme.applyChineseFontToTheme(lightTheme: baseLightTheme, darkTheme: baseDarkTheme);
      darkTheme = isLinux ? baseDarkTheme : FladderTheme.applyChineseFontToDarkTheme(darkTheme: baseDarkTheme);
      _built = (key, lightTheme, darkTheme);
    }

    return ThemesData(
      light: lightTheme,
      dark: darkTheme,
      child: widget.child(darkTheme, lightTheme),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The blue behind the wedge in the icon.
const kChudderBlue = Color(0xFF2E7BE9);

/// The wedge itself, sampled from the icon rather than guessed at.
const kChudderYellow = Color(0xFFFCBC41);

enum ColorThemes {
  fladder(
    name: 'Chudder',
    // Blue against the cheddar mark: complementary, so the logo reads as
    // deliberate contrast, and not the same orange upstream ships as its
    // default. Debug keeps the purple tell, like the grey dev launcher icon.
    color: kDebugMode ? Colors.purpleAccent : kChudderBlue,
    accent: kChudderYellow,
  ),
  chudderReversed(
    name: 'Chudder Reversed',
    // The same pair the other way round: cheese leads, blue answers it.
    color: kChudderYellow,
    accent: kChudderBlue,
  ),
  chudderBlue(
    name: 'Chudder Blue',
    color: kChudderBlue,
  ),
  chudderYellow(
    name: 'Chudder Yellow',
    color: kChudderYellow,
  ),
  deepOrange(
    name: 'Deep Orange',
    color: Colors.deepOrange,
  ),
  amber(
    name: 'Amber',
    color: Colors.amber,
  ),
  green(
    name: 'Green',
    color: Colors.green,
  ),
  lightGreen(
    name: 'Light Green',
    color: Colors.lightGreen,
  ),
  lime(
    name: 'Lime',
    color: Colors.lime,
  ),
  cyan(
    name: 'Cyan',
    color: Colors.cyan,
  ),
  blue(
    name: 'Blue',
    color: Colors.blue,
  ),
  lightBlue(
    name: 'Light Blue',
    color: Colors.lightBlue,
  ),
  indigo(
    name: 'Indigo',
    color: Colors.indigo,
  ),
  deepBlue(
    name: 'Deep Blue',
    color: Color.fromARGB(255, 1, 34, 94),
  ),
  brown(
    name: 'Brown',
    color: Colors.brown,
  ),
  purple(
    name: 'Purple',
    color: Colors.purple,
  ),
  deepPurple(
    name: 'Deep Purple',
    color: Colors.deepPurple,
  ),
  blueGrey(
    name: 'Blue Grey',
    color: Colors.blueGrey,
  ),
  ;

  const ColorThemes({
    required this.name,
    required this.color,
    this.accent,
  });

  final String name;
  final Color color;

  /// The second colour of a two-colour preset, or null where the preset is
  /// built on one colour alone.
  final Color? accent;

  bool get isDual => accent != null;

  /// What this preset's second colour should be once the single-colour setting
  /// has had its say. A two-colour preset asked to be one colour keeps its
  /// primary and drops the rest.
  Color? accentFor({required bool singleColor}) => singleColor ? null : accent;

  ColorScheme get schemeLight {
    return ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light);
  }

  ColorScheme get schemeDark {
    return ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ColorThemes {
  fladder(
    name: 'Chudder',
    // Blue against the cheddar mark: complementary, so the logo reads as
    // deliberate contrast, and not the same orange upstream ships as its
    // default. Debug keeps the purple tell, like the grey dev launcher icon.
    color: kDebugMode ? Colors.purpleAccent : Color(0xFF2E7BE9),
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
  });

  final String name;
  final Color color;

  ColorScheme get schemeLight {
    return ColorScheme.fromSeed(seedColor: color, brightness: Brightness.light);
  }

  ColorScheme get schemeDark {
    return ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark);
  }
}

import 'package:flutter/services.dart';

import 'package:fladder/models/settings/key_combinations.dart';

extension PlayerShortcutFiltering<T> on Map<T, KeyCombination> {
  /// The same shortcuts without the ones bound to a bare arrow key.
  ///
  /// At a keyboard the arrows are volume and seek, which is what anyone at a
  /// desk expects of them. On a remote they are the only way to get anywhere,
  /// and every handler that binds them runs before focus traversal does - so
  /// left bound to "seek back" means left can never move between the controls.
  ///
  /// Only bare arrows go. An arrow held with a modifier is still a shortcut,
  /// and a remote has no modifier to hold, so it can never mean navigation.
  Map<T, KeyCombination> withoutPlainArrows({bool when = true}) {
    if (!when) return this;
    return Map.fromEntries(entries.where((entry) => !entry.value.isPlainArrow));
  }
}

extension PlainArrowCombination on KeyCombination {
  bool get isPlainArrow {
    if (modifier != null) return false;
    return key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight;
  }
}

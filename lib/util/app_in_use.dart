import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Whether the app is the one in use: its window has the focus, or the
/// pointer is moving over it - a window on a second screen is used by mouse
/// without ever being clicked into. A window behind a game is still
/// "visible" to Flutter, so only this says that nobody is looking.
///
/// What moves by itself for show - banners turning, previews playing, the
/// home page refreshing - waits while this is false. Every turn of the banner
/// decoded a backdrop and redrew its layers: a spike of CPU and GPU every few
/// seconds, felt as a dropped frame in the game in front.
final ValueNotifier<bool> appInUse = _AppInUse();

/// How long a pointer that stopped moving over an unfocused window keeps it
/// in use. A pointer left resting on a card, under a game that took the
/// focus, must not keep its preview playing.
const Duration kPointerInUse = Duration(seconds: 10);

class _AppInUse extends ValueNotifier<bool> {
  _AppInUse() : super(_focused(WidgetsBinding.instance.lifecycleState)) {
    _focusedNow = value;
    _listener = AppLifecycleListener(onStateChange: (state) {
      _focusedNow = _focused(state);
      _update();
    });
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  // Kept for the life of the app.
  // ignore: unused_field
  late final AppLifecycleListener _listener;
  bool _focusedNow = true;
  bool _pointerNow = false;
  Timer? _pointerTimer;

  static bool _focused(AppLifecycleState? state) => state == null || state == AppLifecycleState.resumed;

  void _onPointer(PointerEvent event) {
    if (event is! PointerHoverEvent && event is! PointerMoveEvent && event is! PointerDownEvent) return;
    _pointerTimer?.cancel();
    _pointerTimer = Timer(kPointerInUse, () {
      _pointerNow = false;
      _update();
    });
    if (!_pointerNow) {
      _pointerNow = true;
      _update();
    }
  }

  void _update() => value = _focusedNow || _pointerNow;
}

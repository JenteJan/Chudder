import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Whether the browser's last step through its history went forward.
///
/// Flutter numbers every history entry it writes (`serialCount` in the
/// entry's state), so a step to a higher number is forward and one to a lower
/// number is back. The number of the entry the browser was on is kept from
/// every write and every step.
bool _lastStepWasForward = false;
int? _currentSerial;

/// Set from a step through the history until the app has written the page it
/// went to for it.
Timer? _afterStep;

int? _serialOf(JSAny? state) {
  if (state == null || !state.isA<JSObject>()) return null;
  final serial = (state as JSObject)['serialCount'];
  if (serial == null || !serial.isA<JSNumber>()) return null;
  return (serial as JSNumber).toDartInt;
}

/// Starts following the browser's history, so a step through it can be told
/// apart as back or forward ([lastWebHistoryStepWasForward]).
void installWebNavigationGuard() {
  final history = globalContext['history'] as JSObject;
  _currentSerial = _serialOf(history['state']);

  final replaceState = history['replaceState'] as JSFunction;
  final pushState = history['pushState'] as JSFunction;

  // Flutter writes its entries through these two; the state it passes carries
  // the entry's number.
  JSAny? wrappedReplace(JSAny? state, JSAny? title, JSAny? url) {
    _afterStep?.cancel();
    _afterStep = null;
    _currentSerial = _serialOf(state) ?? _currentSerial;
    return replaceState.callAsFunction(history, state, title, url);
  }

  JSAny? wrappedPush(JSAny? state, JSAny? title, JSAny? url) {
    final serial = _currentSerial;
    if (_afterStep != null && serial != null && state != null && state.isA<JSObject>()) {
      // The page the app went to for the browser's step, written onto the
      // entry the browser stepped to. Pushed, as Flutter does whenever the
      // address differs (two details pages: the one underneath loses its
      // ?id=), it threw away every entry ahead, and forward had nowhere left
      // to go. The entry keeps its own number, so the numbers still rise
      // along the history and the next step is still told apart.
      (state as JSObject)['serialCount'] = serial.toJS;
      return wrappedReplace(state, title, url);
    }
    _currentSerial = _serialOf(state) ?? _currentSerial;
    return pushState.callAsFunction(history, state, title, url);
  }

  history['replaceState'] = wrappedReplace.toJS;
  history['pushState'] = wrappedPush.toJS;

  void onStep(JSObject event) {
    final serial = _serialOf(event['state']);
    final previous = _currentSerial;
    _lastStepWasForward = serial != null && previous != null && serial > previous;
    _currentSerial = serial ?? _currentSerial;
    // The app answers the step within a frame or two; anything written after
    // this is the person going somewhere new.
    _afterStep?.cancel();
    _afterStep = Timer(const Duration(milliseconds: 1500), () => _afterStep = null);
  }

  // Capturing, so it runs before Flutter's own listener reacts to the step.
  globalContext.callMethod('addEventListener'.toJS, 'popstate'.toJS, onStep.toJS, true.toJS);
}

bool lastWebHistoryStepWasForward() => _lastStepWasForward;

/// One step back through the browser's history; the app follows it from the
/// step itself, so every way of going back takes the same road.
void webHistoryBack() => (globalContext['history'] as JSObject).callMethod('back'.toJS);

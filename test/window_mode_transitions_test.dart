@TestOn('windows')
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/widgets/full_screen_helpers/full_screen_wrapper.dart';

/// A window that behaves the way Windows and `window_manager` 0.5.1 do where
/// it matters here: a maximised window ignores new bounds, the plugin's own
/// full screen keeps a maximised window zoomed, and every call takes a moment,
/// so two changes that are not kept apart get the chance to interleave.
class _FakeWindow {
  static const display = Rect.fromLTWH(0, 0, 1920, 1080);

  Rect bounds = const Rect.fromLTWH(200, 100, 1400, 800);
  bool maximized = false;
  bool minimized = false;
  bool pluginFullScreen = false;
  bool frameless = false;
  final List<String> log = [];

  /// Calls in flight at once. Anything above one is two changes overlapping.
  int _inFlight = 0;
  int maxInFlight = 0;

  Rect get visible => pluginFullScreen ? display : (maximized ? const Rect.fromLTWH(0, 0, 1920, 1040) : bounds);

  Future<Object?> handle(MethodCall call) async {
    final mutating = !call.method.startsWith('is') && !call.method.startsWith('get');
    if (mutating) {
      log.add(call.method);
      _inFlight++;
      if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    }
    try {
      // A few turns of the event loop, without a timer the test clock would
      // have to account for.
      for (var i = 0; i < 3; i++) {
        await Future<void>.value();
      }
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'isFullScreen':
          return pluginFullScreen;
        case 'isMaximized':
          return maximized;
        case 'isMinimized':
          return minimized;
        case 'getBounds':
          final r = visible;
          return {'x': r.left, 'y': r.top, 'width': r.width, 'height': r.height};
        case 'setBounds':
          // SetWindowPos on a maximised window does nothing.
          if (maximized) return null;
          bounds = Rect.fromLTWH(
            (args['x'] as num).toDouble(),
            (args['y'] as num).toDouble(),
            (args['width'] as num).toDouble(),
            (args['height'] as num).toDouble(),
          );
          return null;
        case 'setFullScreen':
          pluginFullScreen = args['isFullScreen'] as bool;
          return null;
        case 'maximize':
          maximized = true;
          minimized = false;
          return null;
        case 'unmaximize':
          maximized = false;
          return null;
        case 'minimize':
          minimized = true;
          return null;
        case 'setAsFrameless':
          frameless = true;
          return null;
        case 'setTitleBarStyle':
          frameless = false;
          return null;
        default:
          return null;
      }
    } finally {
      if (mutating) _inFlight--;
    }
  }

  Future<Object?> handleScreens(MethodCall call) async {
    final screen = {
      'id': '1',
      'size': {'width': display.width, 'height': display.height},
      'visiblePosition': {'dx': 0.0, 'dy': 0.0},
      'visibleSize': {'width': 1920.0, 'height': 1040.0},
      'scaleFactor': 1.0,
    };
    return switch (call.method) {
      'getAllDisplays' => {
          'displays': [screen]
        },
      'getPrimaryDisplay' => screen,
      _ => null,
    };
  }
}

void main() {
  late _FakeWindow window;
  late WidgetRef ref;
  late ProviderContainer container;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pump();
  }

  WindowMode mode() => container.read(windowModeProvider);

  setUp(() {
    window = _FakeWindow();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), window.handle);
    messenger.setMockMethodCallHandler(
        const MethodChannel('dev.leanflutter.plugins/screen_retriever'), window.handleScreens);
  });

  Future<void> mount(WidgetTester tester) async {
    container = ProviderContainer();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, r, _) {
        ref = r;
        r.watch(windowModeProvider);
        return const SizedBox();
      }),
    ));
    await settle(tester);
  }

  tearDown(() async {
    // The helper's state is static: leave every test out of full screen.
    window.maximized = false;
    window.minimized = false;
  });

  testWidgets('normal -> full screen -> the player button -> back where it was', (tester) async {
    await mount(tester);
    expect(mode(), WindowMode.normal);
    final before = window.bounds;

    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    expect(mode(), WindowMode.fullScreen);
    expect(window.bounds, _FakeWindow.display);
    expect(window.frameless, isTrue);

    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    expect(mode(), WindowMode.normal);
    expect(window.bounds, before);
    expect(window.frameless, isFalse, reason: 'the resize border and title bar come back');
  });

  testWidgets('full screen -> the title bar maximise button only leaves full screen', (tester) async {
    await mount(tester);
    final before = window.bounds;
    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);

    await tester.runAsync(() => fullScreenHelper.toggleMaximized());
    await settle(tester);
    expect(mode(), WindowMode.normal);
    expect(window.maximized, isFalse);
    expect(window.bounds, before);
  });

  testWidgets('maximised -> full screen -> out comes back maximised', (tester) async {
    await mount(tester);
    await tester.runAsync(() => fullScreenHelper.toggleMaximized());
    await settle(tester);
    expect(mode(), WindowMode.maximized);

    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    expect(mode(), WindowMode.fullScreen);

    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    expect(mode(), WindowMode.maximized);
    expect(window.pluginFullScreen, isFalse);

    // And the maximise button still knows where it stands afterwards - the
    // plugin's own events stop after this round trip.
    await tester.runAsync(() => fullScreenHelper.toggleMaximized());
    await settle(tester);
    expect(mode(), WindowMode.normal);
  });

  testWidgets('full screen -> minimise leaves full screen first', (tester) async {
    await mount(tester);
    final before = window.bounds;
    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);

    await tester.runAsync(() => fullScreenHelper.minimize());
    await settle(tester);
    expect(mode(), WindowMode.minimized);
    expect(window.frameless, isFalse);
    expect(window.bounds, before);
  });

  testWidgets('presses that overlap run one after the other', (tester) async {
    await mount(tester);
    final before = window.bounds;
    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    window.log.clear();
    window.maxInFlight = 0;

    // The player button and the title bar button at once, the double click
    // on the picture landing on top: nothing waits for anything.
    await tester.runAsync(() => Future.wait([
          fullScreenHelper.toggleFullScreen(ref),
          fullScreenHelper.toggleMaximized(),
          fullScreenHelper.closeFullScreen(ref),
        ]));
    await settle(tester);

    expect(window.maxInFlight, 1, reason: 'no two window changes at once: ${window.log}');
    // Out of full screen first, all the way back, and only then maximised.
    expect(window.log.indexOf('maximize'), greaterThan(window.log.lastIndexOf('setBounds')));
    expect(mode(), WindowMode.maximized);
    await tester.runAsync(() => fullScreenHelper.toggleMaximized());
    await settle(tester);
    expect(window.bounds, before);
  });

  testWidgets('a change nobody asked us for is picked up from the view resizing', (tester) async {
    await mount(tester);
    expect(mode(), WindowMode.normal);

    // Win+Up: the window maximises without a word to the app.
    window.maximized = true;
    tester.binding.handleMetricsChanged();
    await settle(tester);
    expect(mode(), WindowMode.maximized);

    window.maximized = false;
    tester.binding.handleMetricsChanged();
    await settle(tester);
    expect(mode(), WindowMode.normal);
  });

  testWidgets('maximised behind our back while full screen still comes out at its old size', (tester) async {
    await mount(tester);
    final before = window.bounds;
    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);

    window.maximized = true; // Win+Up on the borderless window.
    await tester.runAsync(() => fullScreenHelper.toggleFullScreen(ref));
    await settle(tester);
    expect(window.maximized, isFalse);
    expect(window.bounds, before);
    expect(mode(), WindowMode.normal);
  });
}

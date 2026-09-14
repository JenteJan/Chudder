import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/video_player/components/flying_video.dart';
import 'package:chudder/screens/video_player/components/minimized_video_surfaces.dart';
import 'package:chudder/screens/video_player/video_player_route.dart';

const _video = Key('video');
const _window = Rect.fromLTWH(700, 400, 160, 90);

/// A 16:9 picture on a 1000x600 screen, contained: full width, letterboxed.
const _landed = Rect.fromLTRB(0, 18.75, 1000, 581.25);

Widget _player() => const FlyingVideo(
      videoSize: Size(1920, 1080),
      fit: BoxFit.contain,
      padding: EdgeInsets.zero,
      child: ColoredBox(key: _video, color: Colors.red),
    );

void main() {
  setUp(MinimizedVideoSurfaces.clear);

  /// Home with a "floating window" box at [_window] that is signed in as the
  /// surface on top - the thing the player shrinks back into.
  Future<NavigatorState> pumpHome(WidgetTester tester, {bool withSurface = false}) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final surface = GlobalKey();
    if (withSurface) MinimizedVideoSurfaces.register(surface, radius: 16);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Stack(
            children: [
              const Text('home'),
              Positioned.fromRect(rect: _window, child: SizedBox(key: surface)),
            ],
          ),
        ),
      ),
    );
    return tester.state<NavigatorState>(find.byType(Navigator));
  }

  Rect rectOf(WidgetTester tester) => tester.getRect(find.byKey(_video));

  /// The same rect to within rounding.
  Matcher isRect(Rect expected) => predicate<Rect>(
        (rect) =>
            (rect.left - expected.left).abs() < 1e-6 &&
            (rect.top - expected.top).abs() < 1e-6 &&
            (rect.right - expected.right).abs() < 1e-6 &&
            (rect.bottom - expected.bottom).abs() < 1e-6,
        'is $expected',
      );

  /// A pushed route spends its first frame offstage - the navigator measures
  /// heroes that way - so the first frame anyone sees is the second.
  Future<void> pumpFirstVisibleFrame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  double opacityOf(WidgetTester tester) =>
      tester.widget<Opacity>(find.ancestor(of: find.byKey(_video), matching: find.byType(Opacity))).opacity;

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.text('home', skipOffstage: false)));

  group('opening', () {
    testWidgets('grows out of the window it was opened from and lands on the fitted rect', (tester) async {
      final navigator = await pumpHome(tester);
      navigator.push(VideoPlayerRoute(
        from: const VideoSurfaceFrame(rect: _window, radius: 16),
        builder: (_) => _player(),
      ));
      await pumpFirstVisibleFrame(tester);
      // The first frame anyone sees is the window, exactly - nothing to blink.
      expect(rectOf(tester), isRect(_window));

      await tester.pump(const Duration(milliseconds: 200));
      final midway = rectOf(tester);
      expect(midway.width, greaterThan(_window.width));
      expect(midway.width, lessThan(_landed.width));
      expect(opacityOf(tester), 1);

      await tester.pumpAndSettle();
      expect(rectOf(tester), isRect(_landed));
    });

    testWidgets('keeps the page underneath still', (tester) async {
      final navigator = await pumpHome(tester);
      final home = ModalRoute.of(tester.element(find.text('home')))!;
      navigator.push(VideoPlayerRoute(
        from: const VideoSurfaceFrame(rect: _window, radius: 16),
        builder: (_) => _player(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(home.secondaryAnimation!.value, 0);
    });

    testWidgets('with nothing to grow out of, the picture is simply in place', (tester) async {
      final navigator = await pumpHome(tester);
      navigator.push(VideoPlayerRoute(builder: (_) => _player()));
      await pumpFirstVisibleFrame(tester);
      expect(rectOf(tester), isRect(_landed));
      await tester.pump(const Duration(milliseconds: 200));
      expect(rectOf(tester), isRect(_landed));
      await tester.pumpAndSettle();
    });
  });

  group('closing', () {
    Future<NavigatorState> openPlayer(WidgetTester tester, {required bool withSurface}) async {
      final navigator = await pumpHome(tester, withSurface: withSurface);
      navigator.push(VideoPlayerRoute(builder: (_) => _player()));
      await tester.pumpAndSettle();
      expect(rectOf(tester), isRect(_landed));
      return navigator;
    }

    testWidgets('shrinks back into the surface on top', (tester) async {
      final navigator = await openPlayer(tester, withSurface: true);
      container(tester).read(mediaPlaybackProvider.notifier).state =
          MediaPlaybackModel(state: VideoPlayerState.minimized);

      navigator.pop();
      await tester.pump();
      expect(rectOf(tester), isRect(_landed));

      await tester.pump(const Duration(milliseconds: 150));
      final midway = rectOf(tester);
      expect(midway.width, lessThan(_landed.width));
      expect(midway.width, greaterThan(_window.width));
      expect(opacityOf(tester), 1);

      await tester.pump(const Duration(milliseconds: 150));
      final nearlyThere = rectOf(tester);
      expect(nearlyThere.width, lessThan(midway.width));
      expect((nearlyThere.left - _window.left).abs(), lessThan(40));
      await tester.pumpAndSettle();
    });

    testWidgets('holds still while the surface it is heading for is still being laid out', (tester) async {
      final navigator = await openPlayer(tester, withSurface: false);
      container(tester).read(mediaPlaybackProvider.notifier).state =
          MediaPlaybackModel(state: VideoPlayerState.minimized);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(rectOf(tester), isRect(_landed));
      expect(opacityOf(tester), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('with nowhere to go - playback stopped - fades in place', (tester) async {
      final navigator = await openPlayer(tester, withSurface: false);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(rectOf(tester), isRect(_landed));
      expect(opacityOf(tester), lessThan(1));
      await tester.pumpAndSettle();
    });
  });

  group('in flight', () {
    testWidgets('is reported while the picture is on its way, both ways, and not after', (tester) async {
      final navigator = await pumpHome(tester, withSurface: true);
      bool inFlight() => container(tester).read(videoPictureInFlightProvider);
      expect(inFlight(), isFalse);

      navigator.push(VideoPlayerRoute(
        from: const VideoSurfaceFrame(rect: _window, radius: 16),
        builder: (_) => _player(),
      ));
      await pumpFirstVisibleFrame(tester);
      expect(inFlight(), isTrue);
      await tester.pumpAndSettle();
      expect(inFlight(), isFalse);

      container(tester).read(mediaPlaybackProvider.notifier).state =
          MediaPlaybackModel(state: VideoPlayerState.minimized);
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(inFlight(), isTrue);
      await tester.pumpAndSettle();
      expect(inFlight(), isFalse);
    });
  });

  group('settledRect', () {
    const area = Size(1000, 600);
    const wide = Size(1920, 1080);

    test('contain letterboxes, cover and fill take the area', () {
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, wide, BoxFit.contain), isRect(_landed));
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, wide, BoxFit.cover), Offset.zero & area);
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, wide, BoxFit.fill), Offset.zero & area);
    });

    test('none is the picture at its own size, scaleDown never bigger than that', () {
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, wide, BoxFit.none),
          const Rect.fromLTWH(-460, -240, 1920, 1080));
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, wide, BoxFit.scaleDown), isRect(_landed));
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, const Size(500, 300), BoxFit.scaleDown),
          const Rect.fromLTWH(250, 150, 500, 300));
    });

    test('keeps clear of the padding, and takes the whole area without a size', () {
      expect(FlyingVideo.settledRect(area, const EdgeInsets.symmetric(horizontal: 100), wide, BoxFit.contain),
          isRect(const Rect.fromLTRB(100, 75, 900, 525)));
      expect(FlyingVideo.settledRect(area, EdgeInsets.zero, null, BoxFit.contain), Offset.zero & area);
    });
  });
}

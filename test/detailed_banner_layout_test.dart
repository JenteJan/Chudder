// The detailed banner fits the window it is in: the words stand against the
// picture whatever the window's shape, and the header can be stepped by hand.

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/details_screens/components/overview_header.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';
import 'package:chudder/screens/shared/media/detailed_banner.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/util/poster_defaults.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';

MovieModel _movie(String id) => MovieModel(
      originalTitle: id,
      premiereDate: DateTime(2000),
      sortName: id,
      status: '',
      name: 'Film $id',
      id: id,
      overview: const OverviewModel(summary: 'A film about a film.', productionYear: 2000),
      parentId: null,
      playlistId: null,
      images: null,
      childCount: null,
      primaryRatio: null,
      userData: const UserData(),
      parentImages: null,
      mediaStreams: MediaStreamsModel(versionStreams: const []),
      canDownload: null,
      canDelete: null,
    );

Future<List<ItemBaseModel>> _pumpBanner(WidgetTester tester, Size window, {required InputDevice input}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Cards with no picture write their name on the placeholder, which in the
  // test font runs out of the card. Nothing under test.
  final onError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    onError?.call(details);
  };
  addTearDown(() => FlutterError.onError = onError);
  final selected = <ItemBaseModel>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveLayout(
          data: AdaptiveLayoutModel(
            viewSize: window.width < 600 ? ViewSize.phone : ViewSize.tablet,
            layoutMode: LayoutMode.single,
            inputDevice: input,
            platform: TargetPlatform.windows,
            isDesktop: true,
            posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
            controller: const {},
            sideBarWidth: 0,
            topBarHeight: 0,
            statusBarHeight: 0,
          ),
          child: FocusTraversalGroup(
            policy: GlobalFallbackTraversalPolicy(),
            child: Scaffold(
              body: SingleChildScrollView(
                child: DetailedBanner(
                  posters: List.generate(4, (i) => _movie('banner-$i')),
                  onSelect: selected.add,
                  label: 'Continue watching',
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return selected;
}

void main() {
  for (final window in const [Size(400, 850), Size(700, 1000), Size(800, 1200), Size(1000, 900), Size(1366, 768)]) {
    testWidgets('the words stand against the picture in a ${window.width.round()}x${window.height.round()} window',
        (tester) async {
      await _pumpBanner(tester, window, input: InputDevice.touch);
      // The banner's own picture is the first; the rest are the row's cards.
      final picture = tester.getRect(find.byType(WideCardImage).first);
      final facts = tester.getRect(find.byType(MetadataLabels));
      // Used to be hundreds of pixels of bare page in a tall window.
      expect(facts.top - picture.bottom, lessThan(110));
      // And the row the banner stands over is in sight without scrolling.
      final banner = tester.getRect(find.byType(DetailedBanner));
      expect(banner.bottom, lessThanOrEqualTo(window.height));
    });
  }

  testWidgets('under a mouse, the arrows step the header on and back', (tester) async {
    final selected = await _pumpBanner(tester, const Size(1366, 768), input: InputDevice.pointer);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(900, 150));
    addTearDown(mouse.removePointer);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The hero's arrows come before the row's own in the tree.
    await tester.tap(find.byIcon(IconsaxPlusLinear.arrow_right_3).first);
    await tester.pump();
    expect(selected.last.id, 'banner-1');

    await tester.tap(find.byIcon(IconsaxPlusLinear.arrow_left_1).first);
    await tester.pump();
    expect(selected.last.id, 'banner-0');

    // Back from the first is the last: a rotation has no ends.
    await tester.tap(find.byIcon(IconsaxPlusLinear.arrow_left_1).first);
    await tester.pump();
    expect(selected.last.id, 'banner-3');
  });

  testWidgets('a swipe across the picture is the next one', (tester) async {
    final selected = await _pumpBanner(tester, const Size(400, 850), input: InputDevice.touch);
    await tester.fling(find.byType(WideCardImage).first, const Offset(-200, 0), 1000, warnIfMissed: false);
    await tester.pump();
    expect(selected.last.id, 'banner-1');

    await tester.fling(find.byType(WideCardImage).first, const Offset(200, 0), 1000, warnIfMissed: false);
    await tester.pump();
    expect(selected.last.id, 'banner-0');
  });

  testWidgets('no arrows without a pointer', (tester) async {
    await _pumpBanner(tester, const Size(400, 850), input: InputDevice.touch);
    expect(find.byIcon(IconsaxPlusLinear.arrow_right_3), findsNothing);
  });
}

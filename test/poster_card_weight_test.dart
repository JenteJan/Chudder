import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/shared/media/poster_widget.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/util/poster_defaults.dart';

/// What a poster card in a grid is made of. A fling builds a row of them
/// every few frames, so what each one sets up for a hover, a selection or a
/// flight that never comes is paid for by the scroll.
AdaptiveLayoutModel _layout(ViewSize size) => AdaptiveLayoutModel(
      viewSize: size,
      layoutMode: LayoutMode.single,
      inputDevice: InputDevice.touch,
      platform: TargetPlatform.android,
      isDesktop: false,
      posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
      controller: const {},
      sideBarWidth: 0,
      topBarHeight: 0,
      statusBarHeight: 0,
    );

final _film = ItemBaseModel(
  name: 'A film',
  id: 'film',
  overview: const OverviewModel(),
  parentId: null,
  playlistId: null,
  images: ImagesData(
    primary: ImageData(path: '/nowhere/poster.png', key: 'film_primary', hash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj'),
  ),
  childCount: null,
  primaryRatio: null,
  userData: const UserData(),
  canDownload: null,
  canDelete: null,
  jellyType: BaseItemKind.movie,
);

Future<void> _pumpCard(WidgetTester tester, ViewSize size, {Widget? subTitle}) => tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AdaptiveLayout(
            data: _layout(size),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 120,
                  height: 220,
                  child: PosterWidget(poster: _film, subTitle: subTitle),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Finder _inCard(Type type) => find.descendant(of: find.byType(PosterWidget), matching: find.byType(type));

void main() {
  testWidgets('on a phone, where no poster waits on the detail page, the card is not a hero', (tester) async {
    await _pumpCard(tester, ViewSize.phone);
    expect(_inCard(Hero), findsNothing);
  });

  testWidgets('where the detail page has a poster to fly to, it is', (tester) async {
    await _pumpCard(tester, ViewSize.tablet);
    expect(_inCard(Hero), findsOneWidget);
  });

  testWidgets('a card left alone has no animation running and none waiting on a frame', (tester) async {
    await _pumpCard(tester, ViewSize.phone);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expect(_inCard(AnimatedContainer), findsNothing);
    expect(_inCard(TweenAnimationBuilder<double>), findsNothing);
    expect(_inCard(FadeInImage), findsNothing);
  });

  testWidgets('only the card itself can be selected, with or without a subtitle of the caller\'s', (tester) async {
    for (final subTitle in [null, TextButton(onPressed: () {}, child: const Text('more'))]) {
      await _pumpCard(tester, ViewSize.phone, subTitle: subTitle);
      final scope = FocusScope.of(tester.element(find.byType(PosterWidget)));
      final reachable = scope.traversalDescendants.toList();
      expect(reachable, hasLength(1), reason: subTitle == null ? 'no subtitle' : 'a subtitle with a button in it');
    }
  });
}

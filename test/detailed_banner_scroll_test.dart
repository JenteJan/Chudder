// Where the home page comes to rest as the selection moves down it on a pad.
//
// The detailed banner's row is the first row of the page and describes what
// is selected in it above itself, so selecting there shows the top of the
// page. Every row under it rests at the focus line like anywhere else.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/overview_model.dart';
import 'package:chudder/screens/shared/media/detailed_banner.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout_model.dart';
import 'package:chudder/util/poster_defaults.dart';
import 'package:chudder/widgets/navigation_scaffold/components/navigation_body.dart';
import 'package:chudder/widgets/shared/ensure_visible.dart';

const _window = Size(1000, 700);

MovieModel _movie(String id) => MovieModel(
      originalTitle: id,
      premiereDate: DateTime(2000),
      sortName: id,
      status: '',
      name: 'Film $id',
      id: id,
      overview: const OverviewModel(summary: 'A film about a film.'),
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

AdaptiveLayoutModel _layout(InputDevice input) => AdaptiveLayoutModel(
      viewSize: ViewSize.desktop,
      layoutMode: LayoutMode.dual,
      inputDevice: input,
      platform: TargetPlatform.windows,
      isDesktop: true,
      posterDefaults: const PosterDefaults(size: 350, ratio: 0.55),
      controller: const {},
      sideBarWidth: 0,
      topBarHeight: 0,
      statusBarHeight: 0,
    );

/// A home page: the banner, two rows under it, and plenty of page below.
Future<ScrollController> _pumpHome(WidgetTester tester, {InputDevice input = InputDevice.dPad}) async {
  tester.view.physicalSize = _window;
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
  final controller = ScrollController();
  addTearDown(controller.dispose);
  final banner = List.generate(4, (i) => _movie('banner-$i'));
  final second = List.generate(4, (i) => _movie('second-$i'));
  final third = List.generate(4, (i) => _movie('third-$i'));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AdaptiveLayout(
          data: _layout(input),
          child: FocusTraversalGroup(
            policy: GlobalFallbackTraversalPolicy(),
            child: Scaffold(
              body: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: DetailedBanner(
                      posters: banner,
                      onSelect: (_) {},
                      label: 'Continue watching',
                    ),
                  ),
                  SliverToBoxAdapter(child: PosterRow(label: 'Second', posters: second)),
                  SliverToBoxAdapter(child: PosterRow(label: 'Third', posters: third)),
                  const SliverToBoxAdapter(child: SizedBox(height: 3000)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _inBanner(BuildContext context) => context.findAncestorWidgetOfExactType<DetailedBanner>() != null;

/// The first card of the banner's row - a control, not the row's own node.
FocusNode _firstBannerCard() => FocusManager.instance.rootScope.traversalDescendants.firstWhere(
      (node) => node.context != null && _inBanner(node.context!) && node.traversalDescendants.isEmpty,
    );

/// Selects the banner's first card the way the page's own first focus does,
/// rather than by a press from nowhere, which is Flutter's choice to make.
Future<void> _selectBannerCard(WidgetTester tester) async {
  _firstBannerCard().requestFocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The row the selection is in, by its label.
String _focusedRow() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return 'nothing';
  if (_inBanner(context)) return 'banner';
  return context.findAncestorWidgetOfExactType<PosterRow>()?.label ?? '${context.widget.runtimeType}';
}

void main() {
  testWidgets('selecting in the banner row shows the top of the page, on a pad too', (tester) async {
    final controller = await _pumpHome(tester);
    // Scrolled away, as it is coming back up the page.
    controller.jumpTo(300);
    await tester.pump();

    await _selectBannerCard(tester);
    expect(_focusedRow(), 'banner');
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    // Along the row stays at the top.
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(_focusedRow(), 'banner');
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('the rows under the banner rest at the focus line', (tester) async {
    final controller = await _pumpHome(tester);
    await _selectBannerCard(tester);
    expect(_focusedRow(), 'banner');

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedRow(), 'Second');
    await tester.pumpAndSettle();
    final secondRow = tester.getRect(find.byWidgetPredicate((w) => w is PosterRow && w.label == 'Second'));
    // A little above centre - see [kTvFocusRest] - not the top of the page.
    expect(controller.offset, greaterThan(0));
    expect(secondRow.top, closeTo(kTvFocusRest * (_window.height - secondRow.height), 1));

    await _press(tester, LogicalKeyboardKey.arrowDown);
    expect(_focusedRow(), 'Third');
    await tester.pumpAndSettle();
    final thirdRow = tester.getRect(find.byWidgetPredicate((w) => w is PosterRow && w.label == 'Third'));
    expect(thirdRow.top, closeTo(kTvFocusRest * (_window.height - thirdRow.height), 1));

    // And back up to the banner is the top of the page again.
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    expect(_focusedRow(), 'banner');
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });
}

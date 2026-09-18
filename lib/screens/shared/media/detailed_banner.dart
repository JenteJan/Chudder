import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/screens/details_screens/components/overview_header.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/card_preview.dart';
import 'package:chudder/widgets/shared/custom_shader_mask.dart';

/// How long the banner stays on one item before moving on to the next.
const Duration kDetailedBannerInterval = Duration(seconds: 8);

/// How many of its items the banner rotates through. The row under it has
/// them all; the header only has to show what is there.
const int _rotationLimit = 10;

const Duration _crossfade = Duration(milliseconds: 600);

/// The banner narrower than this stands its picture over its words rather
/// than beside them.
const double _stackedBelow = 720;

/// What [HorizontalList] puts around a row's cards - its name, the gaps - and
/// what the banner puts around the row: the dots above it, the space under.
const double _rowChrome = 36 + 8 + 31 + 16;

class DetailedBanner extends ConsumerStatefulWidget {
  final List<ItemBaseModel> posters;
  final Function(ItemBaseModel selected) onSelect;

  /// The name of the row of [posters].
  final String label;

  const DetailedBanner({
    required this.posters,
    required this.onSelect,
    required this.label,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DetailedBannerState();
}

/// Where everything in the banner goes, for the room there is.
///
/// The banner used to be a fixed share of the screen's height with the picture
/// pinned to its top and the words to its bottom. That is right for exactly one
/// shape of window: on anything taller than it is wide the picture ended a
/// long way above the words, with the page's bare colour in between and the
/// fade that is there to set the words off fading into nothing at all.
///
/// So the height is an outcome now, not a given. The picture is sized from the
/// width, the words are put against the picture's faded edge, and the banner is
/// as tall as that comes to.
@immutable
class _BannerGeometry {
  const _BannerGeometry({
    required this.stacked,
    required this.pictureWidth,
    required this.pictureHeight,
    required this.pictureTop,
    required this.heroHeight,
    required this.headerTop,
    required this.headerWidth,
    required this.logoHeight,
    required this.arrowCentre,
    required this.backArrowLeft,
    required this.backArrowRight,
  });

  /// The picture across the top with the words centred under it - a phone, a
  /// narrow window - rather than the picture to the right of the words.
  final bool stacked;

  final double pictureWidth;

  /// The most the picture's box stands; beside the words it also stops at the
  /// banner's own bottom edge.
  final double pictureHeight;

  /// Above the banner's own top where the page has a bar lying over it.
  final double pictureTop;

  /// The part of the banner over the dots and the row: the picture to look at,
  /// and the words.
  final double heroHeight;

  /// Where in the hero the words may begin. They stand on its bottom edge and
  /// take what they need, the summary giving way first.
  final double headerTop;

  final double headerWidth;

  final double logoHeight;

  /// The arrows' height in the hero, and where the one that goes back stands.
  /// Over the words' heads the two are at the picture's two ends, as a row's
  /// are. Beside the words the left end is where the words are, so they stand
  /// together at the right one.
  final double arrowCentre;
  final double? backArrowLeft;
  final double? backArrowRight;

  factory _BannerGeometry.of({
    required double width,
    required Size screen,
    required double topPadding,
    required bool underAppBar,
    required double rowBlock,
    required double textScale,
  }) {
    final summaryLine = 14 * 1.45 * textScale;
    // Narrow, or taller than it is wide: beside the words, a picture that has
    // to fit across such a window is a small one, with the words all over it.
    if (width < _stackedBelow || width < screen.height * 0.9) {
      // Squarer the narrower it gets: a 16:9 strip across a phone is a
      // letterbox, and the same picture cropped towards square is a poster.
      final shape = lerpDouble(1.05, 16 / 9, ((width - 360) / (_stackedBelow - 360)).clamp(0.0, 1.0))!;
      // The bar over the page is see-through; the picture runs up under it.
      final bleed = underAppBar ? topPadding + 80 : 0.0;
      final pictureHeight = (width / shape).clamp(0.0, screen.height * 0.52);
      final visible = pictureHeight - bleed;
      final overlap = (pictureHeight * 0.26).clamp(56.0, 110.0);
      final logoHeight = (screen.height * 0.11).clamp(56.0, 96.0);
      final summaryLines = screen.height < 700 ? 2 : 3;
      // Held at what the fullest item needs, so that the rows under the banner
      // stay where they are as it goes from one item to the next.
      final headerHeight = logoHeight + (26 + 34 + 26) * textScale + 10 + summaryLines * summaryLine + 4;
      final heroHeight = visible - overlap + headerHeight + 12;
      final clearTop = underAppBar ? 0.0 : topPadding;
      return _BannerGeometry(
        stacked: true,
        pictureWidth: width,
        pictureHeight: pictureHeight,
        pictureTop: -bleed,
        heroHeight: heroHeight,
        headerTop: heroHeight - 12 - headerHeight,
        // Lines of a length that reads, however wide the picture over them.
        headerWidth: (width - 32).clamp(0.0, 560.0),
        logoHeight: logoHeight,
        arrowCentre: clearTop + (visible - overlap - clearTop) / 2,
        backArrowLeft: 16,
        backArrowRight: null,
      );
    }

    // A window taller than it is wide gets the picture right across; a wide
    // one keeps it to the right, clear of the words.
    final aspect = width / screen.height;
    final pictureWidth = width * lerpDouble(1.0, 0.85, ((aspect - 0.8) / 0.6).clamp(0.0, 1.0))!;
    final pictureHeight = pictureWidth / 1.8;
    // The row stands on the picture's lower third, and the whole banner leaves
    // the top of the next row in sight. Never less than the name, the facts
    // and a line or two need.
    final heroHeight = [
      pictureHeight * 0.67,
      screen.height * 0.9 - rowBlock,
    ].reduce((a, b) => a < b ? a : b).clamp(topPadding + 208 * textScale, double.infinity);
    final headerWidth = (width * 0.5).clamp(280.0, 640.0);
    return _BannerGeometry(
      stacked: false,
      pictureWidth: pictureWidth,
      pictureHeight: pictureHeight,
      pictureTop: 0,
      heroHeight: heroHeight,
      headerTop: topPadding + 8,
      headerWidth: headerWidth,
      logoHeight: (screen.height * 0.14).clamp(48.0, 110.0),
      arrowCentre: topPadding + (heroHeight - topPadding) / 2,
      backArrowLeft: null,
      backArrowRight: 16 + 48 + 4,
    );
  }
}

/// A header for one item at a time, over the row of them all.
///
/// The header moves on through the first few items by itself, and holds still
/// for as long as somebody is using the banner: the pointer is over it, the
/// selection is in its row, or a card there is playing its preview. Picking a
/// card shows that card and starts the wait for the next one over; so does an
/// arrow under a mouse, or a swipe across the picture.
class _DetailedBannerState extends ConsumerState<DetailedBanner> {
  late ItemBaseModel _selected = widget.posters.first;
  Timer? _timer;
  Duration _shownFor = Duration.zero;
  bool _hovering = false;
  bool _rowFocused = false;
  late final CardPreviewController _previews = ref.read(cardPreviewProvider);

  /// Whether the pointer is over the hero - the picture and the words, not the
  /// row of cards under them. The arrows only exist while it is, the way a
  /// row's own do.
  final ValueNotifier<bool> _heroHovered = ValueNotifier(false);

  List<ItemBaseModel> get _rotation => widget.posters.take(_rotationLimit).toList();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), _tick);
  }

  @override
  void didUpdateWidget(covariant DetailedBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.posters.where((item) => item.id == _selected.id).firstOrNull;
    // A refresh hands over new copies; keep the one shown, with its new data.
    _selected = current ?? widget.posters.first;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _heroHovered.dispose();
    super.dispose();
  }

  /// Whether this page is the one on screen; a page over it, or another tab,
  /// turns tickers off.
  bool _onScreen = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onScreen = TickerMode.valuesOf(context).enabled;
  }

  bool get _held => _hovering || _heroHovered.value || _rowFocused || _previews.session.value != null || !_onScreen;

  void _tick(Timer timer) {
    if (!mounted) return;
    if (_rotation.length < 2 || _held) return;
    _shownFor += const Duration(milliseconds: 250);
    if (_shownFor < kDetailedBannerInterval) return;
    _step(1);
  }

  void _show(ItemBaseModel item) {
    _shownFor = Duration.zero;
    if (item.id == _selected.id) return;
    setState(() => _selected = item);
    widget.onSelect(item);
  }

  /// On by [direction] items, round the ends: a rotation has none.
  void _step(int direction) {
    final rotation = _rotation;
    if (rotation.length < 2) return;
    final index = rotation.indexWhere((item) => item.id == _selected.id);
    _show(rotation[(index + direction) % rotation.length]);
  }

  /// Brings the page back to its top.
  ///
  /// The banner's row is the page's first row, and the header it describes
  /// stands above it. Every other row comes to rest at the focus line, a
  /// little above centre, which for this one scrolled the header off the top:
  /// you could pick a card and never see what the banner had to say about it.
  /// Selecting a card in the row shows the banner whole, on a remote as much
  /// as under a pointer - so not [EnsureVisibleHelper.ensureVisible], which
  /// on a remote has one answer for every row.
  ///
  /// After the frame, so this is the last word on where the page is rather
  /// than the first: the row's own traversal settles the card sideways in the
  /// same pass.
  void _revealTop(BuildContext context) {
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
    if (position == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !position.hasPixels || position.pixels == position.minScrollExtent) return;
      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 275),
        curve: Curves.fastOutSlowIn,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPointer = AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer;
    // A phone's page has its bar of buttons lying over the top of it, see
    // [NestedSliverAppBar]; nothing wider does.
    final underAppBar = AdaptiveLayout.viewSizeOf(context) <= ViewSize.phone;
    final rowBlock = posterCardMetrics(
          context,
          ref,
          artRatio: kWideCardArtRatio,
          portraitRatio: kWideCardArtRatio,
        ).height +
        _rowChrome;
    final screen = MediaQuery.sizeOf(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final value = _selected;
    final rotation = _rotation;

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _BannerGeometry.of(
          width: constraints.maxWidth,
          screen: screen,
          topPadding: topPadding,
          underAppBar: underAppBar,
          rowBlock: rowBlock,
          textScale: textScale,
        );
        final picture = _BannerPicture(item: value, stacked: geometry.stacked);
        return Stack(
          // The picture runs up under a phone's bar, out of the banner's box.
          clipBehavior: Clip.none,
          children: [
            if (geometry.stacked)
              Positioned(
                top: geometry.pictureTop,
                left: 0,
                right: 0,
                height: geometry.pictureHeight,
                child: picture,
              )
            else
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                width: geometry.pictureWidth,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: geometry.pictureHeight),
                    child: SizedBox.expand(child: picture),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(context, geometry, value, showArrows: hasPointer && rotation.length > 1),
                if (rotation.length > 1)
                  ExcludeFocus(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      // Under the header, and lined up the way the header is.
                      child: Align(
                        alignment: geometry.stacked ? Alignment.center : Alignment.centerLeft,
                        child: _PageDots(
                          count: rotation.length,
                          current: rotation.indexWhere((item) => item.id == value.id),
                          onTap: (index) => _show(rotation[index]),
                        ),
                      ),
                    ),
                  ),
                // Held while the row is being looked through - under the
                // pointer, or holding the selection.
                MouseRegion(
                  onEnter: (_) => _hovering = true,
                  onExit: (_) => _hovering = false,
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onFocusChange: (focused) => _rowFocused = focused,
                    child: Builder(builder: (context) {
                      return FocusProvider(
                        autoFocus: true,
                        child: PosterRow(
                          label: widget.label,
                          wideArt: true,
                          posters: widget.posters,
                          onFocused: (poster) {
                            _revealTop(context);
                            _show(poster);
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ],
        );
      },
    );
  }

  /// The part of the banner that is about one item: room to see its picture,
  /// the words about it, and the ways of getting to the next one by hand.
  Widget _hero(BuildContext context, _BannerGeometry geometry, ItemBaseModel value, {required bool showArrows}) {
    final stacked = geometry.stacked;
    return ExcludeFocus(
      child: MouseRegion(
        onEnter: (_) => _heroHovered.value = true,
        onExit: (_) => _heroHovered.value = false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // A swipe across the picture is the next one, or the one before. The
          // page only scrolls up and down, so the two never want the same drag.
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity.abs() < 200) return;
            final forwards = Directionality.of(context) == TextDirection.ltr ? velocity < 0 : velocity > 0;
            _step(forwards ? 1 : -1);
          },
          child: SizedBox(
            height: geometry.heroHeight,
            child: Stack(
              children: [
                Positioned(
                  top: geometry.headerTop,
                  left: 16,
                  right: stacked ? 16 : null,
                  width: stacked ? null : geometry.headerWidth,
                  bottom: 12,
                  child: AnimatedSwitcher(
                    duration: _crossfade,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, if (current != null) current],
                    ),
                    child: Align(
                      key: ValueKey(value.id),
                      alignment: stacked ? Alignment.bottomCenter : Alignment.bottomLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: geometry.headerWidth),
                        child: _BannerHeader(
                          item: value,
                          centered: stacked,
                          logoHeight: geometry.logoHeight,
                        ),
                      ),
                    ),
                  ),
                ),
                if (showArrows) ...[
                  _StepArrow(
                    left: geometry.backArrowLeft,
                    right: geometry.backArrowRight,
                    centre: geometry.arrowCentre,
                    icon: IconsaxPlusLinear.arrow_left_1,
                    shown: _heroHovered,
                    onTap: () => _step(-1),
                  ),
                  _StepArrow(
                    right: 16,
                    centre: geometry.arrowCentre,
                    icon: IconsaxPlusLinear.arrow_right_3,
                    shown: _heroHovered,
                    onTap: () => _step(1),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The item's picture, crossfading to the next one's, and faded into the page
/// on the sides the words are on.
///
/// Something to read the header against. The words used to sit on whatever the
/// picture had at its edge - a face, a sky, a white shirt. The page's own
/// colour runs in over the picture from the side the words are on, thinning to
/// nothing where the picture is left to itself. Inside the mask, so it is
/// faded out at the picture's edges exactly as the picture is and never reaches
/// the page: laid over the whole banner it ended in a hard line wherever the
/// banner met the page's backdrop.
class _BannerPicture extends StatelessWidget {
  const _BannerPicture({required this.item, required this.stacked});

  final ItemBaseModel item;

  /// Over the words, which want its bottom edge faded; rather than beside
  /// them, which wants the left one and the bottom both.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final layers = Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: _crossfade,
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [...previous, if (current != null) current],
          ),
          child: WideCardImage(
            key: ValueKey(item.id),
            item: item,
            art: WideCardArt.large(item),
            decodeHeight: 1080,
            // Cut to another shape, keep the top: heads are up there.
            alignment: const Alignment(0, -0.5),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: stacked
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.4, 1.0],
                    colors: [surface.withValues(alpha: 0.0), surface.withValues(alpha: 0.65)],
                  )
                : LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.25, 0.58],
                    colors: [
                      surface.withValues(alpha: 0.96),
                      surface.withValues(alpha: 0.82),
                      surface.withValues(alpha: 0.0),
                    ],
                  ),
          ),
        ),
        if (!stacked)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.45, 1.0],
                colors: [surface.withValues(alpha: 0.0), surface.withValues(alpha: 0.85)],
              ),
            ),
          ),
      ],
    );
    return IgnorePointer(
      child: ExcludeFocus(
        child: stacked
            // The whole width, so only the bottom goes: the mask the wide
            // banner uses fades the left edge too, and on a phone that is a
            // third of the picture.
            ? ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.55, 1.0],
                  colors: [Colors.white, Colors.white, Colors.transparent],
                ).createShader(bounds),
                child: layers,
              )
            : CustomShaderMask(child: layers),
      ),
    );
  }
}

/// One of the two arrows over the hero, there while the pointer is: the same
/// button, and the same manners, as the ones at the ends of a row.
class _StepArrow extends StatelessWidget {
  const _StepArrow({
    this.left,
    this.right,
    required this.centre,
    required this.icon,
    required this.shown,
    required this.onTap,
  });

  final double? left;
  final double? right;
  final double centre;
  final IconData icon;
  final ValueNotifier<bool> shown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: centre - 24,
      height: 48,
      child: ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, show, child) => IgnorePointer(
          ignoring: !show,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: child,
          ),
        ),
        child: Center(
          child: IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
        ),
      ),
    );
  }
}

/// What the banner says about the item it is showing: its name, what it is,
/// the facts of it, and as much of its summary as there is room for.
///
/// Laid out from the bottom up in whatever height the hero has for it, so
/// nothing here ever runs on under the row. The summary is the one part that
/// gives: it takes the lines that fit and no more, and goes altogether where
/// there is no room for even one.
class _BannerHeader extends StatelessWidget {
  const _BannerHeader({required this.item, required this.centered, required this.logoHeight});

  final ItemBaseModel item;

  /// Whether the header stands in the middle of its width, as it does under
  /// the picture, rather than against the left.
  final bool centered;

  /// The most a logo stands.
  final double logoHeight;

  /// The most lines the summary takes, whatever the room.
  static const int _summaryLines = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localized = context.localized;
    final crossAxis = centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    final name = item.parentBaseModel.name;
    // The episode, the year, whatever says which one of the name this is.
    // Nothing when it says only the name again.
    final label = item.label(localized) ?? "";
    final subtitle = label.isNotEmpty && label != name ? label : null;
    final logo = item.tvPosterLogo;
    final genres = item.overview.genreItems.take(4).map((genre) => genre.name).join('  ·  ');

    final summaryStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onSurface.withValues(alpha: 0.88),
      height: 1.45,
    );
    final summary = item.overview.summary.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: crossAxis,
      children: [
        // The name as a picture where there is one, and never taller than a
        // few lines of text: the banner's logo is a heading, not a poster.
        if (logo != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: logoHeight, maxWidth: 360),
            child: FladderImage(
              image: logo,
              disableBlur: true,
              fit: BoxFit.contain,
              alignment: centered ? Alignment.bottomCenter : Alignment.bottomLeft,
              placeHolder: const SizedBox(height: 0),
              imageErrorBuilder: (context, object, stack) => _Title(name: name, textAlign: textAlign),
            ),
          )
        else
          _Title(name: name, textAlign: textAlign),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: MetadataLabels(
            officialRating: item.overview.parentalRating,
            productionYear: item.overview.productionYear?.toString(),
            runTime: item.overview.runTime,
            communityRating: item.overview.communityRating,
            alignment: centered ? WrapAlignment.center : WrapAlignment.start,
          ),
        ),
        if (genres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              genres,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ),
        if (summary.isNotEmpty && summaryStyle != null)
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final lineHeight = _lineHeight(context, summaryStyle);
                final lines = ((constraints.maxHeight - gap) / lineHeight).floor().clamp(0, _summaryLines);
                if (lines == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: gap),
                  child: Text(
                    summary,
                    textAlign: textAlign,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: summaryStyle,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// How tall one line of [style] comes out, at the reader's text size.
  static double _lineHeight(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.preferredLineHeight;
    painter.dispose();
    return height;
  }
}

/// The name written out, for an item without a logo.
class _Title extends StatelessWidget {
  const _Title({required this.name, required this.textAlign});

  final String name;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // A size to match the window: a heading on a big screen, a line on a
    // small one.
    final style = MediaQuery.sizeOf(context).width >= 1200 ? textTheme.headlineMedium : textTheme.headlineSmall;
    return Text(
      name,
      textAlign: textAlign,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(fontWeight: FontWeight.bold, height: 1.15),
    );
  }
}

/// Which of the banner's items is showing: a dot each, the current one drawn
/// out into a bar.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current, required this.onTap});

  final int count;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (index) {
        final active = index == current;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: active ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.9 : 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        );
      }),
    );
  }
}

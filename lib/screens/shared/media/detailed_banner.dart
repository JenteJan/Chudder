import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// A header for one item at a time, over the row of them all.
///
/// The header moves on through the first few items by itself, and holds still
/// for as long as somebody is using the banner: the pointer is over its row, the
/// selection is in its row, or a card there is playing its preview. Picking a
/// card shows that card and starts the wait for the next one over.
class _DetailedBannerState extends ConsumerState<DetailedBanner> {
  late ItemBaseModel _selected = widget.posters.first;
  Timer? _timer;
  Duration _shownFor = Duration.zero;
  bool _hovering = false;
  bool _rowFocused = false;
  late final CardPreviewController _previews = ref.read(cardPreviewProvider);

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

  bool get _held => _hovering || _rowFocused || _previews.session.value != null || !_onScreen;

  void _tick(Timer timer) {
    if (!mounted) return;
    final rotation = _rotation;
    if (rotation.length < 2 || _held) return;
    _shownFor += const Duration(milliseconds: 250);
    if (_shownFor < kDetailedBannerInterval) return;
    final index = rotation.indexWhere((item) => item.id == _selected.id);
    _show(rotation[(index + 1) % rotation.length]);
  }

  void _show(ItemBaseModel item) {
    _shownFor = Duration.zero;
    if (item.id == _selected.id) return;
    setState(() => _selected = item);
    widget.onSelect(item);
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
    final viewSize = AdaptiveLayout.viewSizeOf(context);
    final isPhone = viewSize <= ViewSize.phone;
    final phoneOffsetHeight = isPhone ? MediaQuery.paddingOf(context).top + 80 : 0.0;
    final value = _selected;
    final rotation = _rotation;
    final surface = Theme.of(context).colorScheme.surface;
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.topRight,
            child: ExcludeFocus(
              child: Transform.translate(
                offset: Offset(0, -phoneOffsetHeight),
                child: FractionallySizedBox(
                  widthFactor: 0.85,
                  child: AspectRatio(
                    aspectRatio: 1.8,
                    child: CustomShaderMask(
                      child: Stack(
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
                              key: ValueKey(value.id),
                              item: value,
                              art: WideCardArt.large(value),
                              decodeHeight: 1080,
                            ),
                          ),
                          // Something to read the header against. The words
                          // used to sit on whatever the picture had at its
                          // edge - a face, a sky, a white shirt. The page's
                          // own colour now runs in over the picture from the
                          // side the words are on, and up from under the row,
                          // thinning to nothing where the picture is left to
                          // itself. Inside the mask, so it is faded out at the
                          // picture's edges exactly as the picture is and
                          // never reaches the page: laid over the whole
                          // banner it ended in a hard line wherever the banner
                          // met the page's backdrop.
                          IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: isPhone
                                    ? LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: const [0.0, 0.45, 0.8],
                                        colors: [
                                          surface.withValues(alpha: 0.0),
                                          surface.withValues(alpha: 0.8),
                                          surface.withValues(alpha: 0.95),
                                        ],
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
                          ),
                          if (!isPhone)
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    stops: const [0.45, 1.0],
                                    colors: [
                                      surface.withValues(alpha: 0.0),
                                      surface.withValues(alpha: 0.85),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (isPhone ? MediaQuery.sizeOf(context).height * 0.75 : MediaQuery.sizeOf(context).height * 0.9)
                .clamp(20, 1000),
            maxWidth: double.infinity,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              const SizedBox(height: 32),
              Expanded(
                child: ExcludeFocus(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 12),
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: ConstrainedBox(
                        // Lines of a length that reads: about half the page on
                        // a desktop, and never so wide that the eye loses the
                        // start of the next one on a big screen.
                        constraints: BoxConstraints(
                          maxWidth:
                              isPhone ? double.infinity : (MediaQuery.sizeOf(context).width * 0.5).clamp(280, 640),
                        ),
                        child: AnimatedSwitcher(
                          duration: _crossfade,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.bottomLeft,
                            children: [...previous, if (current != null) current],
                          ),
                          child: _BannerHeader(
                            key: ValueKey(value.id),
                            item: value,
                            centered: isPhone,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (rotation.length > 1)
                ExcludeFocus(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    // Under the header, and lined up the way the header is.
                    child: Align(
                      alignment: isPhone ? Alignment.center : Alignment.centerLeft,
                      child: _PageDots(
                        count: rotation.length,
                        current: rotation.indexWhere((item) => item.id == value.id),
                        onTap: (index) => _show(rotation[index]),
                      ),
                    ),
                  ),
                ),
              // Held while the row is being looked through - under the
              // pointer, or holding the selection - not while the pointer
              // merely rests somewhere over the picture.
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
              const SizedBox(height: 16)
            ],
          ),
        ),
      ],
    );
  }
}

/// What the banner says about the item it is showing: its name, what it is,
/// the facts of it, and as much of its summary as there is room for.
///
/// Laid out from the bottom up in whatever height the banner has left over
/// after its row, so nothing here ever runs on under the row. The summary is
/// the one part that gives: it takes the lines that fit and no more, and goes
/// altogether on a window too short for even one.
class _BannerHeader extends StatelessWidget {
  const _BannerHeader({required this.item, required this.centered, super.key});

  final ItemBaseModel item;

  /// Whether the header stands in the middle of its width, as it does on a
  /// phone, rather than against the left.
  final bool centered;

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
            constraints: BoxConstraints(
              maxHeight: (MediaQuery.sizeOf(context).height * 0.14).clamp(48, 110),
              maxWidth: centered ? double.infinity : 360,
            ),
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

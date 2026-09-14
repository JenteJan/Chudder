import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/screens/details_screens/components/overview_header.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';
import 'package:chudder/screens/shared/media/poster_row.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/card_preview.dart';
import 'package:chudder/widgets/shared/custom_shader_mask.dart';
import 'package:chudder/widgets/shared/ensure_visible.dart';

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

  @override
  Widget build(BuildContext context) {
    final viewSize = AdaptiveLayout.viewSizeOf(context);
    final phoneOffsetHeight = viewSize <= ViewSize.phone ? MediaQuery.paddingOf(context).top + 80 : 0.0;
    final value = _selected;
    final rotation = _rotation;
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
                      child: AnimatedSwitcher(
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: (viewSize == ViewSize.phone
                    ? MediaQuery.sizeOf(context).height * 0.75
                    : MediaQuery.sizeOf(context).height * 0.9)
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
                    padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 4),
                    child: FractionallySizedBox(
                      widthFactor: viewSize <= ViewSize.phone ? 1.0 : 0.55,
                      child: AnimatedSwitcher(
                        duration: _crossfade,
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.bottomLeft,
                          children: [...previous, if (current != null) current],
                        ),
                        child: OverviewHeader(
                          key: ValueKey(value.id),
                          // The banner is the artwork, not a page under one.
                          belowArtwork: false,
                          name: value.parentBaseModel.name,
                          subTitle: value.label(context.localized),
                          image: value.getPosters,
                          logoAlignment: viewSize <= ViewSize.phone ? Alignment.center : Alignment.centerLeft,
                          summary: Text(
                            value.overview.summary,
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                            maxLines: viewSize == ViewSize.phone ? 5 : 3,
                          ),
                          productionYear: value.overview.productionYear?.toString(),
                          runTime: value.overview.runTime,
                          genres: value.overview.genreItems,
                          studios: value.overview.studios,
                          officialRating: value.overview.parentalRating,
                          communityRating: value.overview.communityRating,
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
                    child: _PageDots(
                      count: rotation.length,
                      current: rotation.indexWhere((item) => item.id == value.id),
                      onTap: (index) => _show(rotation[index]),
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
                          context.ensureVisible(
                            alignment: 10.0,
                          );
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

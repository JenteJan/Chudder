import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart' as jelly;
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/album_model.dart';
import 'package:chudder/models/items/artist_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/screens/shared/media/components/poster_image.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/item_base_model/play_item_helpers.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/clickable_text.dart';
import 'package:chudder/widgets/shared/focus_ring.dart';
import 'package:chudder/widgets/shared/item_actions.dart';

class PosterWidget extends ConsumerStatefulWidget {
  final ItemBaseModel poster;
  final Widget? subTitle;
  final bool? selected;
  final int maxLines;
  final double? aspectRatio;
  final bool inlineTitle;
  final bool underTitle;
  final Set<ItemActions> excludeActions;
  final List<ItemAction> otherActions;
  final Function(String id, UserData? newData)? onUserDataChanged;
  final Function(ItemBaseModel newItem)? onItemUpdated;
  final Function(ItemBaseModel oldItem)? onItemRemoved;
  final Function(VoidCallback action, ItemBaseModel item)? onPressed;
  final List<jelly.ImageType>? imagePriority;
  final Function(bool focus)? onFocusChanged;
  final bool showSyncStatus;

  /// A wide picture above the text instead of the poster; see [WideCardImage].
  final bool wideArt;

  const PosterWidget({
    required this.poster,
    this.subTitle,
    this.maxLines = 2,
    this.selected,
    this.aspectRatio,
    this.inlineTitle = false,
    this.underTitle = true,
    this.excludeActions = const {},
    this.otherActions = const [],
    this.onUserDataChanged,
    this.onItemUpdated,
    this.onItemRemoved,
    this.onPressed,
    this.imagePriority,
    this.onFocusChanged,
    this.showSyncStatus = false,
    this.wideArt = false,
    super.key,
  });

  @override
  ConsumerState<PosterWidget> createState() => _PosterWidgetState();
}

class _PosterWidgetState extends ConsumerState<PosterWidget> {
  /// Whether the card is hovered or selected, for the title to read along.
  final ValueNotifier<bool> _highlight = ValueNotifier(false);

  ItemBaseModel get poster => widget.poster;
  Widget? get subTitle => widget.subTitle;
  bool? get selected => widget.selected;
  int get maxLines => widget.maxLines;
  double? get aspectRatio => widget.aspectRatio;
  bool get inlineTitle => widget.inlineTitle;
  bool get underTitle => widget.underTitle;
  Set<ItemActions> get excludeActions => widget.excludeActions;
  List<ItemAction> get otherActions => widget.otherActions;
  Function(String id, UserData? newData)? get onUserDataChanged => widget.onUserDataChanged;
  Function(ItemBaseModel newItem)? get onItemUpdated => widget.onItemUpdated;
  Function(ItemBaseModel oldItem)? get onItemRemoved => widget.onItemRemoved;
  Function(VoidCallback action, ItemBaseModel item)? get onPressed => widget.onPressed;
  List<jelly.ImageType>? get imagePriority => widget.imagePriority;
  Function(bool focus)? get onFocusChanged => widget.onFocusChanged;
  bool get showSyncStatus => widget.showSyncStatus;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = 0.65;
    final subtitleClick = switch (poster) {
      AlbumModel album => () {
          album.parentBaseModel.navigateTo(context);
        },
      _ => null,
    };
    final showText = !inlineTitle && underTitle;
    Widget image = PosterImage(
      poster: poster,
      selected: selected,
      playVideo: (value) async => await poster.play(context, ref),
      inlineTitle: inlineTitle,
      excludeActions: excludeActions,
      otherActions: otherActions,
      onUserDataChanged: (newData) => onUserDataChanged?.call(poster.id, newData),
      onItemRemoved: onItemRemoved,
      onItemUpdated: onItemUpdated,
      onPressed: onPressed,
      imagePriority: imagePriority,
      onFocusChanged: onFocusChanged,
      onHighlightChanged: (value) => _highlight.value = value,
      showSyncStatus: showSyncStatus,
      wideArt: widget.wideArt,
    );
    // The picture keeps its own shape above the text. The card's shape is the
    // parent's to choose - a row's height, a grid's column - and the text is a
    // fixed height under a card that scales, so the picture's share was
    // whatever was left: at the default poster size that was a box wider than
    // a 2:3 poster, and cover-fit took a tenth off the top and bottom of every
    // one. Any slack the card has beyond the picture now sits beside or under
    // it instead of being cut out of it.
    if (showText) {
      // A card asking for thumb/backdrop art first wants the wide ratio those
      // images actually have - the same case primaryPosters used to cover
      // before imagePriority replaced it.
      final preferredType = imagePriority?.firstOrNull;
      final isWideArt = preferredType == jelly.ImageType.thumb || preferredType == jelly.ImageType.backdrop;
      image = Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
          aspectRatio: widget.wideArt
              ? kWideCardArtRatio
              : isWideArt
                  ? poster.type.imageAspectRatio
                  : poster.type.posterArtRatio,
          child: image,
        ),
      );
    }
    final card = Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(child: image),
        if (showText)
          ExcludeFocus(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: ClickableText(
                    onTap: AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer
                        ? () => switch (poster) {
                              ArtistModel artist => artist.navigateTo(context),
                              AlbumModel album => album.navigateTo(context),
                              _ => poster.parentBaseModel.navigateTo(context),
                            }
                        : null,
                    text: poster.title,
                    maxLines: 1,
                    highlight: _highlight,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // One line, not two. An episode says "S1 - E1: its name" here
                // rather than keeping a line for each half, and anything too
                // long for the card slides along while the card is hovered or
                // selected - see [MarqueeText], which [ClickableText] reaches
                // for on its own given a highlight and a single line.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (subTitle != null) ...[
                      Flexible(
                        child: subTitle!,
                      ),
                    ],
                    Flexible(
                      child: ClickableText(
                        onTap: subtitleClick,
                        opacity: opacity,
                        text: poster.subTextCombined(context.localized) ?? "",
                        maxLines: 1,
                        highlight: _highlight,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ].take(maxLines).toList(),
            ),
          ),
      ],
    );
    // Rows and grids shape the card to fit the picture whole, see
    // [posterCardRatioForHeight] and [posterCardRatioForWidth]. A caller that
    // gives no shape gets a card that fills whatever cell it is in.
    // The whole card lifts when selected on a pad, picture and title together,
    // so the picture never grows over its own title - see [FocusScale].
    return FocusScale(
      highlight: _highlight,
      child: aspectRatio == null ? card : AspectRatio(aspectRatio: aspectRatio!, child: card),
    );
  }
}

/// How tall the text [PosterWidget] draws under its picture is: the title in
/// titleMedium, the rest in titleSmall, [maxLines] in all. Measured from the
/// theme, so a card can be shaped around it before anything is laid out.
double posterTextBlockHeight(BuildContext context, {int maxLines = 2}) {
  final lines = maxLines.clamp(0, 3);
  if (lines == 0) return 0;
  final textTheme = Theme.of(context).textTheme;
  final baseStyle = DefaultTextStyle.of(context).style;
  final scaler = MediaQuery.textScalerOf(context);
  // Two text layouts per call, and it is called once per row every time the
  // dashboard rebuilds. The answer only changes with the theme or the text
  // scale, so it is kept for the next row that asks the same question.
  final memoKey = (textTheme.titleMedium, textTheme.titleSmall, baseStyle, scaler, lines);
  final memoized = _textBlockHeights[memoKey];
  if (memoized != null) return memoized;
  double lineHeight(TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: baseStyle.merge(style?.copyWith(fontWeight: FontWeight.bold))),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  final height = lineHeight(textTheme.titleMedium) + (lines - 1) * lineHeight(textTheme.titleSmall);
  if (_textBlockHeights.length > 32) _textBlockHeights.clear();
  return _textBlockHeights[memoKey] = height;
}

final Map<(TextStyle?, TextStyle?, TextStyle, TextScaler, int), double> _textBlockHeights = {};

/// The shape of a whole poster card [width] wide: a picture of [artRatio]
/// with [maxLines] of text under it. What a grid hands its delegate.
double posterCardRatioForWidth(
  BuildContext context, {
  required double artRatio,
  required double width,
  int maxLines = 2,
}) =>
    width / (width / artRatio + posterTextBlockHeight(context, maxLines: maxLines));

/// The same card, for a row [height] tall.
double posterCardRatioForHeight(
  BuildContext context, {
  required double artRatio,
  required double height,
  int maxLines = 2,
}) {
  final pictureHeight = (height - posterTextBlockHeight(context, maxLines: maxLines)).clamp(1.0, height);
  return pictureHeight * artRatio / height;
}

class PosterPlaceHolder extends StatelessWidget {
  final Function() onTap;
  final double aspectRatio;
  const PosterPlaceHolder({
    required this.onTap,
    required this.aspectRatio,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: FractionallySizedBox(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: FocusButton(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: FladderTheme.defaultShape.borderRadius,
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    const Icon(
                      IconsaxPlusLinear.more_square,
                      size: 46,
                    ),
                    Text(
                      context.localized.showMore,
                      style: Theme.of(context).textTheme.labelMedium,
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

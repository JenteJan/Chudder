import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:collection/collection.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/watched_state.dart';
import 'package:fladder/screens/details_screens/components/media_stream_information.dart';
import 'package:fladder/screens/shared/detail_scaffold.dart';
import 'package:fladder/screens/shared/media/components/media_header.dart';
import 'package:fladder/screens/shared/media/components/small_detail_widgets.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/humanize_duration.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/enum_selection.dart';
import 'package:fladder/widgets/shared/focus_row.dart';
import 'package:fladder/widgets/shared/item_actions.dart';

/// What the header's row of buttons stands at once the play button and the
/// stream pickers have arrived - reserved from the first frame so their arrival
/// does not move the page.
const double _actionRowHeight = 48;

/// One row of genre chips. Held open while a page is still fetching the item
/// whose genres they are, so that their arrival does not shove the page down.
const double _genreRowHeight = 36;

/// The line the name and original title share. Held open from the first frame,
/// because the original title is not known until the item has been fetched and
/// a line that appears later moves everything under it.
const double _titleRowHeight = 28;

class OverviewHeader extends ConsumerWidget {
  final String name;
  final double? minHeight;
  final bool disableheader;
  final ImagesData? image;
  final Widget? mainButton;
  final Widget? poster;
  final Widget? centerButtons;
  final EdgeInsets? padding;
  final String? subTitle;
  final String? originalTitle;
  final Alignment logoAlignment;
  final Function()? onTitleClicked;
  final List<SimpleLabel> additionalLabels;
  final String? productionYear;
  final Widget? summary;
  final Duration? runTime;
  final String? officialRating;
  final double? communityRating;
  final List<Studio> studios;
  final List<GenreItems> genres;
  final Function(GenreItems value)? onGenreClicked;
  final MediaStreamHelper? mediaStreamHelper;

  /// Whether to hold a genre row's worth of space while there are none yet.
  ///
  /// Genres belong to the show, not to the episode you opened it from, so they
  /// are the one thing in the header that cannot be known before its own
  /// request comes back. Set while that request is in flight, the row is the
  /// right size from the first frame and the genres simply appear in it.
  final bool reserveGenres;

  /// Whether the header sits below a detail page's artwork and should start
  /// where that artwork ends. The home banner draws its own artwork behind the
  /// header instead of above it, and passes false.
  final bool belowArtwork;

  const OverviewHeader({
    required this.name,
    this.minHeight,
    this.disableheader = false,
    this.image,
    this.mainButton,
    this.poster,
    this.centerButtons,
    this.padding,
    this.subTitle,
    this.originalTitle,
    this.logoAlignment = Alignment.bottomCenter,
    this.onTitleClicked,
    this.additionalLabels = const [],
    this.productionYear,
    this.summary,
    this.runTime,
    this.officialRating,
    this.communityRating,
    this.genres = const [],
    this.studios = const [],
    this.mediaStreamHelper,
    this.onGenreClicked,
    this.reserveGenres = false,
    this.belowArtwork = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
        );
    final subStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 18,
        );

    final fullHeight =
        (MediaQuery.sizeOf(context).height - (MediaQuery.paddingOf(context).top + 50)).clamp(50, 1250).toDouble();

    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;

    final crossAlignment = !isPhone ? CrossAxisAlignment.start : CrossAxisAlignment.stretch;

    final streamHeight = 43.0;

    // Roughly what one of these is once it has a resolution or a language in
    // it. Held from the start so that filling them in changes their labels
    // rather than the shape of the row they are in.
    final streamMinWidth = 124.0;

    // A logo means the name is a picture, and is not written anywhere.
    final hasLogo = image?.logo != null;
    final showsOriginalTitle =
        originalTitle != null && originalTitle!.isNotEmpty && name.toLowerCase() != originalTitle!.toLowerCase();

    final streamOptionsButtons = [
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: streamMinWidth, minHeight: streamHeight, maxHeight: streamHeight),
        child: EnumBox(
          onFocusChanged: (focused) {
            if (focused) {
              context.ensureVisible(alignment: 1.0);
            }
          },
          currentWidget: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(
                IconsaxPlusLinear.video_square,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              Text(
                mediaStreamHelper?.mediaStream.currentVersionStream?.detailedResolutionLabel ?? "",
              ),
            ],
          ),
          itemBuilder: (context) => mediaStreamHelper!.mediaStream.versionStreams
              .mapIndexed((index, e) => ItemActionButton(
                    selected: mediaStreamHelper!.mediaStream.currentVersionStream == e,
                    label: Text(e.name),
                    action: () {
                      final newItem = mediaStreamHelper!.mediaStream.copyWith(
                        versionStreamIndex: e.index,
                      );
                      mediaStreamHelper!.onItemChanged?.call(newItem);
                    },
                  ))
              .toList(),
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: streamMinWidth, minHeight: streamHeight, maxHeight: streamHeight),
        child: EnumBox(
          onFocusChanged: (focused) {
            if (focused) {
              context.ensureVisible(alignment: 1.0);
            }
          },
          currentWidget: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(
                IconsaxPlusLinear.audio_square,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              Text(
                mediaStreamHelper?.mediaStream.currentAudioStream?.shortTitle ?? "",
              ),
            ],
          ),
          itemBuilder: (context) => [AudioStreamModel.no(), ...mediaStreamHelper!.mediaStream.audioStreams]
              .mapIndexed((index, e) => ItemActionButton(
                    selected: mediaStreamHelper!.mediaStream.currentAudioStream == e,
                    label: Text(e.displayTitle),
                    action: () {
                      final newItem = mediaStreamHelper!.mediaStream.copyWith(
                        defaultAudioStreamIndex: e.index,
                      );
                      mediaStreamHelper!.onItemChanged?.call(newItem);
                    },
                  ))
              .toList(),
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(minWidth: streamMinWidth, minHeight: streamHeight, maxHeight: streamHeight),
        child: EnumBox(
          onFocusChanged: (focused) {
            if (focused) {
              context.ensureVisible(alignment: 1.0);
            }
          },
          currentWidget: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(
                IconsaxPlusLinear.subtitle,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              Text(
                (mediaStreamHelper?.mediaStream.currentSubStream?.shortTitle ?? context.localized.off).toUpperCase(),
              ),
            ],
          ),
          itemBuilder: (context) => [SubStreamModel.no(), ...mediaStreamHelper!.mediaStream.subStreams]
              .mapIndexed((index, e) => ItemActionButton(
                    selected: mediaStreamHelper!.mediaStream.currentSubStream == e,
                    label: Text(e.displayTitle),
                    action: () {
                      final newItem = mediaStreamHelper!.mediaStream.copyWith(
                        defaultSubStreamIndex: e.index,
                      );
                      mediaStreamHelper!.onItemChanged?.call(newItem);
                    },
                  ))
              .toList(),
        ),
      )
    ].withPositionProvider(context: context);

    // A phone bottom-aligned this inside a box nearly as tall as the screen, so
    // the title, the play button and the overview all opened below the fold. It
    // begins just inside the bottom of the artwork instead — far enough in to
    // land in the fade rather than under a hard edge — and the page reads
    // downwards from there.
    final offsetForArtwork = belowArtwork && isPhone && minHeight == null;

    // Desktop equivalent: the title/logo zone spans the artwork's height
    // (bottom-aligned, so they draw on top of the art) and the info section
    // starts right below the artwork's end. When the viewport is too short
    // for that, the sticky layout slides the whole block up over the artwork
    // by exactly the overflow — continuously, no mode jump — so the play
    // button always stays above the fold.
    final desktopArtwork = belowArtwork && !isPhone && minHeight == null;

    final titleSection = !isPhone
        ? Row(
            spacing: 16,
            mainAxisSize: MainAxisSize.min,
            // On the artwork the whole row hugs its bottom edge; the banner
            // path keeps the old vertical centering.
            crossAxisAlignment: desktopArtwork ? CrossAxisAlignment.end : CrossAxisAlignment.center,
            children: [
              if (poster != null) poster!,
              Flexible(
                child: ExcludeFocus(
                  child: Align(
                    alignment: desktopArtwork ? Alignment.bottomCenter : Alignment.center,
                    child: ConstrainedBox(
                      // Overlaid on the artwork the logo reads as a caption,
                      // not a poster — cap it well below MediaHeader's own
                      // 700px ceiling.
                      constraints: desktopArtwork
                          ? BoxConstraints(
                              maxWidth: (MediaQuery.sizeOf(context).width * 0.32).clamp(240.0, 440.0),
                              maxHeight: detailArtworkHeight(context) * 0.32,
                            )
                          : const BoxConstraints(),
                      child: MediaHeader(
                        name: name,
                        logo: image?.logo,
                        onTap: onTitleClicked,
                        alignment: logoAlignment,
                      ),
                    ),
                  ),
                ),
              )
            ],
          )
        : Column(
            spacing: 16,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (poster != null) poster!,
              ExcludeFocus(
                child: Center(
                  child: MediaHeader(
                    name: name,
                    logo: image?.logo,
                    onTap: onTitleClicked,
                    alignment: logoAlignment,
                  ),
                ),
              )
            ],
          );

    final infoChildren = <Widget>[
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAlignment,
        children: [
          // The item's name, with its original-language title beside it on the
          // same line when the two differ.
          //
          // Always drawn, and drawn from the name — which every page has before
          // it has fetched anything. The original title used to sit here on a
          // line of its own, with nothing to say what it was the original of,
          // and it appeared only once the item's own request came back: a line
          // that was not there while the page was being read and then pushed
          // everything under it down. Arriving into a line that already exists
          // costs no height at all.
          Flexible(
            child: ConstrainedBox(
              // Holds its line whether or not there is anything in it yet, so
              // an original title arriving with the item's own request lands in
              // a row that is already there.
              constraints: const BoxConstraints(minHeight: _titleRowHeight),
              child: SelectableText.rich(
                TextSpan(
                  children: [
                    // Only where the header above is a picture. Without a logo
                    // [MediaHeader] writes the name itself, and writing it
                    // again underneath is not a title, it is an echo.
                    if (hasLogo) TextSpan(text: name, style: mainStyle),
                    if (showsOriginalTitle)
                      TextSpan(
                        text: hasLogo ? '  ($originalTitle)' : originalTitle,
                        style: subStyle?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ),
          if (subTitle != null && name.toLowerCase() != subTitle!.toLowerCase())
            Flexible(
              child: SelectableText(
                subTitle ?? "",
                textAlign: TextAlign.center,
                style: mainStyle,
                maxLines: 1,
              ),
            ),
        ].addInBetween(const SizedBox(height: 4)),
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAlignment,
        spacing: 10,
        children: [
          MetadataLabels(
            officialRating: officialRating,
            productionYear: productionYear,
            runTime: runTime,
            communityRating: communityRating,
          ),
          if (genres.isNotEmpty || reserveGenres)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _genreRowHeight),
              child: Genres(
                genres: genres.take(6).toList(),
                onGenreClicked: onGenreClicked,
              ),
            ),
          if (additionalLabels.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              direction: Axis.horizontal,
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: additionalLabels,
            ),
        ],
      ),
      if (summary != null) summary!,
      if (AdaptiveLayout.viewSizeOf(context) <= ViewSize.phone)
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (mainButton != null) mainButton!,
            if (mediaStreamHelper != null)
              Center(
                child: FittedBox(
                  child: Row(
                    spacing: 4,
                    mainAxisSize: MainAxisSize.min,
                    children: streamOptionsButtons,
                  ),
                ),
              ),
            if (centerButtons != null) centerButtons!,
          ].addInBetween(
            Center(
              child: Container(
                width: 12,
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(64),
                  borderRadius: FladderTheme.smallShape.borderRadius,
                ),
              ),
            ),
          ),
        )
      else
        Flexible(
          child: FocusRow(
            ensureVisibleAlignment: 1.0,
            // Held at the height it will have once everything has arrived.
// The play button and the stream pickers are not known on the
// first frame, and a row that grows when they turn up pushes the
// whole page down under the reader.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _actionRowHeight),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    mainButton,
                    if (mediaStreamHelper != null)
                      Row(
                        spacing: 4,
                        mainAxisSize: MainAxisSize.min,
                        children: streamOptionsButtons,
                      ),
                    centerButtons,
                  ].nonNulls.toList().addInBetween(
                        Container(
                          width: 4,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(64),
                            borderRadius: FladderTheme.smallShape.borderRadius,
                          ),
                        ),
                      ),
                ),
              ),
            ),
          ),
        ),
    ];

    if (desktopArtwork) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: _StickyArtworkHeader(
          artworkHeight: detailArtworkHeight(context),
          crossAxisAlignment: crossAlignment,
          title: titleSection,
          children: infoChildren,
        ),
      );
    }

    return Padding(
      // Starts where the backdrop begins fading out rather than below it: the
      // bottom fifth of the artwork is a fade into the page, and leaving it
      // clear only pushed the logo and the play button down for nothing.
      padding: EdgeInsets.only(top: offsetForArtwork ? detailArtworkHeight(context) * 0.74 : 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: minHeight ?? (offsetForArtwork ? 0 : fullHeight),
        ),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: crossAlignment,
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              if (!isPhone) Flexible(child: titleSection) else titleSection,
              ...infoChildren,
            ],
          ),
        ),
      ),
    );
  }
}

class MetadataLabels extends StatelessWidget {
  final bool? favourite;
  final String? officialRating;
  final String? productionYear;
  final Duration? runTime;
  final double? communityRating;
  final WatchedState? playLabel;
  final List<Widget> additionalLabels;

  const MetadataLabels({
    this.favourite,
    this.officialRating,
    this.productionYear,
    this.runTime,
    this.communityRating,
    this.playLabel,
    this.additionalLabels = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final playState = playLabel;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      direction: Axis.horizontal,
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (officialRating != null)
          SimpleLabel(
            icon: null,
            label: Text(officialRating.toString()),
          ),
        if (productionYear != null)
          SimpleLabel(
            icon: IconsaxPlusBold.calendar,
            color: Theme.of(context).colorScheme.surfaceBright,
            label: SelectableText(
              productionYear.toString(),
              textAlign: TextAlign.center,
            ),
          ),
        if (runTime != null && (runTime?.inSeconds ?? 0) > 1)
          SimpleLabel(
            icon: IconsaxPlusBold.timer,
            color: Theme.of(context).colorScheme.surfaceBright,
            iconColor: Theme.of(context).colorScheme.onSurface,
            label: SelectableText(
              runTime.humanize.toString(),
              textAlign: TextAlign.center,
            ),
          ),
        if (communityRating != null && communityRating != 0.0)
          SimpleLabel(
            icon: IconsaxPlusBold.star_1,
            color: Theme.of(context).colorScheme.tertiaryContainer,
            iconColor: Theme.of(context).colorScheme.onTertiaryContainer,
            label: Text(
              communityRating?.toStringAsFixed(2) ?? "",
            ),
          ),
        if (favourite != null)
          SimpleLabel(
            icon: favourite == true ? IconsaxPlusBold.heart : IconsaxPlusLinear.heart,
            color: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.onError,
          ),
        if (playState case PartiallyPlayed(:final label))
          SimpleLabel(
            color: Theme.of(context).colorScheme.onPrimary,
            iconColor: Theme.of(context).colorScheme.primary,
            label: Text(label),
          )
        else if (playState case Played())
          SimpleLabel(
            icon: Icons.check_rounded,
            color: Theme.of(context).colorScheme.onPrimary,
            iconColor: Theme.of(context).colorScheme.primary,
          ),
        ...additionalLabels,
      ].addInBetween(CircleAvatar(
        radius: 3,
        backgroundColor: Theme.of(context).colorScheme.onSurface,
      )),
    );
  }
}

class SimpleLabel extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final Widget? label;
  final Color? color;
  final Color? iconColor;
  const SimpleLabel({
    this.icon,
    this.iconWidget,
    this.label,
    this.color,
    this.iconColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = (color ?? Theme.of(context).colorScheme.surfaceBright)
        .harmonizeWith(Theme.of(context).colorScheme.primaryContainer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: FladderTheme.smallShape.borderRadius,
        color: backgroundColor.withAlpha(200),
        border: Border.all(
          color: backgroundColor.withAlpha(255),
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: iconColor ?? Theme.of(context).colorScheme.onSurface,
            ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            if (icon != null)
              Icon(
                icon,
                size: 21,
                color: iconColor ?? Theme.of(context).colorScheme.onSurface,
              ),
            if (iconWidget != null) iconWidget!,
            if (label != null) label!
          ],
        ),
      ),
    );
  }
}

/// Reports its child's laid-out size after each frame, so [_StickyArtworkHeader]
/// can size the title zone from the real height of the info section.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(BuildContext context, _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_reported == newSize) return;
    _reported = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}

/// The desktop detail header: [title] pinned to the bottom of the artwork and
/// [children] (the info section — buttons, genres, summary) flowing right
/// below the artwork's end. When the viewport is too short for the info
/// section to fit below the art, the whole block slides up over the artwork
/// by exactly the overflow — continuously, so window resizes never cause a
/// layout jump — keeping the actions above the fold. With enough overlap the
/// info section's bottom lands on the fold, so the next page section starts
/// cleanly off screen.
class _StickyArtworkHeader extends StatefulWidget {
  const _StickyArtworkHeader({
    required this.artworkHeight,
    required this.crossAxisAlignment,
    required this.title,
    required this.children,
  });

  final double artworkHeight;
  final CrossAxisAlignment crossAxisAlignment;
  final Widget title;
  final List<Widget> children;

  @override
  State<_StickyArtworkHeader> createState() => _StickyArtworkHeaderState();
}

class _StickyArtworkHeaderState extends State<_StickyArtworkHeader> {
  static const _spacing = 12.0;

  /// Breathing room between the info section and whatever follows (or the
  /// fold, when the block is overlapping the artwork).
  static const _bottomPadding = 16.0;
  double _infoHeight = 0;

  /// How far the block must slide up over the artwork for the info section
  /// (plus bottom padding) to end at the fold. Zero while everything fits
  /// below the art; capped so a very long info section scrolls instead of
  /// burying the art entirely.
  double _overflowFor(double infoHeight) {
    final viewport = MediaQuery.sizeOf(context).height;
    final maxShift = widget.artworkHeight * 0.7;
    return (widget.artworkHeight + _spacing + infoHeight + _bottomPadding - viewport).clamp(0.0, maxShift);
  }

  @override
  Widget build(BuildContext context) {
    final overflow = _overflowFor(_infoHeight);
    return Padding(
      padding: const EdgeInsets.only(bottom: _bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: widget.crossAxisAlignment,
        spacing: _spacing,
        children: [
          SizedBox(
            height: (widget.artworkHeight - overflow).clamp(0.0, double.infinity),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: widget.crossAxisAlignment,
              children: [Flexible(child: widget.title)],
            ),
          ),
          _MeasureSize(
            onChange: (size) {
              if (!mounted || (size.height - _infoHeight).abs() < 0.5) return;
              // Only rebuild when the new height visibly moves the layout —
              // with no overlap active (the common case), a changed info
              // height changes nothing on screen and a relayout would be
              // wasted work every time the section reflows.
              final changesLayout = (_overflowFor(size.height) - _overflowFor(_infoHeight)).abs() >= 0.5;
              _infoHeight = size.height;
              if (changesLayout) setState(() {});
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: widget.crossAxisAlignment,
              spacing: _spacing,
              children: widget.children,
            ),
          ),
        ],
      ),
    );
  }
}

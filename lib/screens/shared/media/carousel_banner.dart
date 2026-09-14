import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/screens/details_screens/components/item_toggle_buttons.dart';
import 'package:chudder/screens/shared/media/banner_play_button.dart';
import 'package:chudder/screens/shared/media/components/wide_card_art.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/themes_data.dart';
import 'package:chudder/widgets/shared/card_preview.dart';
import 'package:chudder/widgets/shared/ensure_visible.dart';

class CarouselBanner extends ConsumerStatefulWidget {
  final PageController? controller;
  final List<ItemBaseModel> items;
  final double maxHeight;
  const CarouselBanner({
    this.controller,
    required this.items,
    this.maxHeight = 250,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _CarouselBannerState();
}

/// The shape of the picture inside a banner card. It used to be 2.1, which is
/// wider than any backdrop, so the top and bottom of every one was cropped off
/// — the pointed bits of a cowl among them. At the picture's own shape the
/// whole frame fits.
const double _bannerRatio = 16 / 9;

class _CarouselBannerState extends ConsumerState<CarouselBanner> {
  final carouselController = CarouselController();
  bool showControls = false;

  /// Which card is selected, per item, for its preview; see [CardPreview].
  final Map<String, PreviewSelection> _selections = {};

  PreviewSelection _selectionOf(ItemBaseModel item) => _selections.putIfAbsent(item.id, PreviewSelection.new);

  @override
  void dispose() {
    for (final selection in _selections.values) {
      selection.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parentContext = context;
    return MouseRegion(
      onEnter: (event) => setState(() => showControls = true),
      onExit: (event) => setState(() => showControls = false),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxExtent = (constraints.maxHeight * _bannerRatio).clamp(
              250.0,
              (MediaQuery.sizeOf(context).shortestSide * 0.75).clamp(251.0, double.maxFinite),
            );
            final border = BorderRadius.circular(18);
            final itemExtent = widget.items.length == 1 ? MediaQuery.sizeOf(context).width : maxExtent;
            // Height follows the width at a fixed shape. A card that could not
            // have the width it wanted — one item filling a narrow screen, or
            // the clamp above biting — gets shorter instead of keeping a
            // height its picture has to be stretched or cropped to fill.
            final itemHeight = math.min(constraints.maxHeight, itemExtent / _bannerRatio);

            return Padding(
              padding: EdgeInsets.only(top: AdaptiveLayout.of(context).isDesktop ? 6 : 10),
              child: SizedBox(
                height: itemHeight,
                child: Stack(
                  children: [
                    CarouselView(
                      elevation: 3,
                      shrinkExtent: 0,
                      controller: carouselController,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(borderRadius: border),
                      enableSplash: false,
                      itemExtent: itemExtent,
                      children: [
                        ...widget.items.mapIndexed(
                          (index, item) => LayoutBuilder(
                            builder: (context, constraints) {
                              final opacity = (constraints.maxWidth / maxExtent);
                              final selection = _selectionOf(item);
                              return FocusButton(
                                onTap: () => widget.items[index].navigateTo(context),
                                borderRadius: border,
                                onHover: (hovering) => selection.hovered = hovering,
                                onFocusChanged: (focused) {
                                  selection.focused = focused;
                                  if (focused) {
                                    parentContext.ensureVisible();
                                  }
                                },
                                onLongPress: AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer
                                    ? null
                                    : () {
                                        final poster = widget.items[index];
                                        showItemActionsSheet(
                                          context,
                                          ref,
                                          poster,
                                          actions: poster.generateActions(context, ref),
                                        );
                                      },
                                onSecondaryTapDown: AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch
                                    ? null
                                    : (details) async {
                                        final poster = widget.items[index];

                                        await showItemActionsSheet(
                                          context,
                                          ref,
                                          poster,
                                          actions: poster.generateActions(context, ref),
                                        );
                                      },
                                child: Stack(
                                  children: [
                                    CardPreview(
                                      item: item,
                                      active: selection.active,
                                      child: WideCardImage(
                                        item: item,
                                        // The title is written over the card, so
                                        // the backdrop rather than art with its own.
                                        art: WideCardArt.large(item),
                                        // Backdrops arrive at 2000px. Decoded whole
                                        // that is 16MB of pixels per card, for a
                                        // card a third of the window wide.
                                        decodeHeight: (itemHeight * MediaQuery.devicePixelRatioOf(context)).ceil(),
                                      ),
                                    ),
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomLeft,
                                          end: Alignment.topCenter,
                                          colors: [
                                            ThemesData.of(context)
                                                .dark
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: opacity.clamp(0, 1)),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0).copyWith(right: constraints.maxWidth * 0.2),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              maxLines: 2,
                                              softWrap: item.title.length > 25,
                                              overflow: TextOverflow.fade,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineMedium
                                                  ?.copyWith(color: Colors.white),
                                            ),
                                            if (item.label(context.localized) != null || item.subText != null)
                                              Text(
                                                item.label(context.localized) ?? item.subText ?? "",
                                                maxLines: 2,
                                                softWrap: false,
                                                overflow: TextOverflow.fade,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(color: Colors.white),
                                              ),
                                          ].addInBetween(const SizedBox(height: 4)),
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.1),
                                            width: 1.0,
                                          ),
                                          borderRadius: border,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                overlays: [
                                  ExcludeFocus(
                                    child: BannerPlayButton(item: widget.items[index]),
                                  ),
                                ],
                              );
                            },
                          ),
                        )
                      ],
                    ),
                    if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer)
                      ExcludeFocus(
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: showControls ? 1 : 0,
                          child: IgnorePointer(
                            ignoring: !showControls,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Align(
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton.filledTonal(
                                      onPressed: () {
                                        final currentPos = carouselController.position;
                                        carouselController.animateTo(currentPos.pixels - itemExtent,
                                            curve: Curves.easeInOutCubic, duration: const Duration(milliseconds: 250));
                                      },
                                      icon: const Icon(IconsaxPlusLinear.arrow_left_1),
                                    ),
                                    IconButton.filledTonal(
                                      onPressed: () {
                                        final currentPos = carouselController.position;
                                        carouselController.animateTo(currentPos.pixels + itemExtent,
                                            curve: Curves.easeInOutCubic, duration: const Duration(milliseconds: 250));
                                      },
                                      icon: const Icon(IconsaxPlusLinear.arrow_right_3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

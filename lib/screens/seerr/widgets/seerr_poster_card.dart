import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/providers/items/item_prefetch_provider.dart';
import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/seerr_user_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/seerr/widgets/seerr_request_popup.dart';
import 'package:fladder/seerr/seerr_models.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/clickable_text.dart';
import 'package:fladder/widgets/shared/focus_ring.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

class SeerrPosterCard extends ConsumerStatefulWidget {
  final SeerrDashboardPosterModel poster;

  /// The shape of the whole card, picture and text together.
  final double? aspectRatio;

  /// The shape of the picture itself. Given, the picture keeps it whatever the
  /// card's shape is, with any slack under the text rather than cut out of
  /// the artwork.
  final double? artRatio;
  final Function(bool value)? onFocusChanged;

  const SeerrPosterCard({
    required this.poster,
    this.aspectRatio,
    this.artRatio,
    this.onFocusChanged,
    super.key,
  });

  @override
  ConsumerState<SeerrPosterCard> createState() => _SeerrPosterCardState();
}

class _SeerrPosterCardState extends ConsumerState<SeerrPosterCard> {
  final ValueNotifier<bool> _highlight = ValueNotifier(false);
  bool _hovered = false;
  bool _focused = false;

  SeerrDashboardPosterModel get poster => widget.poster;
  double? get aspectRatio => widget.aspectRatio;
  Function(bool value)? get onFocusChanged => widget.onFocusChanged;

  void _updateHighlight() => _highlight.value = _hovered || _focused;

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = FladderTheme.smallShape.borderRadius;

    ImageData? image = poster.images.primary;
    image ??= poster.images.backDrop?.lastOrNull;

    final user = ref.watch(seerrUserProvider);
    final canRequest = user?.canRequestMedia(isTv: poster.type == SeerrMediaType.tvshow) ?? true;

    final baseItemModel = poster.itemBaseModel;

    void prefetchDetails() => ref.read(itemPrefetchProvider).prefetch(baseItemModel);

    void openRequestDetails() {
      context.router.push(
        SeerrDetailsRoute(
          mediaType: poster.type == SeerrMediaType.tvshow ? 'tvshow' : 'movie',
          tmdbId: poster.tmdbId,
          poster: poster,
        ),
      );
    }

    void handleTapAction() {
      if (baseItemModel != null) {
        baseItemModel.navigateTo(context);
      } else {
        openRequestDetails();
      }
    }

    final List<ItemAction> itemActions = [
      if (poster.hasDisplayStatus || poster.id.isNotEmpty)
        ItemActionButton(
          icon: const Icon(IconsaxPlusBold.folder_open),
          label: Text(context.localized.manageRequest),
          action: openRequestDetails,
        ),
      if (!poster.hasDisplayStatus && canRequest)
        ItemActionButton(
          icon: const Icon(IconsaxPlusBold.add),
          label: Text(context.localized.request),
          action: () => openSeerrRequestPopup(context, poster),
        ),
      if (baseItemModel != null)
        ItemActionButton(
          icon: Icon(baseItemModel.type.icon),
          label: Text(context.localized.showDetails),
          action: () => baseItemModel.navigateTo(context),
        ),
    ];

    Widget picture = FocusButton(
      onTap: handleTapAction,
      // Same as a library poster: ask for what the page will need while
      // the pointer is still here, so it opens complete.
      onHover: (hovering) {
        if (hovering) prefetchDetails();
        _hovered = hovering;
        _updateHighlight();
      },
      onFocusChanged: (focused) {
        if (focused) prefetchDetails();
        _focused = focused;
        _updateHighlight();
        onFocusChanged?.call(focused);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: Theme.of(context).colorScheme.surfaceContainer,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
        ),
        clipBehavior: Clip.hardEdge,
        child: FladderImage(
          image: image,
          placeHolder: Center(
            child: Text(
              poster.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
      ),
      onSecondaryTapDown: (details) => _showContextMenu(context, itemActions, ref, details.globalPosition),
      onLongPress: () => _showBottomSheet(context, itemActions, ref),
      focusedOverlays: [
        if (!poster.hasDisplayStatus && canRequest && AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => openSeerrRequestPopup(context, poster),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            IconsaxPlusBold.add_square,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 21,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.localized.request,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      overlays: [
        if (poster.hasDisplayStatus)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Container(
                decoration: BoxDecoration(
                  color: poster.displayStatusColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3.0),
                  child: Icon(
                    switch (poster.mediaStatus) {
                      SeerrMediaStatus.available => IconsaxPlusLinear.import_3,
                      _ => Icons.remove_rounded,
                    },
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                poster.type == SeerrMediaType.movie
                    ? context.localized.mediaTypeMovie(1)
                    : context.localized.mediaTypeSeries(1),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ),
        )
      ],
    );

    if (widget.artRatio != null) {
      picture = Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(aspectRatio: widget.artRatio!, child: picture),
      );
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(child: picture),
        ExcludeFocus(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClickableText(
                text: poster.title,
                maxLines: 1,
                highlight: _highlight,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              ClickableText(
                opacity: 0.65,
                text: poster.releaseYear?.toString() ?? "",
                maxLines: 1,
                highlight: _highlight,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );

    if (aspectRatio != null) {
      content = AspectRatio(aspectRatio: aspectRatio!, child: content);
    }

    // Lifted when selected on a pad, like a library poster - see [FocusScale].
    return FocusScale(highlight: _highlight, child: content);
  }

  void _showBottomSheet(BuildContext context, List<ItemAction> itemActions, WidgetRef ref) {
    showBottomSheetPill(
      context: context,
      content: (scrollContext, scrollController) => ListView(
        shrinkWrap: true,
        controller: scrollController,
        children: itemActions.listTileItems(scrollContext, useIcons: true),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, List<ItemAction> itemActions, WidgetRef ref, Offset globalPos) async {
    final position = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
    await showMenu(
      context: context,
      position: position,
      items: itemActions.popupMenuItems(
        useIcons: true,
      ),
    );
  }
}

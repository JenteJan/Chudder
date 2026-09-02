import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/sync/sync_provider_helpers.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/window_title_provider.dart';
import 'package:fladder/screens/syncing/sync_button.dart';
import 'package:fladder/screens/syncing/sync_item_details.dart';
import 'package:fladder/shaders/fade_edges.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/util/router_extension.dart';
import 'package:fladder/widgets/navigation_scaffold/components/settings_user_icon.dart';
import 'package:fladder/widgets/navigation_scaffold/components/playback_chrome_actions.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';
import 'package:fladder/widgets/shared/theme_overwrite.dart';

/// The smallest the artwork a detail page opens with is allowed to be.
///
/// The floor has to come down on a phone: 450 is half the screen there on its
/// own, so clamping to it undid the shrink entirely. It is low enough now that
/// it only catches a genuinely narrow window - a phone-width backdrop needs
/// more than this, and the band is measured from the backdrop.
double detailArtworkMinHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
  // Capped at the same ceiling its callers clamp against, not at the full
  // height. A window shorter than the minimum - a landscape phone - otherwise
  // produced a lower bound above the upper one, and clamp() throws on that.
  final ceiling = (size.height - 10).clamp(0.0, double.infinity);
  return (isPhone ? 200.0 : 450.0).clamp(0.0, ceiling).toDouble();
}

/// How much of the screen the artwork a detail page opens with covers.
///
/// Measured from the picture, not from the screen: backdrops are 16:9, so at a
/// given width that is all the room one needs. A share of the screen height
/// reserved more than the art could ever fill on a tall phone, and the strip
/// left over sat between the artwork and the title as dead space.
///
/// The header that sits under the artwork measures itself against this, so the
/// two have to agree on the number.
double detailArtworkHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
  if (isPhone) {
    // Plus the inset the artwork layer itself is drawn with, so the band ends
    // where the picture does.
    return (size.width / (16 / 9) + 20).clamp(detailArtworkMinHeight(context), size.height - 10).toDouble();
  }
  // Match the artwork actually on screen: backdrops are 16:9 and cover-fit
  // into this box, so sizing the box from the width means the header can sit
  // exactly on the art and the page continues right below it — instead of
  // reserving a whole screen the artwork never fills on wide windows.
  final artworkWidth = size.width - AdaptiveLayout.of(context).sideBarWidth / 1.5;
  return (artworkWidth / (16 / 9)).clamp(detailArtworkMinHeight(context), size.height - 10).toDouble();
}

Future<Color?> getDominantColor(ImageProvider imageProvider) async {
  final paletteGenerator = await PaletteGeneratorMaster.fromImageProvider(
    imageProvider,
    size: const Size(16, 16),
    maximumColorCount: 3,
  );

  return paletteGenerator.dominantColor?.color ?? paletteGenerator.vibrantColor?.color;
}

class DetailScaffold extends ConsumerStatefulWidget {
  final String label;
  final String? windowTitle;
  final ItemBaseModel? item;
  final List<ItemAction>? Function(BuildContext context)? actions;
  final Color? backgroundColor;
  final ImagesData? backDrops;
  final Function(BuildContext context, EdgeInsets padding) content;
  final Future<void> Function()? onRefresh;
  final bool posterFillsContent;
  final Color? dominantColor;
  const DetailScaffold({
    required this.label,
    this.windowTitle,
    this.item,
    this.actions,
    this.backgroundColor,
    required this.content,
    this.backDrops,
    this.onRefresh,
    this.posterFillsContent = false,
    this.dominantColor,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends ConsumerState<DetailScaffold> {
  late ItemBaseModel? item = widget.item;

  // Chosen up front rather than on the first rebuild. [updateImage] only ever
  // ran from didUpdateWidget, so a page drew its first frame with no artwork at
  // all and got it whenever something else happened to rebuild it - which was
  // the show's own fetch returning, and why the artwork arrived in step with
  // the genres instead of with everything else we already had.
  late List<ImageData>? lastImages = widget.backDrops?.backDrop;
  late ImageData? backgroundImage = widget.backDrops?.randomBackDrop;
  Color? dominantColor;

  ImageProvider? _lastRequestedImage;
  String? _lastColorImage;

  WindowTitleNotifier? _windowTitleNotifier;

  void _pushTitle() {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!isCurrent) return;

    final newTitle = widget.windowTitle ?? widget.item?.windowTitle(context.localized) ?? widget.label;
    if (newTitle.isNotEmpty) {
      ref.read(windowTitleProvider.notifier).updateTitle(this, newTitle);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _windowTitleNotifier = ref.read(windowTitleProvider.notifier);
    _pushTitle();
  }

  @override
  void dispose() {
    _windowTitleNotifier?.removeTitle(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DetailScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pushTitle();
    updateImage();
    _updateDominantColor();
    if (widget.backDrops != oldWidget.backDrops) {
      lastImages = widget.backDrops?.backDrop;
      // Keep the picture already on screen if the new set still holds it.
      // These are picked at random, and the page is handed a stand-in set
      // before the real one arrives - so re-picking here swapped the artwork
      // out from under the reader a moment after it appeared, for no reason
      // other than that the list it came from was a different object.
      final current = backgroundImage;
      final stillThere =
          current != null && (widget.backDrops?.backDrop?.any((image) => image.key == current.key) ?? false);
      if (!stillThere) {
        backgroundImage = widget.backDrops?.randomBackDrop;
      }
    }
    if (widget.item != null && widget.item?.id != item?.id) {
      item = widget.item;
    }
  }

  void updateImage() {
    if (lastImages == null) {
      lastImages = widget.backDrops?.backDrop;
      backgroundImage = widget.backDrops?.randomBackDrop;
    }
  }

  Future<void> _updateDominantColor() async {
    if (widget.dominantColor != null) {
      // Only when it changed. This runs from didUpdateWidget, and a setState
      // there for a colour that is the same as before built the whole page a
      // second time on every rebuild of its parent.
      if (widget.dominantColor != dominantColor) {
        setState(() {
          dominantColor = widget.dominantColor;
        });
      }
      return;
    }
    if (!ref.read(clientSettingsProvider.select((value) => value.deriveColorsFromItem))) return;
    final newImage = widget.item?.getPosters?.logo;
    // By what the picture is, not by which copy of it we were handed: a page
    // that swaps the item it is showing - the show page moving between the
    // series and one of its episodes - hands over an equal-but-new instance
    // every time, and re-deriving the palette on each of those both costs a
    // decode and flickers the theme.
    final newKey = newImage == null ? null : "${newImage.key}|${newImage.path}";
    if (newImage == null || newKey == _lastColorImage) return;
    _lastColorImage = newKey;

    final provider = newImage.imageProvider;
    _lastRequestedImage = provider;

    final newColor = await getDominantColor(provider);

    if (!mounted || !identical(_lastRequestedImage, provider)) return;

    setState(() {
      dominantColor = newColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final horizontalBasePadding = size.width / 25;
    final safeArea = MediaQuery.paddingOf(context);
    final backGroundColor = Theme.of(context).colorScheme.surface.withValues(alpha: 0.8);
    final maxHeight = detailArtworkHeight(context);
    final sideBarPadding = AdaptiveLayout.of(context).sideBarWidth;
    final topBarPadding = AdaptiveLayout.of(context).topBarHeight;
    // What the sharp backdrop actually needs at this width, never more than
    // the band leaves room for. On anything wider than a phone this is the
    // band's own height - [detailArtworkHeight] is measured the same way -
    // so only a phone, where the band has a floor, has room to spare.
    final backdropRoom = (maxHeight - (20 + topBarPadding)).clamp(0.0, maxHeight);
    final backdropHeight = ((size.width - sideBarPadding / 1.5) / (16 / 9)).clamp(0.0, backdropRoom);
    final directionalSidePadding = EdgeInsetsDirectional.only(start: sideBarPadding);
    final horizontalPadding = 16.0;
    final contentPadding = EdgeInsets.only(
      left: isRtl ? horizontalBasePadding : sideBarPadding + horizontalPadding + safeArea.left,
      right: isRtl ? sideBarPadding + horizontalPadding + safeArea.right : horizontalBasePadding,
    );
    final topRowPadding = safeArea
        .add(directionalSidePadding.resolve(Directionality.of(context)))
        .add(EdgeInsets.only(top: topBarPadding))
        .add(EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 12));

    return ThemeOverwrite(
      color: dominantColor,
      child: (context) => PullToRefresh(
        onRefresh: () async {
          await widget.onRefresh?.call();
          if (mounted) {
            setState(() {
              if (widget.backDrops?.backDrop?.contains(backgroundImage) == true) {
                backgroundImage = widget.backDrops?.randomBackDrop;
              }
            });
          }
        },
        refreshOnStart: true,
        child: (context) => Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Stack(
                  children: [
                    SizedBox(
                      height: maxHeight,
                      width: size.width,
                      child: FladderImage(
                        image: backgroundImage,
                        blurOnly: !widget.posterFillsContent,
                      ),
                    ),
                    if (backgroundImage != null && !widget.posterFillsContent)
                      SizedBox(
                        height: maxHeight,
                        width: size.width,
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            start: sideBarPadding / 1.5,
                            top: topBarPadding / 1.5,
                          ),
                          // Sits at the top of the band. The band is measured
                          // from the picture rather than the other way around
                          // (see [detailArtworkHeight]), so there is nothing
                          // below it worth centring in.
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: RepaintBoundary(
                              child: SizedBox(
                                width: double.infinity,
                                height: backdropHeight,
                                child: FadeEdges(
                                  leftFade: sideBarPadding > 0 && !isRtl ? 0.05 : 0.0,
                                  rightFade: sideBarPadding > 0 && isRtl ? 0.05 : 0.0,
                                  topFade: topBarPadding > 0 ? 0.1 : 0.0,
                                  bottomFade: 0.2,
                                  child: FadeInImage(
                                    placeholder: ResizeImage(
                                      backgroundImage!.imageProvider,
                                      height: maxHeight ~/ 1.5,
                                    ),
                                    placeholderColor: Colors.transparent,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    placeholderFit: BoxFit.cover,
                                    excludeFromSemantics: true,
                                    image: ResizeImage(
                                      backgroundImage!.imageProvider,
                                      height: maxHeight ~/ 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      height: maxHeight + 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.posterFillsContent
                              ? [
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 1),
                                ]
                              : [
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.10),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.35),
                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                                  Theme.of(context).colorScheme.surface,
                                ],
                        ),
                      ),
                    ),
                    Container(
                      height: size.height,
                      width: size.width,
                      color: widget.backgroundColor,
                    ),
                    FocusScope(
                      autofocus: true,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: size.height,
                          maxWidth: size.width,
                        ),
                        child: widget.content(
                          context,
                          contentPadding,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              //Top row buttons
              IconTheme(
                data: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
                child: Padding(
                  padding: topRowPadding,
                  child: Row(
                    children: [
                      // A remote has its own back button, so this one is only
                      // clutter there. The rest of the row is not - it
                      // carries SyncPlay and Cast on detail screens.
                      if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad)
                        IconButton.filledTonal(
                          style: IconButton.styleFrom(
                            backgroundColor: backGroundColor,
                          ),
                          onPressed: () => context.router.popBack(),
                          icon: Padding(
                            padding:
                                EdgeInsets.all(AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer ? 0 : 4),
                            child: const BackButtonIcon(),
                          ),
                        ),
                      const Spacer(),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          decoration: BoxDecoration(
                              color: backGroundColor, borderRadius: FladderTheme.defaultShape.borderRadius),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item != null) ...[
                                ref.watch(syncedItemProvider(item)).when(
                                      error: (error, stackTrace) => const SizedBox.shrink(),
                                      data: (syncedItem) {
                                        if (syncedItem == null &&
                                            ref.read(userProvider.select(
                                              (value) => value?.canDownload ?? false,
                                            )) &&
                                            item?.syncAble == true) {
                                          return IconButton(
                                            onPressed: () =>
                                                ref.read(syncProvider.notifier).addSyncItem(context, item!),
                                            icon: const Icon(
                                              IconsaxPlusLinear.arrow_down_2,
                                            ),
                                          );
                                        } else if (syncedItem != null) {
                                          return IconButton(
                                            onPressed: () => showSyncItemDetails(context, syncedItem, ref),
                                            icon: SyncButton(item: item!, syncedItem: syncedItem),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                      loading: () => const SizedBox.shrink(),
                                    ),
                                Builder(
                                  builder: (context) {
                                    final newActions = widget.actions?.call(context);
                                    if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer) {
                                      return PopupMenuButton(
                                        tooltip: context.localized.moreOptions,
                                        enabled: newActions?.isNotEmpty == true,
                                        icon: Icon(
                                          Icons.more_vert_rounded,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                        itemBuilder: (context) => newActions?.popupMenuItems(useIcons: true) ?? [],
                                      );
                                    } else {
                                      return IconButton(
                                        onPressed: () => showBottomSheetPill(
                                          context: context,
                                          content: (context, scrollController) => ListView(
                                            controller: scrollController,
                                            shrinkWrap: true,
                                            children: newActions?.listTileItems(context, useIcons: true) ?? [],
                                          ),
                                        ),
                                        icon: const Icon(Icons.more_vert_rounded),
                                      );
                                    }
                                  },
                                ),
                              ],
                              if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer)
                                Tooltip(
                                  message: context.localized.refresh,
                                  child: IconButton(
                                    onPressed: () => context.refreshData(),
                                    icon: const Icon(IconsaxPlusLinear.refresh),
                                  ),
                                ),
                              // Detail screens carry them in this row; the
                              // sticky corner pair is for the overview
                              // screens, which have no row like this.
                              const PlaybackChromeActions(background: false),
                              if (AdaptiveLayout.layoutModeOf(context) == LayoutMode.single ||
                                  AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  child: const SizedBox(
                                    height: 30,
                                    width: 30,
                                    child: SettingsUserIcon(),
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
          ),
        ),
      ),
    );
  }
}

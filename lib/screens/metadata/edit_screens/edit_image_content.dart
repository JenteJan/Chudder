import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_editing_model.dart';
import 'package:fladder/providers/edit_item_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/screens/shared/file_picker.dart';
import 'package:fladder/util/custom_cache_manager.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';

class EditImageContent extends ConsumerStatefulWidget {
  final ImageType type;
  const EditImageContent({required this.type, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _EditImageContentState();
}

class _EditImageContentState extends ConsumerState<EditImageContent> {
  bool loading = false;
  ProviderSubscription<String?>? _itemListener;

  Future<void> loadAll() async {
    // Nothing to search for until the editor has its item; the listener
    // below runs this again the moment it lands.
    if (ref.read(editItemProvider).item == null) return;
    setState(() {
      loading = true;
    });
    try {
      await ref.read(editItemProvider.notifier).fetchRemoteImages(type: widget.type);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // The editor's refresh clears its state and reloads the item, which
    // drops the remote images with it; fetch them again whenever the item
    // (re)appears.
    _itemListener = ref.listenManual<String?>(
      editItemProvider.select((value) => value.item?.id),
      (previous, next) {
        if (next != null && next != previous) loadAll();
      },
    );
    Future.microtask(() => loadAll());
  }

  @override
  void didUpdateWidget(covariant EditImageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) loadAll();
  }

  @override
  void dispose() {
    _itemListener?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posterSize = MediaQuery.sizeOf(context).width /
        (AdaptiveLayout.poster(context).gridRatio *
            ref.watch(clientSettingsProvider.select((value) => value.posterSize)));
    final decimal = posterSize - posterSize.toInt();
    final includeAllImages = ref.watch(editItemProvider.select((value) => value.includeAllImages));
    final images = ref.watch(editItemProvider.select((value) => switch (widget.type) {
          ImageType.backdrop => value.backdrop.images,
          ImageType.logo => value.logo.images,
          ImageType.primary || _ => value.primary.images,
        }));

    final customImages = ref.watch(editItemProvider.select((value) => switch (widget.type) {
          ImageType.backdrop => value.backdrop.customImages,
          ImageType.logo => value.logo.customImages,
          ImageType.primary || _ => value.primary.customImages,
        }));

    final selectedImage = ref.watch(editItemProvider.select((value) => switch (widget.type) {
          ImageType.logo => value.logo.selected,
          ImageType.primary => value.primary.selected,
          _ => null,
        }));

    final serverImages = ref.watch(editItemProvider.select((value) => switch (widget.type) {
          ImageType.logo => value.logo.serverImages,
          ImageType.primary => value.primary.serverImages,
          ImageType.backdrop => value.backdrop.serverImages,
          _ => null,
        }));

    final selections = ref.watch(editItemProvider.select((value) => switch (widget.type) {
          ImageType.backdrop => value.backdrop.selection,
          _ => [],
        }));

    final hiddenTags = ref.watch(clientSettingsProvider.select((value) => value.hiddenBackdropTags));

    Widget buildImageCard(EditingImageModel image, {required bool isServerImage, required bool isSelected}) {
      final tag = image.tag;
      // Only a backdrop can sit out: there are several, and the page picks
      // one. A poster or logo is the one picture of its kind.
      final canHide = isServerImage && widget.type == ImageType.backdrop && tag != null && tag.isNotEmpty;
      final isHidden = canHide && hiddenTags.contains(tag);
      final tooltipMessage = isServerImage
          ? (isHidden ? context.localized.hiddenFromRotation : context.localized.serverImage)
          : "${image.providerName} - ${image.language} \n${image.width}x${image.height}";

      Future<void> showDeleteDialog() async {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.localized.deleteImage),
            content: Text(context.localized.deleteImagePermanent),
            actions: [
              ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                  iconColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () async {
                  await ref.read(editItemProvider.notifier).deleteImage(widget.type, image);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(context.localized.deleteFromServer),
              )
            ],
          ),
        );
      }

      void toggleHidden() {
        if (!canHide) return;
        ref.read(clientSettingsProvider.notifier).setBackdropHidden(tag, !isHidden);
      }

      // Delete lives one step further away than it used to: a long press or
      // right-click opens this, and only its second entry removes the file.
      Future<void> showServerImageMenu() async {
        final errorColor = Theme.of(context).colorScheme.error;
        await showDialog(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(context.localized.serverImage),
            children: [
              if (canHide)
                ListTile(
                  leading: Icon(isHidden ? IconsaxPlusLinear.eye : IconsaxPlusLinear.eye_slash),
                  title: Text(isHidden ? context.localized.showInRotation : context.localized.hideFromRotation),
                  subtitle: Text(context.localized.rotationThisDeviceOnly),
                  onTap: () {
                    Navigator.of(context).pop();
                    toggleHidden();
                  },
                ),
              ListTile(
                leading: Icon(IconsaxPlusLinear.trash, color: errorColor),
                title: Text(context.localized.deleteFromServer, style: TextStyle(color: errorColor)),
                subtitle: Text(context.localized.deleteImagePermanent),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showDeleteDialog();
                },
              ),
            ],
          ),
        );
      }

      return Tooltip(
        message: tooltipMessage,
        child: FocusButton(
          onTap: () {
            if (canHide) {
              toggleHidden();
              return;
            }
            ref.read(editItemProvider.notifier).selectImage(widget.type, isServerImage ? null : image);
          },
          onLongPress: isServerImage ? showServerImageMenu : null,
          onSecondaryTapDown: isServerImage ? (details) => showServerImageMenu() : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: image.ratio,
                child: Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isServerImage
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: isHidden ? 0.4 : 1)
                            : isSelected
                                ? Colors.white
                                : Colors.transparent,
                        width: 4,
                        strokeAlign: BorderSide.strokeAlignInside),
                  ),
                  child: Card(
                    color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
                    child: Opacity(
                      opacity: isHidden ? 0.35 : 1,
                      child: isServerImage
                          ? CachedNetworkImage(
                              cacheKey: image.url ?? image.hashCode.toString(),
                              imageUrl: image.url ?? "",
                              cacheManager: CustomCacheManager.instance,
                            )
                          : (image.imageData != null
                              ? Image(image: Image.memory(image.imageData!).image)
                              : CachedNetworkImage(
                                  imageUrl: image.url ?? "",
                                  cacheManager: CustomCacheManager.instance,
                                )),
                    ),
                  ),
                ),
              ),
              if (isHidden)
                IgnorePointer(
                  child: Icon(
                    IconsaxPlusLinear.eye_slash,
                    size: 36,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final allImageCards = [
      ...?serverImages?.map((image) {
        final selected = selectedImage == null;
        return buildImageCard(image, isServerImage: true, isSelected: selected);
      }),
      ...([...customImages, ...images].map((image) {
        final selected = switch (widget.type) {
          ImageType.backdrop => selections.contains(image),
          _ => selectedImage == image,
        };
        return buildImageCard(image, isServerImage: false, isSelected: selected);
      }))
    ];
    final hintLabel = switch (AdaptiveLayout.inputDeviceOf(context)) {
      InputDevice.touch || InputDevice.dPad => context.localized.metadataImageLongPressTouch,
      InputDevice.pointer => context.localized.metadataImageLongPressClick,
    };
    return Column(
      children: [
        SizedBox(
          height: 80,
          child: FilePickerBar(
            multipleFiles: switch (widget.type) {
              ImageType.backdrop => true,
              _ => false,
            },
            extensions: FladderFile.imageTypes,
            urlPicked: (url) {
              final newFile = EditingImageModel(providerName: "Custom(URL)", url: url);
              ref.read(editItemProvider.notifier).addCustomImages(widget.type, [newFile]);
            },
            onFilesPicked: (file) {
              final newFiles = file.map(
                (e) => EditingImageModel(
                  providerName: "Custom(${e.name})",
                  imageData: e.data,
                ),
              );
              ref.read(editItemProvider.notifier).addCustomImages(widget.type, newFiles);
            },
          ),
        ),
        SettingsListTile(
          label: Text(context.localized.includeAllLanguages),
          trailing: Switch(
            value: includeAllImages,
            onChanged: (value) {
              ref.read(editItemProvider.notifier).setIncludeImages(value);
              loadAll();
            },
          ),
        ),
        Text(
          widget.type == ImageType.backdrop ? "$hintLabel\n${context.localized.backdropRotationHint}" : hintLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              children: [
                GridView(
                  shrinkWrap: true,
                  scrollDirection: Axis.vertical,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    mainAxisSpacing: (8 * decimal) + 8,
                    crossAxisSpacing: (8 * decimal) + 8,
                    childAspectRatio: 1.0,
                    crossAxisCount: posterSize.toInt().clamp(1, double.maxFinite).toInt(),
                  ),
                  children: allImageCards,
                ),
                if (loading) const Center(child: CircularProgressIndicator(strokeCap: StrokeCap.round)),
                if (!loading && allImageCards.isEmpty) Center(child: Text("No ${widget.type.value}s found"))
              ],
            ),
          ),
        ),
      ],
    );
  }
}

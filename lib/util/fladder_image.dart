import 'package:flutter/material.dart';

import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transparent_image/transparent_image.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/providers/arguments_provider.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';

/// How far beyond the viewport a poster list keeps its items built.
///
/// Flutter's default is 250 logical pixels, which is less than the height of a
/// single poster — nothing starts loading until it is practically on screen,
/// so scrolling quickly always outran the images. Two rows of head start is
/// enough for a fast flick to land on pictures rather than placeholders,
/// without building so far ahead that the scroll itself pays for it.
const double kPosterCacheExtent = 1000;

/// A picture appearing should be quick enough not to be mistaken for one that
/// has not arrived.
///
/// [FadeInImage] defaults to 700ms in and 300ms out. On a grid that is most of
/// a second per poster spent translucent, which reads as "still loading" —
/// especially while scrolling, where a dozen of them are mid-fade at once.
const Duration kImageFadeIn = Duration(milliseconds: 150);
const Duration kImageFadeOut = Duration(milliseconds: 100);

class FladderImage extends ConsumerWidget {
  final ImageData? image;
  final Widget Function(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded)? frameBuilder;
  final Widget Function(BuildContext context, Object object, StackTrace? stack)? imageErrorBuilder;
  final Widget? placeHolder;
  final StackFit stackFit;
  final BoxFit fit;
  final BoxFit? blurFit;
  final AlignmentGeometry? alignment;
  final bool disableBlur;
  final bool blurOnly;
  final int decodeHeight;
  final bool cachedImage;
  const FladderImage({
    required this.image,
    this.frameBuilder,
    this.imageErrorBuilder,
    this.placeHolder,
    this.stackFit = StackFit.expand,
    this.fit = BoxFit.cover,
    this.blurFit,
    this.alignment,
    this.disableBlur = false,
    this.blurOnly = false,
    this.decodeHeight = 520,
    this.cachedImage = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBluredPlaceHolder = ref.watch(clientSettingsProvider.select((value) => value.blurPlaceHolders));
    final newImage = image;
    final imageProvider = cachedImage ? image?.imageProvider : image?.nonCachedImageProvider;

    final leanBackMode = ref.watch(argumentsStateProvider.select((value) => value.leanBackMode));

    if (newImage == null) {
      return placeHolder ?? Container();
    } else {
      return Stack(
        key: Key(newImage.key),
        fit: stackFit,
        children: [
          if (!disableBlur && useBluredPlaceHolder && newImage.hash.isNotEmpty || blurOnly && newImage.hash.isNotEmpty)
            Image(
              image: BlurHashImage(
                newImage.hash,
                decodingHeight: 16,
                decodingWidth: 16,
              ),
              fit: blurFit ?? fit,
              height: 16,
            ),
          if (!blurOnly && imageProvider != null)
            FadeInImage(
              placeholder: MemoryImage(kTransparentImage),
              fadeInDuration: kImageFadeIn,
              fadeOutDuration: kImageFadeOut,
              fit: fit,
              placeholderFit: fit,
              alignment: alignment ?? Alignment.center,
              imageErrorBuilder: imageErrorBuilder,
              image: leanBackMode
                  ? ResizeImage(
                      imageProvider,
                      policy: ResizeImagePolicy.fit,
                      height: decodeHeight,
                    )
                  : imageProvider,
            )
        ],
      );
    }
  }
}

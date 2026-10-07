import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/util/blur_placeholder_image.dart';

/// How far beyond the viewport a poster list keeps its items built.
///
/// Flutter's default is 250 logical pixels, which is less than the height of a
/// single poster — nothing starts loading until it is practically on screen,
/// so scrolling quickly always outran the images. Two rows of head start is
/// enough for a fast flick to land on pictures rather than placeholders,
/// without building so far ahead that the scroll itself pays for it.
const ScrollCacheExtent kPosterCacheExtent = ScrollCacheExtent.pixels(1000);

/// A picture appearing should be quick enough not to be mistaken for one that
/// has not arrived.
///
/// [FadeInImage] defaults to 700ms in and 300ms out. On a grid that is most of
/// a second per poster spent translucent, which reads as "still loading" —
/// especially while scrolling, where a dozen of them are mid-fade at once.
const Duration kImageFadeIn = Duration(milliseconds: 150);

const int kLeanBackDecodeHeight = 520;

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
  /// Decode no taller than this. A picture is decoded at the size it was
  /// sent, whatever it is drawn at: a 2000px backdrop behind a blur is 16MB
  /// of pixels for a smear. Given, it is decoded to fit this height instead.
  final int? decodeHeight;

  /// Decode at the size the picture is laid out at, rather than the size the
  /// server sent.
  ///
  /// Posters arrive sized for the largest place a poster is drawn - the
  /// detail page's - and were decoded at that size in every grid cell too: on
  /// a phone a 600x900 poster in a cell a third of that across. Each one was
  /// three times the decoding work while scrolling, and three times the
  /// memory, so the decoded-image cache held a third as many and scrolling
  /// back a few rows meant decoding them all again.
  ///
  /// Only for pictures that never take part in a hero flight: the copy that
  /// flies is laid out at every size between the two ends, and would ask for
  /// a new decode partway. Ignored where [decodeHeight] or the television's
  /// own limit already applies.
  final bool decodeToLayout;
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
    this.decodeHeight,
    this.decodeToLayout = false,
    this.cachedImage = true,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useBluredPlaceHolder = ref.watch(clientSettingsProvider.select((value) => value.blurPlaceHolders));
    final newImage = image;
    final imageProvider = cachedImage ? image?.imageProvider : image?.nonCachedImageProvider;

    final leanBackMode = ref.watch(argumentsStateProvider.select((value) => value.leanBackMode));
    // A television decodes everything small; it has the memory of a phone and
    // sits far enough away that nobody can tell.
    final resizeTo = decodeHeight ?? (leanBackMode ? kLeanBackDecodeHeight : null);

    if (newImage == null) {
      return placeHolder ?? Container();
    }

    Widget stack(ImageProvider? provider) => Stack(
          key: Key(newImage.key),
          fit: stackFit,
          children: [
            // Not under a picture that is already decoded: that one is drawn
            // on this very frame, and the blur beneath it is never seen. It
            // was still decoded - in Dart, on this thread - for every card
            // that scrolled back into view, a row of them at a time.
            if (blurOnly && newImage.hash.isNotEmpty ||
                !disableBlur &&
                    useBluredPlaceHolder &&
                    newImage.hash.isNotEmpty &&
                    !(provider != null && _alreadyDecoded(provider)))
              Image(
                // The package's own decoder off the phone and the desktop:
                // a browser cannot make an image from bare pixels this way.
                image: kIsWeb
                    ? BlurHashImage(newImage.hash, decodingHeight: 16, decodingWidth: 16) as ImageProvider
                    : BlurPlaceholderImage(newImage.hash),
                fit: blurFit ?? fit,
                height: 16,
                excludeFromSemantics: true,
              ),
            if (!blurOnly && provider != null)
              _RevealedImage(
                image: provider,
                fit: fit,
                alignment: alignment ?? Alignment.center,
                errorBuilder: imageErrorBuilder,
              )
          ],
        );

    if (resizeTo != null && imageProvider != null) {
      return stack(ResizeImage(
        imageProvider,
        policy: ResizeImagePolicy.fit,
        height: resizeTo,
      ));
    }

    if (decodeToLayout && !blurOnly && imageProvider != null) {
      final pixelRatio = MediaQuery.devicePixelRatioOf(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final box = constraints.biggest;
          // Nothing to size it to: an unbounded side is decoded as sent.
          if (!box.isFinite || box.isEmpty) return stack(imageProvider);
          return stack(CoverResizeImage(
            imageProvider,
            width: _decodeBucket(box.width * pixelRatio),
            height: _decodeBucket(box.height * pixelRatio),
          ));
        },
      );
    }

    return stack(imageProvider);
  }
}

/// A picture that fades in when it arrives, and is simply there when it was
/// already in memory.
///
/// What [FadeInImage] did, for a card's worth less. That widget is built to
/// cross-fade a placeholder into a picture: two images, a stack, and an
/// animation set up for every one, around a placeholder that here was a single
/// transparent pixel. Most pictures in a grid someone is scrolling back
/// through are decoded already and never fade at all, so the animation is made
/// only for the ones that do.
class _RevealedImage extends StatefulWidget {
  const _RevealedImage({
    required this.image,
    required this.fit,
    required this.alignment,
    this.errorBuilder,
  });

  final ImageProvider image;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  State<_RevealedImage> createState() => _RevealedImageState();
}

class _RevealedImageState extends State<_RevealedImage> with SingleTickerProviderStateMixin {
  /// Fully there until a picture turns up that has to fade in.
  final ProxyAnimation _opacity = ProxyAnimation(kAlwaysCompleteAnimation);
  AnimationController? _fade;
  CurvedAnimation? _curve;

  /// Whether the picture now showing has been dealt with, faded or not.
  bool _shown = false;

  @override
  void didUpdateWidget(_RevealedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another picture in the same place gets its own arrival.
    if (oldWidget.image != widget.image) _shown = false;
  }

  @override
  void dispose() {
    _curve?.dispose();
    _fade?.dispose();
    super.dispose();
  }

  Widget _frame(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
    // Nothing is drawn before the first frame, whatever the opacity says.
    if (frame == null || _shown) return child;
    _shown = true;
    if (wasSynchronouslyLoaded) {
      _opacity.parent = kAlwaysCompleteAnimation;
      return child;
    }
    final fade = _fade ??= AnimationController(vsync: this, duration: kImageFadeIn);
    _opacity.parent = _curve ??= CurvedAnimation(parent: fade, curve: Curves.easeIn);
    fade.forward(from: 0);
    return child;
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.image,
      fit: widget.fit,
      alignment: widget.alignment,
      opacity: _opacity,
      frameBuilder: _frame,
      errorBuilder: widget.errorBuilder,
      excludeFromSemantics: true,
    );
  }
}

/// Whether [provider]'s picture is in memory, decoded, ready to be drawn
/// without waiting for anything.
bool _alreadyDecoded(ImageProvider provider) {
  Object? key;
  // Synchronous for every provider a picture here is made of; one that is
  // not leaves the key unset, and the placeholder is shown as before.
  provider.obtainKey(ImageConfiguration.empty).then((value) => key = value);
  final found = key;
  if (found == null) return false;
  final status = PaintingBinding.instance.imageCache.statusForKey(found);
  return status.keepAlive && !status.pending;
}

/// Rounds a decode size up to a step, so that a box changing by a pixel -
/// a window being dragged wider - does not decode the picture again at every
/// size it passes through. Up rather than to the nearest, so the picture is
/// never decoded smaller than it is drawn.
int _decodeBucket(double physicalPixels) => ((physicalPixels / 64).ceil() * 64).clamp(64, 1 << 14);

/// Decodes [imageProvider] only as large as it takes to cover a box of
/// [width] by [height] pixels, keeping its shape.
///
/// [ResizeImage] can fit a picture inside a box or stretch it to one, but a
/// cover-fit poster needs the other way round: the smaller scale of the two
/// sides would leave a wide picture in a tall box blurry at the top and
/// bottom. Never upscales - a picture already smaller than the box is
/// decoded as it is.
///
/// Keyed on the inner provider's key plus the box, so the network and disk
/// caches still see one picture, and only the decoded copy is per size.
class CoverResizeImage extends ImageProvider<CoverResizeImageKey> {
  const CoverResizeImage(this.imageProvider, {required this.width, required this.height});

  final ImageProvider<Object> imageProvider;
  final int width;
  final int height;

  @override
  Future<CoverResizeImageKey> obtainKey(ImageConfiguration configuration) {
    // Synchronous when the inner provider's key is, as [ResizeImage] does: a
    // picture already in the cache should be drawn on the frame that asks for
    // it, not one frame later with a fade.
    Completer<CoverResizeImageKey>? completer;
    SynchronousFuture<CoverResizeImageKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      final resized = CoverResizeImageKey._(key, width, height);
      if (completer == null) {
        result = SynchronousFuture<CoverResizeImageKey>(resized);
      } else {
        completer.complete(resized);
      }
    });
    if (result != null) return result!;
    completer = Completer<CoverResizeImageKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(CoverResizeImageKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeCover(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(buffer, getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
        final scale = math.max(width / intrinsicWidth, height / intrinsicHeight);
        if (scale >= 1) return ui.TargetImageSize(width: intrinsicWidth, height: intrinsicHeight);
        return ui.TargetImageSize(
          width: (intrinsicWidth * scale).ceil(),
          height: (intrinsicHeight * scale).ceil(),
        );
      });
    }

    final completer = imageProvider.loadImage(key._providerKey, decodeCover);
    // A failed load is not kept under this key, so the next time the poster
    // is built it tries again - what [ResizeImage] does for the same reason.
    completer.addEphemeralErrorListener((Object exception, StackTrace? stackTrace) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  @override
  bool operator ==(Object other) =>
      other is CoverResizeImage &&
      other.imageProvider == imageProvider &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(imageProvider, width, height);

  @override
  String toString() => 'CoverResizeImage($imageProvider, $width x $height)';
}

class CoverResizeImageKey {
  const CoverResizeImageKey._(this._providerKey, this._width, this._height);

  final Object _providerKey;
  final int _width;
  final int _height;

  @override
  bool operator ==(Object other) =>
      other is CoverResizeImageKey &&
      other._providerKey == _providerKey &&
      other._width == _width &&
      other._height == _height;

  @override
  int get hashCode => Object.hash(_providerKey, _width, _height);
}

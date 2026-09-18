import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/screens/shared/media/components/poster_placeholder.dart';
import 'package:chudder/util/fladder_image.dart';

/// The shape of a wide card's picture.
const double kWideCardArtRatio = 16 / 9;

/// Wide pictures are drawn on cards a few hundred pixels across; a backdrop is
/// sent for a whole screen. Decoded to this height they cost a tenth of the
/// memory and look the same.
const int _wideCardDecodeHeight = 540;

/// What a wide card draws for an item, best first.
@immutable
class WideCardArt {
  const WideCardArt({this.still, this.poster});

  /// A wide picture of the thing.
  final ImageData? still;

  /// When there is nothing wide at all, the poster, drawn whole.
  final ImageData? poster;

  /// For a card in a row. Thumb is the landscape art made for cards like these,
  /// title and all, so it comes first: an episode takes its show's, since
  /// episodes seldom have one of their own, and only then its own still. A
  /// backdrop is the picture without the title. Banner art is a strip five
  /// times as wide as it is tall, and cut to 16:9 is a slice of its middle.
  static WideCardArt of(ItemBaseModel item) {
    final own = item.images;
    final show = item.getPosters;
    final ImageData? still = switch (item) {
      EpisodeModel _ => own?.thumb ?? show?.thumb ?? own?.primary ?? show?.backDrop?.firstOrNull,
      _ => own?.thumb ?? own?.backDrop?.firstOrNull ?? show?.thumb,
    };
    return WideCardArt(still: still, poster: show?.primary ?? own?.primary);
  }

  /// For a picture as big as a banner, which has the title written over it
  /// already: the backdrop first, so the name is not there twice.
  static WideCardArt large(ItemBaseModel item) {
    final own = item.images;
    final show = item.getPosters;
    final ImageData? still = own?.backDrop?.firstOrNull ??
        show?.backDrop?.firstOrNull ??
        (item is EpisodeModel ? own?.primary : null) ??
        own?.thumb ??
        show?.thumb;
    return WideCardArt(still: still, poster: show?.primary ?? own?.primary);
  }
}

/// The picture of a wide card - see [WideCardArt] for which one.
class WideCardImage extends StatelessWidget {
  const WideCardImage({
    required this.art,
    required this.item,
    this.decodeHeight = _wideCardDecodeHeight,
    this.alignment,
    super.key,
  });

  WideCardImage.card({required ItemBaseModel item, Key? key}) : this(art: WideCardArt.of(item), item: item, key: key);

  final WideCardArt art;
  final ItemBaseModel item;
  final int decodeHeight;

  /// Which part of the still to keep when its box is not its shape.
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final placeholder = PosterPlaceholder(item: item);
    final still = art.still;
    if (still != null) {
      return FladderImage(image: still, decodeHeight: decodeHeight, placeHolder: placeholder, alignment: alignment);
    }
    final poster = art.poster;
    if (poster == null) return placeholder;
    return _WholePoster(poster: poster, placeholder: placeholder);
  }
}

/// A poster on a wide card: whole, over a blur of itself, rather than cropped
/// to a strip across its middle.
class _WholePoster extends StatelessWidget {
  const _WholePoster({required this.poster, required this.placeholder});

  final ImageData poster;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster.hash.isNotEmpty)
          FladderImage(image: poster, blurOnly: true)
        else
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16, tileMode: TileMode.decal),
            child: FladderImage(image: poster, decodeHeight: 64, disableBlur: true),
          ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
        FladderImage(image: poster, fit: BoxFit.contain, disableBlur: true, placeHolder: placeholder),
      ],
    );
  }
}

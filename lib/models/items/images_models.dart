import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart' as enums;
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/providers/arguments_provider.dart';
import 'package:chudder/providers/image_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/util/custom_cache_manager.dart';

/// Posters are asked for at quality 80 rather than the 90 everything else
/// gets. Measured on a real library that is a third fewer bytes per poster -
/// 138KB down to 91KB at the 600px a grid asks for - and posters are nearly
/// all of what a library page downloads.
const int kPosterQuality = 80;

/// What to ask the server for, per kind of picture, so that it arrives at
/// about the size it is drawn.
///
/// The requests use Jellyfin's fill box: the picture is scaled until both
/// sides reach the box, never past its original. A square box therefore
/// overshoots by the picture's own shape - fill 600x600 is a 600x900 poster,
/// and fill 2000x2000 turns a 4K backdrop into 3556x2000 - for cells a quarter
/// of that. The boxes here have the shape of what they hold.
///
/// Nothing here goes into a cache key: a row poster and the page it opens build
/// the same URL, and a picture already on disk at another size keeps being
/// used.
class ArtworkSizes {
  const ArtworkSizes({
    required this.posterFill,
    required this.backdropWidth,
  });

  /// The short side of a poster or head shot. The largest one drawn is the
  /// detail page's poster, up to 480 logical pixels tall - 320 wide.
  final int posterFill;

  /// A backdrop's 16:9 box. Nothing draws one wider than the screen it is on.
  final int backdropWidth;

  Size get poster => Size(posterFill.toDouble(), posterFill.toDouble());

  /// Wide art on cards, twice the width of a poster.
  Size get thumb => Size(posterFill * 2.0, (posterFill * 9 / 8).roundToDouble());

  /// A library's tile, whatever shape its art is: a square box, so that wide
  /// art is not asked for taller than the tile, nor a portrait one wider.
  Size get tile => Size.square(min(thumb.height, otherPrimary.height));

  Size get backdrop => Size(backdropWidth.toDouble(), (backdropWidth * 9 / 16).roundToDouble());

  /// The primary of anything else keeps the old box: album covers, episode
  /// stills and photos are drawn in more shapes and at more sizes than a
  /// poster is - an album's cover fills its page.
  static const Size otherPrimary = Size(600, 600);

  static ArtworkSizes forScreen({
    required double devicePixelRatio,
    required double longestScreenSide,
    required bool leanBack,
  }) {
    // A television decodes everything to 520 pixels tall (see
    // [kLeanBackDecodeHeight]), so it never needs more than the smallest.
    final posterFill = leanBack ? 400 : ((320 * devicePixelRatio / 50).ceil() * 50).clamp(400, 600);
    final backdropWidth = !leanBack && longestScreenSide > 2560 ? 3840 : 1920;
    return ArtworkSizes(posterFill: posterFill, backdropWidth: backdropWidth);
  }

  /// For the screens this device has. The largest of them, so that moving the
  /// window to another screen does not change what is asked for.
  static ArtworkSizes of(Ref ref) {
    var ratio = 1.0;
    var longest = 0.0;
    try {
      final dispatcher = PlatformDispatcher.instance;
      for (final display in dispatcher.displays) {
        ratio = max(ratio, display.devicePixelRatio);
        longest = max(longest, display.size.longestSide);
      }
      if (longest == 0) {
        for (final view in dispatcher.views) {
          ratio = max(ratio, view.devicePixelRatio);
          longest = max(longest, view.physicalSize.longestSide);
        }
      }
    } catch (_) {}
    return forScreen(
      devicePixelRatio: ratio,
      longestScreenSide: longest,
      leanBack: ref.read(argumentsStateProvider).leanBackMode,
    );
  }

  /// Kinds whose primary is a library's tile, 200 logical pixels across.
  static bool hasTilePrimary(enums.BaseItemKind? kind) => switch (kind) {
        enums.BaseItemKind.collectionfolder || enums.BaseItemKind.userview => true,
        _ => false,
      };

  /// Kinds whose primary is a portrait poster.
  static bool hasPosterPrimary(enums.BaseItemKind? kind) => switch (kind) {
        enums.BaseItemKind.movie ||
        enums.BaseItemKind.series ||
        enums.BaseItemKind.season ||
        enums.BaseItemKind.boxset ||
        enums.BaseItemKind.trailer ||
        enums.BaseItemKind.book ||
        enums.BaseItemKind.person =>
          true,
        _ => false,
      };
}

class ImagesData {
  final ImageData? primary;
  final ImageData? thumb;
  final List<ImageData>? backDrop;
  final ImageData? logo;
  ImagesData({
    this.primary,
    this.thumb,
    this.backDrop,
    this.logo,
  });

  bool get isEmpty {
    if (primary == null && thumb == null && backDrop == null) return true;
    return false;
  }

  ImageData? get firstOrNull {
    return primary ?? thumb ?? backDrop?.firstOrNull;
  }

  /// One of the backdrops, the same one for as long as this instance lives.
  ///
  /// It used to shuffle the list in place and take the head, so every read
  /// was a different picture - and it is read from build, so a banner that
  /// rebuilt fetched, decoded and faded in a new backdrop each time.
  late final ImageData? randomBackDrop = _pickBackDrop();

  ImageData? _pickBackDrop() {
    final list = backDrop;
    if (list == null || list.isEmpty) return primary;
    return list[Random().nextInt(list.length)];
  }

  static ImagesData? fromBaseItem(
    dto.BaseItemDto item,
    Ref ref, {
    Size? backDrop,
    Size? thumb,
    Size logo = const Size(500, 500),
    Size? primary,
    bool getOriginalSize = false,
  }) {
    final itemid = item.id;
    if (itemid == null) return null;
    final imageProvider = ref.read(imageUtilityProvider);
    final hidden = ref.read(clientSettingsProvider).hiddenBackdropTags;
    final sizes = ArtworkSizes.of(ref);
    final backDropBox = backDrop ?? sizes.backdrop;
    thumb ??= sizes.thumb;
    primary ??= switch (item.type) {
      final kind when ArtworkSizes.hasPosterPrimary(kind) => sizes.poster,
      final kind when ArtworkSizes.hasTilePrimary(kind) => sizes.tile,
      _ => ArtworkSizes.otherPrimary,
    };

    final newImgesData = ImagesData(
      primary: item.imageTags?['Primary'] != null
          ? ImageData(
              path: getOriginalSize
                  ? imageProvider.getItemsOrigImageUrl(
                      itemid,
                      type: enums.ImageType.primary,
                      tag: item.imageTags?['Primary'],
                    )
                  : imageProvider.getItemsImageUrl(
                      itemid,
                      type: enums.ImageType.primary,
                      maxHeight: primary.height.toInt(),
                      maxWidth: primary.width.toInt(),
                      quality: kPosterQuality,
                      tag: item.imageTags?['Primary'],
                    ),
              key: "${itemid}_primary_${item.imageTags?['Primary']}",
              hash: item.imageBlurHashes?.primary?[item.imageTags?['Primary']] ?? "",
            )
          : null,
      thumb: item.imageTags?['Thumb'] != null
          ? ImageData(
              path: getOriginalSize
                  ? imageProvider.getItemsOrigImageUrl(
                      itemid,
                      type: enums.ImageType.thumb,
                      tag: item.imageTags?['Thumb'],
                    )
                  : imageProvider.getItemsImageUrl(
                      itemid,
                      type: enums.ImageType.thumb,
                      maxHeight: thumb.height.toInt(),
                      maxWidth: thumb.width.toInt(),
                      tag: item.imageTags?['Thumb'],
                    ),
              key: "${itemid}_thumb_${item.imageTags?['Thumb']}",
              hash: item.imageBlurHashes?.thumb?[item.imageTags?['Thumb']] ?? "",
            )
          : null,
      // Guarded like the primary above it. Built unconditionally, this handed
      // every item a logo URL whether the server had one or not, so anything
      // that asked for a logo got a 404 to render — which is the broken image
      // on a studio page, and a wasted request everywhere else.
      logo: item.imageTags?['Logo'] != null
          ? ImageData(
              path: getOriginalSize
                  ? imageProvider.getItemsOrigImageUrl(
                      itemid,
                      type: enums.ImageType.logo,
                      tag: item.imageTags?['Logo'],
                    )
                  : imageProvider.getItemsImageUrl(
                      itemid,
                      type: enums.ImageType.logo,
                      maxHeight: logo.height.toInt(),
                      maxWidth: logo.width.toInt(),
                      tag: item.imageTags?['Logo'],
                    ),
              key: "${itemid}_logo_${item.imageTags?['Logo']}",
              hash: item.imageBlurHashes?.logo?[item.imageTags?['Logo']] ?? "",
            )
          : null,
      backDrop: (item.backdropImageTags ?? [])
          .mapIndexed(
            (index, backdrop) {
              if (hidden.contains(backdrop)) return null;
              final image = ImageData(
                path: getOriginalSize
                    ? imageProvider.getBackdropOrigImage(
                        itemid,
                        index,
                        backdrop,
                      )
                    : imageProvider.getBackdropImage(
                        itemid,
                        index,
                        backdrop,
                        maxHeight: backDropBox.height.toInt(),
                        maxWidth: backDropBox.width.toInt(),
                      ),
                key: "${itemid}_backdrop_${index}_$backdrop",
                hash: item.imageBlurHashes?.backdrop?[backdrop] ?? "",
              );
              return image;
            },
          )
          .nonNulls
          .toList(),
    );
    return newImgesData;
  }

  static ImagesData? fromBaseItemParent(
    dto.BaseItemDto item,
    Ref ref, {
    Size? backDrop,
    Size? thumb,
    Size logo = const Size(500, 500),
    Size? primary,
  }) {
    if (item.seriesId == null && item.parentId == null) return null;

    final imageProvider = ref.read(imageUtilityProvider);
    final hidden = ref.read(clientSettingsProvider).hiddenBackdropTags;
    // The parent's primary is the show's poster, under the same key as the
    // show's own - so the same box as the show asks for.
    final sizes = ArtworkSizes.of(ref);
    final backDropBox = backDrop ?? sizes.backdrop;
    thumb ??= sizes.thumb;
    primary ??= sizes.poster;

    final newImgesData = ImagesData(
      primary: (item.seriesPrimaryImageTag != null)
          ? ImageData(
              path: imageProvider.getItemsImageUrl(
                item.seriesId,
                type: enums.ImageType.primary,
                maxHeight: primary.height.toInt(),
                maxWidth: primary.width.toInt(),
                quality: kPosterQuality,
                tag: item.seriesPrimaryImageTag,
              ),
              key: "${item.seriesId}_primary_${item.seriesPrimaryImageTag ?? ""}",
              hash: item.imageBlurHashes?.primary?[item.seriesPrimaryImageTag] ?? "")
          : null,
      thumb: ((item.seriesThumbImageTag ?? item.parentThumbImageTag) != null)
          ? ImageData(
              path: imageProvider.getItemsImageUrl(
                item.parentThumbItemId ?? item.seriesId ?? item.parentId,
                type: enums.ImageType.thumb,
                maxHeight: thumb.height.toInt(),
                maxWidth: thumb.width.toInt(),
                // Only the tag of the item this URL asks for. Another item's
                // tag would pin a version of the picture that never existed.
                tag: item.parentThumbItemId != null ? item.parentThumbImageTag : item.seriesThumbImageTag,
              ),
              key:
                  "${item.parentThumbItemId ?? item.seriesId ?? item.parentId}_thumb_${item.seriesThumbImageTag ?? item.parentThumbImageTag ?? ""}",
              hash: item.imageBlurHashes?.thumb?[item.seriesThumbImageTag ?? item.parentThumbImageTag] ?? "",
            )
          : null,
      logo: item.parentLogoImageTag != null
          ? ImageData(
              path: imageProvider.getItemsImageUrl(
                item.seriesId,
                type: enums.ImageType.logo,
                maxHeight: logo.height.toInt(),
                maxWidth: logo.width.toInt(),
                tag: item.parentLogoItemId == item.seriesId ? item.parentLogoImageTag : null,
              ),
              key: "${item.seriesId}_logo_${item.parentLogoImageTag}",
              hash: item.imageBlurHashes?.logo?[item.parentLogoImageTag] ?? "",
            )
          : null,
      // The parent's own tags, paired with the parent they belong to.
      //
      // This used to read [BaseItemDto.backdropImageTags], which on an episode
      // is the episode's backdrops - and then ask the series for them by index
      // and tag, which is a pairing the server has no answer for. Episodes
      // rarely carry backdrops of their own, so in practice the list came back
      // empty and a show opened from an episode had no artwork to show until
      // its own fetch returned. That is what made the artwork arrive late, in
      // step with the genres, both waiting on the same request.
      backDrop: ((item.parentBackdropImageTags?.isNotEmpty ?? false)
              ? item.parentBackdropImageTags!
              : (item.backdropImageTags ?? const <String>[]))
          .mapIndexed(
            (index, backdrop) {
              if (hidden.contains(backdrop)) return null;
              final itemId = (item.parentBackdropImageTags?.isNotEmpty ?? false)
                  ? (item.parentBackdropItemId ?? item.seriesId ?? item.parentId)
                  : (item.seriesId ?? item.parentId);
              if (itemId == null) return null;
              final image = ImageData(
                path: imageProvider.getBackdropImage(
                  itemId,
                  index,
                  backdrop,
                  maxHeight: backDropBox.height.toInt(),
                  maxWidth: backDropBox.width.toInt(),
                ),
                key: "${itemId}_backdrop_${index}_$backdrop",
                hash: item.imageBlurHashes?.backdrop?[backdrop] ?? "",
              );
              return image;
            },
          )
          .nonNulls
          .toList(),
    );
    return newImgesData;
  }

  static ImagesData? fromPersonDto(
    dto.BaseItemPerson item,
    Ref ref, {
    Size? primary,
  }) {
    // The same box as the person's own page asks for: both are stored under
    // the person's primary key, and whichever arrives first is what both show.
    primary ??= ArtworkSizes.of(ref).poster;
    return ImagesData(
      primary: (item.primaryImageTag != null && item.imageBlurHashes != null)
          ? ImageData(
              path: ref.read(imageUtilityProvider).getItemsImageUrl(
                    item.id ?? "",
                    type: enums.ImageType.primary,
                    maxHeight: primary.height.toInt(),
                    maxWidth: primary.width.toInt(),
                    quality: kPosterQuality,
                    tag: item.primaryImageTag,
                  ),
              key: "${item.id ?? ""}_primary_${item.primaryImageTag ?? ''}",
              hash: item.imageBlurHashes?.primary?[item.primaryImageTag] ?? '')
          : null,
      thumb: null,
      logo: null,
      backDrop: null,
    );
  }

  @override
  String toString() => 'ImagesData(primary: $primary, thumb: $thumb, backDrop: $backDrop, logo: $logo)';

  ImagesData copyWith({
    ValueGetter<ImageData?>? primary,
    ValueGetter<ImageData?>? thumb,
    ValueGetter<List<ImageData>?>? backDrop,
    ValueGetter<ImageData?>? logo,
  }) {
    return ImagesData(
      primary: primary != null ? primary() : this.primary,
      thumb: thumb != null ? thumb() : this.thumb,
      backDrop: backDrop != null ? backDrop() : this.backDrop,
      logo: logo != null ? logo() : this.logo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'primary': primary?.toMap(),
      'thumb': thumb?.toMap(),
      'backDrop': backDrop?.map((x) => x.toMap()).toList(),
      'logo': logo?.toMap(),
    };
  }

  factory ImagesData.fromMap(Map<String, dynamic> map) {
    return ImagesData(
      primary: map['primary'] != null ? ImageData.fromMap(map['primary']) : null,
      thumb: map['thumb'] != null ? ImageData.fromMap(map['thumb']) : null,
      backDrop:
          map['backDrop'] != null ? List<ImageData>.from(map['backDrop']?.map((x) => ImageData.fromMap(x))) : null,
      logo: map['logo'] != null ? ImageData.fromMap(map['logo']) : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory ImagesData.fromJson(String source) => ImagesData.fromMap(json.decode(source));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ImagesData &&
        other.primary?.hash == primary?.hash &&
        other.backDrop?.length == backDrop?.length &&
        other.logo?.hash == logo?.hash;
  }

  @override
  int get hashCode => Object.hash(primary?.hash, Object.hashAll(backDrop?.map((e) => e.hash) ?? []), logo?.hash);
}

final String _sessionNonce = DateTime.now().millisecondsSinceEpoch.toRadixString(36);

class ImageData {
  final String path;
  final String hash;
  final String key;
  ImageData({
    this.path = '',
    this.hash = '',
    this.key = '',
  });

  /// Built once and kept.
  ///
  /// Every widget that draws a picture asks for this in its `build`, and a
  /// window being dragged to a new size is a build per frame for every poster
  /// on screen. A provider equal to the one before it costs no decode, but it
  /// is still an object made and an image stream resolved each time; the same
  /// object is simply recognised.
  ImageProvider? _imageProvider;
  ImageProvider? _nonCachedImageProvider;

  ImageProvider _providerFor(String cacheKey) {
    if (path.startsWith("http")) {
      return CachedNetworkImageProvider(
        cacheKey: cacheKey,
        cacheManager: CustomCacheManager.instance,
        path,
      );
    } else {
      return Image.file(
        key: Key(key),
        File(path),
      ).image;
    }
  }

  ImageProvider get imageProvider => _imageProvider ??= _providerFor(key);

  /// Not trusted across runs, but stable within one.
  ///
  /// The key was a fresh [UniqueKey] on every read, which no cache can ever
  /// hit: each rebuild of the widget fetched and decoded the picture again.
  /// The image tag is already part of [key], so a picture that changes on the
  /// server changes key on its own.
  ImageProvider get nonCachedImageProvider => _nonCachedImageProvider ??= _providerFor('$key-$_sessionNonce');

  @override
  String toString() => 'ImageData(path: $path, hash: $hash, key: $key)';

  ImageData copyWith({
    String? path,
    String? hash,
    String? key,
  }) {
    return ImageData(
      path: path ?? this.path,
      hash: hash ?? this.hash,
      key: key ?? this.key,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'hash': hash,
      'key': key,
    };
  }

  factory ImageData.fromMap(Map<String, dynamic> map) {
    return ImageData(
      path: map['path'] ?? '',
      hash: map['hash'] ?? '',
      key: map['key'] ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory ImageData.fromJson(String source) => ImageData.fromMap(json.decode(source));
}

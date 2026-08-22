import 'package:flutter/material.dart';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:fladder/util/localization_helper.dart';

/// How much room the app is allowed to spend keeping artwork close to hand.
///
/// Two caches sit behind every poster. The disk cache decides whether a picture
/// has to be fetched from the server again; the memory cache decides whether it
/// has to be decoded again. Both were small enough that browsing a library of
/// any size evicted images faster than you could scroll back to them, which is
/// what made the app feel slow: not the network, but the same handful of
/// pictures being fetched and decoded over and over.
enum ImageCacheSize {
  /// What the app used to do, kept for small disks and old phones.
  small(
    objects: 256,
    stalePeriod: Duration(days: 3),
    memoryBytes: 100 << 20,
    memoryEntries: 1000,
  ),

  /// Enough for a few libraries' worth of browsing to stay resident.
  balanced(
    objects: 2000,
    stalePeriod: Duration(days: 30),
    memoryBytes: 256 << 20,
    memoryEntries: 2000,
  ),

  /// For a desktop with disk to spare that you would rather never saw a
  /// placeholder twice.
  large(
    objects: 6000,
    stalePeriod: Duration(days: 90),
    memoryBytes: 512 << 20,
    memoryEntries: 4000,
  );

  const ImageCacheSize({
    required this.objects,
    required this.stalePeriod,
    required this.memoryBytes,
    required this.memoryEntries,
  });

  /// How many files the disk cache keeps before it starts evicting.
  final int objects;

  /// How long a cached file is trusted before it is fetched again.
  final Duration stalePeriod;

  /// What decoded images may occupy in memory. A 2000px backdrop is about 9MB
  /// once decoded, so this is the number that decides how far you can scroll
  /// back before the app has to decode one again.
  final int memoryBytes;

  final int memoryEntries;

  /// Roughly what the disk cache will grow to, for the settings screen to show.
  /// Artwork averages out near 200KB across posters, logos and backdrops.
  int get approximateDiskBytes => objects * 200 * 1024;

  String label(BuildContext context) => switch (this) {
        ImageCacheSize.small => context.localized.imageCacheSizeSmall,
        ImageCacheSize.balanced => context.localized.imageCacheSizeBalanced,
        ImageCacheSize.large => context.localized.imageCacheSizeLarge,
      };

  /// "Balanced — up to about 390 MB on disk, 256 MB in memory". Spelled out
  /// because "more cache" means nothing without knowing what it costs.
  String description(BuildContext context) =>
      '${label(context)} — ${_mb(approximateDiskBytes)} on disk, ${_mb(memoryBytes)} in memory';

  static String _mb(int bytes) => '${(bytes / (1 << 20)).round()} MB';
}

class CustomCacheManager {
  static const key = 'customCacheKey';

  static ImageCacheSize _current = ImageCacheSize.balanced;

  static CacheManager instance = _build(_current);

  static CacheManager _build(ImageCacheSize size) => CacheManager(
        Config(
          key,
          stalePeriod: size.stalePeriod,
          maxNrOfCacheObjects: size.objects,
          fileService: HttpFileService(),
        ),
      );

  /// Applies a size to both caches.
  ///
  /// The memory limits take effect immediately. The disk cache has to be built
  /// again to change its limits, and the old one is disposed first so the two
  /// never hold the same database open at once. Images already handed out keep
  /// the old manager alive until they are done with it, which is harmless — it
  /// is the same files on disk either way.
  static void apply(ImageCacheSize size) {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = size.memoryBytes
      ..maximumSize = size.memoryEntries;

    if (size == _current) return;
    _current = size;

    final previous = instance;
    instance = _build(size);
    previous.dispose();
  }
}

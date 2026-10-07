import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'package:chudder/models/settings/arguments_model.dart';
import 'package:chudder/util/artwork_cache_repository.dart';
import 'package:chudder/util/localization_helper.dart';

/// How much room the app is allowed to spend keeping artwork close to hand.
///
/// Two caches sit behind every poster. The disk cache decides whether a picture
/// has to be fetched from the server again; the memory cache decides whether it
/// has to be decoded again. Both were small enough that browsing a library of
/// any size evicted images faster than you could scroll back to them, which is
/// what made the app feel slow: not the network, but the same handful of
/// pictures being fetched and decoded over and over.
///
/// The memory figures are a desktop's; a phone and a television are held to
/// less by [ArtworkDevice], as decoded pictures live in RAM they do not have.
enum ImageCacheSize {
  /// For small disks and old phones.
  small(objects: 500, memoryBytes: 100 << 20, memoryEntries: 1000),

  /// Enough for a few libraries' worth of browsing to stay resident.
  balanced(objects: 4000, memoryBytes: 256 << 20, memoryEntries: 2000),

  /// For a desktop with disk to spare that you would rather never saw a
  /// placeholder twice.
  large(objects: 12000, memoryBytes: 512 << 20, memoryEntries: 4000),

  /// Every picture that is shown is kept, until [ImageKeepTime] lets it go.
  everything(objects: null, memoryBytes: 1024 << 20, memoryEntries: 6000);

  const ImageCacheSize({
    required this.objects,
    required this.memoryBytes,
    required this.memoryEntries,
  });

  /// How many pictures the disk cache keeps before it starts evicting the
  /// least recently shown. Null for no limit.
  final int? objects;

  /// What decoded images may occupy in memory on a desktop. A 2000px backdrop
  /// is about 9MB once decoded, so this is the number that decides how far you
  /// can scroll back before the app has to decode one again.
  final int memoryBytes;

  final int memoryEntries;

  /// The default for the device the app runs on.
  static ImageCacheSize get forDevice => switch (ArtworkDevice.current) {
        ArtworkDevice.desktop => ImageCacheSize.large,
        ArtworkDevice.phone || ArtworkDevice.television => ImageCacheSize.balanced,
      };

  /// Roughly what the disk cache will grow to, for the settings screen to show.
  /// Now that posters are asked for at the size they are drawn, a real cache
  /// averaged 71KB a picture - posters near 45KB, backdrops near 350KB - so
  /// 100KB leaves room for a library heavier on backdrops.
  int? get approximateDiskBytes => objects == null ? null : objects! * 100 * 1024;

  String label(BuildContext context) => switch (this) {
        ImageCacheSize.small => context.localized.imageCacheSizeSmall,
        ImageCacheSize.balanced => context.localized.imageCacheSizeBalanced,
        ImageCacheSize.large => context.localized.imageCacheSizeLarge,
        ImageCacheSize.everything => context.localized.imageCacheSizeEverything,
      };

  /// "Balanced - up to about 390 MB on disk, 256 MB in memory". Spelled out
  /// because "more cache" means nothing without knowing what it costs.
  String description(BuildContext context) {
    final memory = formatBytes(ArtworkDevice.current.memoryBytes(this));
    final disk = approximateDiskBytes;
    return disk == null
        ? context.localized.imageCacheSizeUnlimitedDescription(label(context), memory)
        : context.localized.imageCacheSizeDescription(label(context), formatBytes(disk), memory);
  }
}

/// How long a picture is kept after it was last shown.
enum ImageKeepTime {
  week(Duration(days: 7)),
  month(Duration(days: 30)),
  threeMonths(Duration(days: 90)),
  year(Duration(days: 365)),
  forever(null);

  const ImageKeepTime(this.duration);

  final Duration? duration;

  /// A century stands in for forever: the cache wants a duration.
  Duration get stalePeriod => duration ?? const Duration(days: 36500);

  String label(BuildContext context) => switch (this) {
        ImageKeepTime.week => context.localized.imageKeepTimeWeek,
        ImageKeepTime.month => context.localized.imageKeepTimeMonth,
        ImageKeepTime.threeMonths => context.localized.imageKeepTimeThreeMonths,
        ImageKeepTime.year => context.localized.imageKeepTimeYear,
        ImageKeepTime.forever => context.localized.imageKeepTimeForever,
      };
}

/// What a kind of picture is cached as.
enum ImageCachePolicy {
  /// In the main cache, under its size and keep time.
  keep,

  /// In a cache of its own that lets a picture go a day after it was shown.
  day,

  /// In a cache of its own that is emptied every time the app starts.
  session;

  String label(BuildContext context) => switch (this) {
        ImageCachePolicy.keep => context.localized.imageCachePolicyKeep,
        ImageCachePolicy.day => context.localized.imageCachePolicyDay,
        ImageCachePolicy.session => context.localized.imageCachePolicySession,
      };
}

/// The pictures that can be cached differently from library artwork.
enum ImageKind {
  /// Posters, backdrops, logos and people from the server.
  library,

  /// Seerr and everything else from outside the server: TMDB posters,
  /// avatars, artwork offered when editing metadata.
  discover,

  /// Photos opened full size.
  photos,

  /// Chapter pictures.
  chapters;

  /// Which kind [url] is. The server's pictures all live under `/Images/`;
  /// anything else came from somewhere else.
  static ImageKind of(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    if (path.contains('/Images/Chapter')) return ImageKind.chapters;
    if (path.contains('/Images/')) return ImageKind.library;
    return ImageKind.discover;
  }
}

/// What the app runs on, as far as the memory for decoded pictures goes.
enum ArtworkDevice {
  desktop,
  phone,
  television;

  static ArtworkDevice get current {
    if (kIsWeb) return ArtworkDevice.desktop;
    if (leanBackMode) return ArtworkDevice.television;
    if (Platform.isAndroid || Platform.isIOS) return ArtworkDevice.phone;
    return ArtworkDevice.desktop;
  }

  /// A phone gets at most a quarter gigabyte, a television box - often 2 GB
  /// of RAM, which the video decoder wants - an eighth.
  int memoryBytes(ImageCacheSize size) => switch (this) {
        ArtworkDevice.desktop => size.memoryBytes,
        ArtworkDevice.phone => size.memoryBytes.clamp(0, 256 << 20),
        ArtworkDevice.television => size.memoryBytes.clamp(0, 128 << 20),
      };

  int memoryEntries(ImageCacheSize size) => switch (this) {
        ArtworkDevice.desktop => size.memoryEntries,
        ArtworkDevice.phone => size.memoryEntries.clamp(0, 2000),
        ArtworkDevice.television => size.memoryEntries.clamp(0, 1000),
      };
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  return '${(bytes / (1 << 20)).round()} MB';
}

class CustomCacheManager {
  static const key = 'customCacheKey';
  static const _dayKey = 'imageCacheDay';
  static const _sessionKey = 'imageCacheSession';

  /// Every network picture goes through this; it hands each one to the cache
  /// its kind is set to.
  static final BaseCacheManager instance = _ArtworkCacheRouter(null);

  /// For pictures [ImageKind.of] cannot tell apart by their address: a photo
  /// opened full size is the same URL shape as a poster.
  static BaseCacheManager forKind(ImageKind kind) => _routers[kind] ??= _ArtworkCacheRouter(kind);
  static final Map<ImageKind, BaseCacheManager> _routers = {};

  static ImageCacheSize _size = ImageCacheSize.forDevice;
  static ImageKeepTime _keepTime = ImageKeepTime.threeMonths;
  static Map<ImageKind, ImageCachePolicy> _policies = const {};

  static _Cache? _keep;
  static _Cache? _day;
  static _Cache? _session;
  static Timer? _sweepScheduled;

  static BaseCacheManager _managerFor(ImageKind kind) => _cacheFor(kind).manager;

  static _Cache _cacheFor(ImageKind kind) => switch (_policies[kind] ?? ImageCachePolicy.keep) {
        ImageCachePolicy.keep => _keep ??= _buildKeep(),
        ImageCachePolicy.day => _day ??= _Cache.build(
            _dayKey,
            stalePeriod: const Duration(days: 1),
            objects: 2000,
          ),
        ImageCachePolicy.session => _session ??= _Cache.build(
            _sessionKey,
            stalePeriod: const Duration(days: 1),
            objects: 1000,
            wipeFirst: true,
          ),
      };

  static _Cache _buildKeep() => _Cache.build(
        key,
        stalePeriod: _keepTime.stalePeriod,
        objects: _size.objects,
        movedFromTemp: true,
      );

  static Iterable<_Cache> get _built => [_keep, _day, _session].nonNulls;

  /// Applies the settings to every cache.
  ///
  /// The memory limits take effect immediately. The main disk cache has to be
  /// built again to change its limits, and the old one is disposed first so
  /// the two never hold the same index open at once. Pictures already handed
  /// out keep the old manager alive until they are done with it, which is
  /// harmless - it is the same files on disk either way.
  static void configure({
    required ImageCacheSize size,
    required ImageKeepTime keepTime,
    required Map<ImageKind, ImageCachePolicy> policies,
  }) {
    final device = ArtworkDevice.current;
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = device.memoryBytes(size)
      ..maximumSize = device.memoryEntries(size);

    _policies = policies;
    if (!kIsWeb) _sweepScheduled ??= Timer(const Duration(seconds: 30), sweepOrphans);

    if (size == _size && keepTime == _keepTime) return;
    _size = size;
    _keepTime = keepTime;

    final previous = _keep;
    _keep = null;
    previous?.manager.dispose();
  }

  /// Deletes the files no cache lists any more: pictures evicted before the
  /// index kept full paths, which the cache manager never managed to delete -
  /// a cache listing 2000 pictures, 139 MB, sat in a folder of 16,000 files
  /// and 1.27 GB. Files younger than an hour are left alone, as a download
  /// being written is not listed yet.
  static Future<void> sweepOrphans({Duration minimumAge = const Duration(hours: 1)}) async {
    if (kIsWeb) return;
    var deleted = 0;
    for (final cache in [_keep ??= _buildKeep(), ..._built.where((c) => c != _keep)]) {
      deleted += await cache.sweep(minimumAge);
    }
    // What is left of the old location when it could not be moved.
    try {
      final old = Directory(join((await getTemporaryDirectory()).path, key));
      final current = await _Cache.folderFor(key);
      if (old.path != current.path && await old.exists()) await old.delete(recursive: true);
    } catch (e) {
      log('Image cache: could not remove the old folder: $e');
    }
    if (deleted > 0) log('Image cache: deleted $deleted files no cache lists');
  }

  /// What every artwork cache occupies on disk.
  static Future<int> diskUsage() async {
    if (kIsWeb) return 0;
    var total = 0;
    for (final name in [key, _dayKey, _sessionKey]) {
      final folder = await _Cache.folderFor(name);
      if (!await folder.exists()) continue;
      await for (final entity in folder.list()) {
        if (entity is File) {
          try {
            total += await entity.length();
          } on FileSystemException {
            continue;
          }
        }
      }
    }
    return total;
  }

  /// Empties every artwork cache, on disk and in memory. Downloads keep their
  /// own artwork.
  static Future<void> clear() async {
    for (final cache in [_keep ??= _buildKeep(), ..._built.where((c) => c != _keep)]) {
      await cache.manager.emptyCache();
    }
    await sweepOrphans(minimumAge: Duration.zero);
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }
}

/// One disk cache: its manager, index and folder.
class _Cache {
  _Cache(this.manager, this.repository, this.folder);

  final CacheManager manager;
  final ArtworkCacheRepository? repository;
  final Future<Directory> folder;

  static Future<Directory> folderFor(String key) async => Directory(join((await getApplicationCacheDirectory()).path, key));

  static _Cache build(
    String key, {
    required Duration stalePeriod,
    required int? objects,
    bool movedFromTemp = false,
    bool wipeFirst = false,
  }) {
    if (kIsWeb) {
      return _Cache(
        CacheManager(Config(key, stalePeriod: stalePeriod, maxNrOfCacheObjects: objects ?? 1 << 30)),
        null,
        Future.value(Directory('')),
      );
    }
    final folder = _prepare(key, movedFromTemp: movedFromTemp, wipeFirst: wipeFirst);
    // Whoever needs the folder hears of a failure; nothing else should.
    folder.ignore();
    final repository = ArtworkCacheRepository(
      directory: () => folder,
      databaseName: key,
      legacy: movedFromTemp ? _legacyIndex : null,
    );
    final manager = CacheManager(Config(
      key,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: objects ?? 1 << 30,
      repo: repository,
      fileSystem: _FolderFileSystem(folder),
      fileService: HttpFileService(),
    ));
    return _Cache(manager, repository, folder);
  }

  /// The folder, moved out of the system temp folder - which Windows' Storage
  /// Sense and cleanup tools empty - into the app's own cache folder.
  static Future<Directory> _prepare(String key, {required bool movedFromTemp, required bool wipeFirst}) async {
    final folder = await folderFor(key);
    if (wipeFirst) {
      try {
        if (await folder.exists()) await folder.delete(recursive: true);
        await ArtworkCacheRepository(directory: () async => folder, databaseName: key).deleteDataFile();
      } on FileSystemException catch (e) {
        log('Image cache: could not empty $key: $e');
      }
    }
    if (movedFromTemp && !await folder.exists()) {
      final old = Directory(join((await getTemporaryDirectory()).path, key));
      if (old.path != folder.path && await old.exists()) {
        try {
          await folder.parent.create(recursive: true);
          await old.rename(folder.path);
        } on FileSystemException {
          // Another drive: the sweep deletes it, and the pictures are fetched
          // again.
        }
      }
    }
    await folder.create(recursive: true);
    return folder;
  }

  /// The index flutter_cache_manager kept before: SQLite where sqflite runs,
  /// a JSON file elsewhere.
  static CacheInfoRepository _legacyIndex() {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      return CacheObjectProvider(databaseName: CustomCacheManager.key);
    }
    return JsonCacheInfoRepository(databaseName: CustomCacheManager.key);
  }

  Future<int> sweep(Duration minimumAge) async {
    final repository = this.repository;
    if (repository == null) return 0;
    var deleted = 0;
    try {
      await repository.open();
      final Set<String> listed;
      try {
        listed = await repository.fileNames();
      } finally {
        await repository.close();
      }
      final directory = await folder;
      if (!await directory.exists()) return 0;
      final cutoff = DateTime.now().subtract(minimumAge);
      await for (final entity in directory.list()) {
        if (entity is! File || listed.contains(basename(entity.path))) continue;
        try {
          if ((await entity.lastModified()).isAfter(cutoff)) continue;
          await entity.delete();
          deleted++;
        } on FileSystemException {
          continue;
        }
      }
    } catch (e) {
      log('Image cache sweep failed: $e');
    }
    return deleted;
  }
}

/// A cache folder that may not be the system temp folder
/// [IOFileSystem] insists on.
class _FolderFileSystem implements FileSystem {
  _FolderFileSystem(this._folder);

  final Future<Directory> _folder;
  static const _fs = LocalFileSystem();

  @override
  Future<fs.File> createFile(String name) async {
    final folder = await _folder;
    // Asked for every picture that is saved. The asynchronous check is a
    // round trip to the I/O service and back through the event loop, on the
    // thread that is drawing the scroll those pictures are arriving during;
    // this one is a single stat.
    if (!folder.existsSync()) await folder.create(recursive: true);
    // The index hands out full paths, which join keeps as they are.
    return _fs.file(join(folder.path, name));
  }
}

/// Hands each picture to the cache its kind is set to.
class _ArtworkCacheRouter extends BaseCacheManager {
  _ArtworkCacheRouter(this.kind);

  /// Null to tell by the address.
  final ImageKind? kind;

  BaseCacheManager _for(String url) => CustomCacheManager._managerFor(kind ?? ImageKind.of(url));

  /// For lookups by key alone: every cache that exists, main first.
  Iterable<BaseCacheManager> get _all {
    final built = CustomCacheManager._built.map((c) => c.manager);
    return built.isEmpty ? [CustomCacheManager._managerFor(ImageKind.library)] : built;
  }

  @override
  Future<fs.File> getSingleFile(String url, {String? key, Map<String, String>? headers}) =>
      _for(url).getSingleFile(url, key: key ?? url, headers: headers ?? const {});

  @override
  // ignore: deprecated_member_use
  Stream<FileInfo> getFile(String url, {String? key, Map<String, String>? headers}) =>
      // ignore: deprecated_member_use
      _for(url).getFile(url, key: key ?? url, headers: headers ?? const {});

  @override
  Stream<FileResponse> getFileStream(String url,
          {String? key, Map<String, String>? headers, bool withProgress = false}) =>
      _for(url).getFileStream(url, key: key, headers: headers, withProgress: withProgress);

  @override
  Future<FileInfo> downloadFile(String url, {String? key, Map<String, String>? authHeaders, bool force = false}) =>
      _for(url).downloadFile(url, key: key, authHeaders: authHeaders, force: force);

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async {
    for (final manager in _all) {
      final info = await manager.getFileFromCache(key, ignoreMemCache: ignoreMemCache);
      if (info != null) return info;
    }
    return null;
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) async {
    for (final manager in _all) {
      final info = await manager.getFileFromMemory(key);
      if (info != null) return info;
    }
    return null;
  }

  @override
  Future<fs.File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) =>
      _for(url).putFile(url, fileBytes, key: key, eTag: eTag, maxAge: maxAge, fileExtension: fileExtension);

  @override
  Future<fs.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) =>
      _for(url).putFileStream(url, source, key: key, eTag: eTag, maxAge: maxAge, fileExtension: fileExtension);

  @override
  Future<void> removeFile(String key) async {
    for (final manager in _all) {
      await manager.removeFile(key);
    }
  }

  @override
  Future<void> emptyCache() => CustomCacheManager.clear();

  /// Shared; the caches behind it are disposed when they are rebuilt.
  @override
  Future<void> dispose() async {}
}

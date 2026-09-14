import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:cached_network_image/cached_network_image.dart' show MultiImageStreamCompleter;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:chudder/util/custom_cache_manager.dart';

/// A server picture from the disk cache when it is there, and from the server
/// when it is not - decoded from the downloaded bytes straight away, with the
/// copy for the disk cache written alongside instead of in front.
///
/// [CachedNetworkImageProvider] does the same job through the cache manager,
/// which streams a download into a file chunk by chunk, records it, and only
/// then reads the file back to decode it: a dozen trips between the UI isolate
/// and the file system per picture before it can be shown, taken turns with
/// the screen the picture is for. On the home screen's 54 pictures that was
/// twice the time of the downloads themselves.
///
/// The same cache, keys and freshness rules, so either can read what the
/// other wrote: a cached picture past its `Cache-Control` age is shown and
/// then replaced once the server has answered, and one the server no longer
/// has is dropped from the cache. Native only; the web uses the browser's.
@immutable
class ArtworkImageProvider extends ImageProvider<ArtworkImageProvider> {
  const ArtworkImageProvider(this.url, {required this.cacheKey});

  final String url;
  final String cacheKey;

  @override
  Future<ArtworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ArtworkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(ArtworkImageProvider key, ImageDecoderCallback decode) {
    return MultiImageStreamCompleter(
      codec: _codecs(key, decode),
      scale: 1.0,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<ArtworkImageProvider>('Image key', key),
      ],
    );
  }

  Stream<ui.Codec> _codecs(ArtworkImageProvider key, ImageDecoderCallback decode) async* {
    try {
      await for (final bytes in ArtworkLoader.instance.load(url, cacheKey)) {
        yield await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    } catch (_) {
      // Not remembered as failed: the next time it is drawn it is asked for
      // again.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is ArtworkImageProvider && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'ArtworkImageProvider("$url", key: $cacheKey)';
}

/// The loading behind [ArtworkImageProvider]. Shared, so that one picture
/// asked for twice at once - a poster and a resized copy of it - is fetched
/// once.
class ArtworkLoader {
  ArtworkLoader({
    BaseCacheManager Function()? cache,
    FileService Function()? service,
  })  : _cache = cache ?? (() => CustomCacheManager.instance),
        _service = service ?? (() => CustomCacheManager.fileService);

  static final ArtworkLoader instance = ArtworkLoader();

  final BaseCacheManager Function() _cache;
  final FileService Function() _service;

  /// As many downloads at once as the cache manager allowed. More was measured
  /// slower: the HTTP and TLS work of every download runs on the UI isolate,
  /// and thirty at once starved the screen they were for.
  static const int maxConcurrent = 10;

  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  /// Downloads in flight, and downloaded bytes not yet on disk, by key.
  final Map<String, Future<Uint8List>> _inFlight = {};

  /// The picture for [key]: the cached copy first, then the server's when the
  /// cached one was missing or stale.
  Stream<Uint8List> load(String url, String key) async* {
    final pending = _inFlight[key];
    if (pending != null) {
      yield await pending;
      return;
    }

    final cache = _cache();
    FileInfo? cached;
    try {
      cached = await cache.getFileFromCache(key);
    } catch (_) {
      cached = null;
    }

    Uint8List? cachedBytes;
    if (cached != null) {
      try {
        cachedBytes = await cached.file.readAsBytes();
      } catch (_) {
        cachedBytes = null;
      }
      if (cachedBytes != null) {
        yield cachedBytes;
        if (!cached.validTill.isBefore(DateTime.now())) return;
      }
    }

    try {
      yield await _download(url, key, cache);
    } on HttpExceptionWithStatus catch (error) {
      if (error.statusCode == HttpStatus.notFound) {
        unawaited(cache.removeFile(key).then((_) {}, onError: (_) {}));
      }
      if (cachedBytes == null || error.statusCode == HttpStatus.notFound) rethrow;
    } catch (_) {
      // Offline with a stale copy: the copy stands.
      if (cachedBytes == null) rethrow;
    }
  }

  Future<Uint8List> _download(String url, String key, BaseCacheManager cache) {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    late final Future<Uint8List> download;
    void forget() {
      if (identical(_inFlight[key], download)) _inFlight.remove(key);
    }

    download = _fetch(url, key, cache).then(
      (fetched) {
        // Until the copy is on disk the bytes stay here, so that asking again
        // meanwhile does not find the cache empty and download it twice.
        fetched.written.whenComplete(forget);
        return fetched.bytes;
      },
      onError: (Object error, StackTrace stack) {
        forget();
        Error.throwWithStackTrace(error, stack);
      },
    );
    _inFlight[key] = download;
    return download;
  }

  Future<({Uint8List bytes, Future<void> written})> _fetch(String url, String key, BaseCacheManager cache) async {
    await _acquire();
    final FileServiceResponse response;
    final Uint8List bytes;
    try {
      response = await _service().get(url);
      if (response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.accepted) {
        // Read to the end, so the connection goes back to the pool.
        await response.content.drain<void>().catchError((_) {});
        throw HttpExceptionWithStatus(
          response.statusCode,
          'Invalid statusCode: ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.content) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    } finally {
      _release();
    }

    // Behind the decode rather than in front of it.
    final maxAge = response.validTill.difference(DateTime.now());
    final extension = response.fileExtension.replaceFirst('.', '');
    final written = cache
        .putFile(
          url,
          bytes,
          key: key,
          eTag: response.eTag,
          maxAge: maxAge.isNegative ? Duration.zero : maxAge,
          fileExtension: extension.isEmpty ? 'file' : extension,
        )
        .then<void>((_) {}, onError: (_) {});
    return (bytes: bytes, written: written);
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }
}

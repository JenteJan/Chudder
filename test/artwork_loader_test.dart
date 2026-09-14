import 'dart:async';
import 'dart:io' show HttpStatus;
import 'dart:typed_data';

// The cache manager's own file type; it comes with flutter_cache_manager.
// ignore: depend_on_referenced_packages
import 'package:file/file.dart';
// ignore: depend_on_referenced_packages
import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/util/artwork_image_provider.dart';

/// A disk cache in memory, with the calls counted.
class FakeCache implements BaseCacheManager {
  final fs = MemoryFileSystem();
  final entries = <String, ({String path, DateTime validTill})>{};
  final puts = <String>[];
  final removed = <String>[];
  Completer<void>? holdWrites;

  void seed(String key, List<int> bytes, {required DateTime validTill}) {
    final file = fs.file('$key.jpg')..writeAsBytesSync(bytes);
    entries[key] = (path: file.path, validTill: validTill);
  }

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async {
    final entry = entries[key];
    if (entry == null) return null;
    return FileInfo(fs.file(entry.path), FileSource.Cache, entry.validTill, key);
  }

  @override
  Future<File> putFile(String url, Uint8List fileBytes,
      {String? key, String? eTag, Duration maxAge = const Duration(days: 30), String fileExtension = 'file'}) async {
    await holdWrites?.future;
    puts.add('$key.$fileExtension');
    final file = fs.file('$key.$fileExtension')..writeAsBytesSync(fileBytes);
    entries[key!] = (path: file.path, validTill: DateTime.now().add(maxAge));
    return file;
  }

  @override
  Future<void> removeFile(String key) async {
    removed.add(key);
    entries.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class FakeResponse implements FileServiceResponse {
  FakeResponse(this.statusCode, this.bytes);
  @override
  final int statusCode;
  final List<int> bytes;
  @override
  Stream<List<int>> get content => Stream.fromIterable([bytes.sublist(0, bytes.length ~/ 2), bytes.sublist(bytes.length ~/ 2)]);
  @override
  int? get contentLength => bytes.length;
  @override
  String? get eTag => '"e"';
  @override
  String get fileExtension => '.jpeg';
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 365));
}

class FakeService extends FileService {
  final requests = <String>[];
  int status = HttpStatus.ok;
  List<int> body = [1, 2, 3, 4];
  Object? failWith;
  Completer<void>? hold;

  @override
  Future<FileServiceResponse> get(String url, {Map<String, String>? headers}) async {
    requests.add(url);
    await hold?.future;
    if (failWith != null) throw failWith!;
    return FakeResponse(status, body);
  }
}

void main() {
  late FakeCache cache;
  late FakeService service;
  late ArtworkLoader loader;

  setUp(() {
    cache = FakeCache();
    service = FakeService();
    loader = ArtworkLoader(cache: () => cache, service: () => service);
  });

  test('a picture not on disk is downloaded once, shown, and then written to the cache', () async {
    final pictures = await loader.load('https://s/p', 'k').toList();
    expect(pictures, [
      [1, 2, 3, 4]
    ]);
    expect(service.requests, ['https://s/p']);
    await pumpEventQueue();
    expect(cache.puts, ['k.jpeg']);
  });

  test('the same picture asked for twice at once is one download', () async {
    service.hold = Completer();
    final first = loader.load('https://s/p', 'k').toList();
    await pumpEventQueue();
    final second = loader.load('https://s/p', 'k').toList();
    await pumpEventQueue();
    service.hold!.complete();
    expect(await first, hasLength(1));
    expect(await second, hasLength(1));
    expect(service.requests, hasLength(1));
  });

  test('asked for again before the copy is on disk, it is not downloaded again', () async {
    cache.holdWrites = Completer();
    await loader.load('https://s/p', 'k').toList();
    await loader.load('https://s/p', 'k').toList();
    expect(service.requests, hasLength(1));
    cache.holdWrites!.complete();
    await pumpEventQueue();
    await loader.load('https://s/p', 'k').toList();
    expect(service.requests, hasLength(1), reason: 'on disk by now');
  });

  test('a fresh cached picture is not asked for', () async {
    cache.seed('k', [9], validTill: DateTime.now().add(const Duration(days: 1)));
    expect(await loader.load('https://s/p', 'k').toList(), [
      [9]
    ]);
    expect(service.requests, isEmpty);
  });

  test('a stale cached picture is shown, then replaced by the server copy', () async {
    cache.seed('k', [9], validTill: DateTime.now().subtract(const Duration(days: 1)));
    expect(await loader.load('https://s/p', 'k').toList(), [
      [9],
      [1, 2, 3, 4]
    ]);
    expect(service.requests, hasLength(1));
  });

  test('offline, a stale cached picture stands', () async {
    cache.seed('k', [9], validTill: DateTime.now().subtract(const Duration(days: 1)));
    service.failWith = Exception('offline');
    expect(await loader.load('https://s/p', 'k').toList(), [
      [9]
    ]);
  });

  test('a picture the server no longer has fails, and leaves the cache', () async {
    cache.seed('k', [9], validTill: DateTime.now().subtract(const Duration(days: 1)));
    service.status = HttpStatus.notFound;
    final seen = <List<int>>[];
    await expectLater(
      loader.load('https://s/p', 'k').forEach(seen.add),
      throwsA(isA<HttpExceptionWithStatus>()),
    );
    expect(seen, [
      [9]
    ]);
    await pumpEventQueue();
    expect(cache.removed, ['k']);
  });

  test('a failed download is not remembered', () async {
    service.failWith = Exception('offline');
    await expectLater(loader.load('https://s/p', 'k').toList(), throwsException);
    service.failWith = null;
    expect(await loader.load('https://s/p', 'k').toList(), hasLength(1));
    expect(service.requests, hasLength(2));
  });

  test('no more than ten downloads run at once', () async {
    service.hold = Completer();
    final loads = [for (var i = 0; i < 25; i++) loader.load('https://s/$i', 'k$i').toList()];
    await pumpEventQueue();
    expect(service.requests, hasLength(ArtworkLoader.maxConcurrent));
    service.hold!.complete();
    await Future.wait(loads);
    expect(service.requests, hasLength(25));
  });

  test('providers for the same key are the same picture to the image cache', () {
    expect(const ArtworkImageProvider('https://a', cacheKey: 'k'), const ArtworkImageProvider('https://b', cacheKey: 'k'));
    expect(const ArtworkImageProvider('https://a', cacheKey: 'k'), isNot(const ArtworkImageProvider('https://a', cacheKey: 'j')));
  });
}

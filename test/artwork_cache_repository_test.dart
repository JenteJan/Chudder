import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:file/file.dart' as fs;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';

import 'package:chudder/util/artwork_cache_repository.dart';

/// The folder the cache manager writes into, as the app's own file system does.
class _Folder implements FileSystem {
  _Folder(this.folder);
  final Directory folder;

  @override
  Future<fs.File> createFile(String name) async => const LocalFileSystem().file(p.join(folder.path, name));
}

void main() {
  // The Windows build ships its own SQLite; tests borrow it.
  final sqlite = File(p.join('build', 'windows', 'x64', 'runner', 'Release', 'sqlite3.dll'));
  if (Platform.isWindows && sqlite.existsSync()) {
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(sqlite.absolute.path));
  }

  late Directory root;
  late Directory folder;

  ArtworkCacheRepository repository({CacheInfoRepository Function()? legacy}) => ArtworkCacheRepository(
        directory: () async => folder,
        databaseName: 'artwork',
        legacy: legacy,
        openDatabase: (file) => NativeDatabase(file),
      );

  CacheObject object(String key, String name, {DateTime? touched}) => CacheObject(
        'https://server/Items/$key/Images/Primary',
        key: key,
        relativePath: name,
        validTill: DateTime.now().add(const Duration(days: 365)),
        touched: touched ?? DateTime.now(),
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artwork_cache_test');
    folder = await Directory(p.join(root.path, 'pictures')).create();
  });

  tearDown(() => root.delete(recursive: true));

  test('pictures are stored by name and handed out by full path', () async {
    final repo = repository();
    await repo.open();
    await repo.insert(object('a', 'a.jpg'));

    expect((await repo.get('a'))!.relativePath, p.join(folder.path, 'a.jpg'));
    expect(await repo.fileNames(), {'a.jpg'});
    await repo.close();
  });

  test('removing a picture deletes its file, not just its entry', () async {
    final repo = repository();
    final manager = CacheManager(Config('artwork', repo: repo, fileSystem: _Folder(folder)));
    final file = File(p.join(folder.path, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
    await repo.open();
    await repo.insert(object('a', 'a.jpg'));

    await manager.removeFile('a');

    expect(file.existsSync(), isFalse);
    expect(await repo.get('a'), isNull);
    await repo.close();
    await manager.dispose();
  });

  test('the least recently shown past the limit are the ones evicted', () async {
    final repo = repository();
    await repo.open();
    final old = DateTime.now().subtract(const Duration(days: 10));
    for (var i = 0; i < 5; i++) {
      await repo.insert(object('k$i', 'k$i.jpg', touched: old.add(Duration(hours: i))), setTouchedToNow: false);
    }

    final over = await repo.getObjectsOverCapacity(3);
    expect(over.map((o) => o.key), ['k1', 'k0']);
    await repo.close();
  });

  test('the old index is carried over once, and then removed', () async {
    final legacyFile = File(p.join(root.path, 'legacy.json'));
    final legacy = JsonCacheInfoRepository.withFile(legacyFile);
    await legacy.open();
    await legacy.insert(object('a', 'a.jpg'), setTouchedToNow: false);
    await legacy.close();
    expect(legacyFile.existsSync(), isTrue);

    final repo = repository(legacy: () => JsonCacheInfoRepository.withFile(legacyFile));
    await repo.open();

    expect((await repo.get('a'))?.relativePath, p.join(folder.path, 'a.jpg'));
    expect(legacyFile.existsSync(), isFalse);
    await repo.close();
  });
}

import 'dart:developer';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The index of an artwork cache, kept in SQLite on every platform.
///
/// flutter_cache_manager ships two indexes: SQLite through sqflite, which has
/// no Windows or Linux build, and on those a JSON file that is rewritten whole,
/// on the UI isolate, a few seconds after every change - 0.7 MB for 2000
/// pictures, and it grows with every picture kept. This one is drift, which
/// the app already ships everywhere, on its own background isolate.
///
/// It also stores each picture by its file name and hands it out by its full
/// path. The cache manager deletes an evicted picture with
/// `File(relativePath)`, which resolves against the working directory, so
/// with a bare file name the file was never deleted - only its index entry
/// was - and every picture ever evicted stayed on disk.
class ArtworkCacheRepository extends CacheInfoRepository {
  ArtworkCacheRepository({
    required this.directory,
    required this.databaseName,
    this.legacy,
    @visibleForTesting this.openDatabase,
  });

  /// Opens the database file; drift_flutter's background isolate unless set.
  final QueryExecutor Function(io.File file)? openDatabase;

  /// Where the pictures are.
  final Future<io.Directory> Function() directory;
  final String databaseName;

  /// The index this one replaces, carried over the first time it opens so the
  /// pictures already on disk are not fetched again.
  final CacheInfoRepository Function()? legacy;

  _ArtworkCacheDatabase? _db;
  String? _folder;
  int _connections = 0;
  Future<bool>? _opening;

  static const _table = 'cache_object';
  static const _columns = 'id, url, key, relative_path, e_tag, valid_till, touched, length';

  Future<io.File> _databaseFile() async => io.File(p.join((await directory()).parent.path, '$databaseName.sqlite'));

  @override
  Future<bool> exists() async => (await _databaseFile()).exists();

  @override
  Future<bool> open() {
    _connections++;
    return _opening ??= _open();
  }

  Future<bool> _open() async {
    final folder = await directory();
    _folder = folder.path;
    final file = await _databaseFile();
    final isNew = !await file.exists();
    _db = _ArtworkCacheDatabase(openDatabase?.call(file) ??
        driftDatabase(
          name: databaseName,
          native: DriftNativeOptions(databasePath: () async => file.path),
        ));
    if (isNew && legacy != null) await _carryOver(legacy!());
    return true;
  }

  Future<void> _carryOver(CacheInfoRepository previous) async {
    try {
      if (!await previous.exists()) return;
      await previous.open();
      final objects = await previous.getAllObjects();
      await _database.transaction(() async {
        for (final object in objects) {
          await insert(object, setTouchedToNow: false);
        }
      });
      await previous.close();
      await previous.deleteDataFile();
      // sqflite's deleteDataFile deletes nothing.
      if (previous is CacheObjectProvider) {
        final support = await getApplicationSupportDirectory();
        for (final suffix in ['', '-journal', '-wal', '-shm']) {
          final old = io.File(p.join(support.path, '$databaseName.db$suffix'));
          if (await old.exists()) await old.delete();
        }
      }
      log('Image cache: carried over ${objects.length} pictures from the old index');
    } catch (e) {
      // The pictures are fetched again, and the sweep deletes the old files.
      log('Image cache: could not carry over the old index: $e');
    }
  }

  @override
  Future<bool> close() async {
    if (_connections > 0) _connections--;
    if (_connections > 0) return false;
    final db = _db;
    _db = null;
    _opening = null;
    await db?.close();
    return true;
  }

  @override
  Future<void> deleteDataFile() async {
    final file = await _databaseFile();
    for (final path in [file.path, '${file.path}-wal', '${file.path}-shm']) {
      try {
        await io.File(path).delete();
      } on io.FileSystemException {
        // Not there.
      }
    }
  }

  _ArtworkCacheDatabase get _database {
    final db = _db;
    if (db == null) throw StateError('ArtworkCacheRepository used before open()');
    return db;
  }

  String _stored(String path) => p.basename(path);

  String _full(String name) => _folder == null ? name : p.join(_folder!, name);

  CacheObject _read(QueryRow row) => CacheObject(
        row.read<String>('url'),
        id: row.read<int>('id'),
        key: row.read<String>('key'),
        relativePath: _full(row.read<String>('relative_path')),
        eTag: row.readNullable<String>('e_tag'),
        validTill: DateTime.fromMillisecondsSinceEpoch(row.read<int>('valid_till')),
        touched: DateTime.fromMillisecondsSinceEpoch(row.read<int>('touched')),
        length: row.readNullable<int>('length'),
      );

  List<Variable<Object>> _values(CacheObject object, bool setTouchedToNow) => [
        Variable<String>(object.url),
        Variable<String>(object.key),
        Variable<String>(_stored(object.relativePath)),
        Variable<String>(object.eTag),
        Variable<int>(object.validTill.millisecondsSinceEpoch),
        Variable<int>((setTouchedToNow ? DateTime.now() : object.touched)?.millisecondsSinceEpoch ?? 0),
        Variable<int>(object.length),
      ];

  Future<List<CacheObject>> _select(String where, [List<Variable<Object>> args = const []]) async {
    final rows = await _database.customSelect('SELECT $_columns FROM $_table $where', variables: args).get();
    return rows.map(_read).toList();
  }

  @override
  Future<dynamic> updateOrInsert(CacheObject cacheObject) =>
      cacheObject.id == null ? insert(cacheObject) : update(cacheObject);

  @override
  Future<CacheObject> insert(CacheObject cacheObject, {bool setTouchedToNow = true}) async {
    final id = await _database.customInsert(
      'INSERT OR REPLACE INTO $_table (url, key, relative_path, e_tag, valid_till, touched, length) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      variables: _values(cacheObject, setTouchedToNow),
    );
    return cacheObject.copyWith(id: id);
  }

  @override
  Future<CacheObject?> get(String key) async =>
      (await _select('WHERE key = ?', [Variable<String>(key)])).firstOrNull;

  @override
  Future<int> delete(int id) =>
      _database.customUpdate('DELETE FROM $_table WHERE id = ?', variables: [Variable<int>(id)]);

  @override
  Future<int> deleteAll(Iterable<int> ids) async {
    if (ids.isEmpty) return 0;
    return _database.customUpdate('DELETE FROM $_table WHERE id IN (${ids.join(',')})');
  }

  @override
  Future<int> update(CacheObject cacheObject, {bool setTouchedToNow = true}) => _database.customUpdate(
        'UPDATE $_table SET url = ?, key = ?, relative_path = ?, e_tag = ?, valid_till = ?, touched = ?, length = ? '
        'WHERE id = ?',
        variables: [..._values(cacheObject, setTouchedToNow), Variable<int>(cacheObject.id)],
      );

  @override
  Future<List<CacheObject>> getAllObjects() => _select('');

  /// The least recently shown beyond [capacity], a hundred at a time, and
  /// never one shown in the last day - as the sqflite index does.
  @override
  Future<List<CacheObject>> getObjectsOverCapacity(int capacity) => _select(
        'WHERE touched < ? ORDER BY touched DESC LIMIT 100 OFFSET ?',
        [
          Variable<int>(DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch),
          Variable<int>(capacity),
        ],
      );

  @override
  Future<List<CacheObject>> getOldObjects(Duration maxAge) => _select(
        'WHERE touched < ? LIMIT 100',
        [Variable<int>(DateTime.now().subtract(maxAge).millisecondsSinceEpoch)],
      );

  /// The file names the index lists, for sweeping the folder.
  Future<Set<String>> fileNames() async {
    final rows = await _database.customSelect('SELECT relative_path FROM $_table').get();
    return {for (final row in rows) row.read<String>('relative_path')};
  }

  Future<int> count() async =>
      (await _database.customSelect('SELECT COUNT(*) AS c FROM $_table').getSingle()).read<int>('c');
}

class _ArtworkCacheDatabase extends GeneratedDatabase {
  _ArtworkCacheDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  Iterable<DatabaseSchemaEntity> get allSchemaEntities => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS cache_object (
              id INTEGER PRIMARY KEY,
              url TEXT NOT NULL,
              key TEXT NOT NULL UNIQUE,
              relative_path TEXT NOT NULL,
              e_tag TEXT,
              valid_till INTEGER NOT NULL,
              touched INTEGER NOT NULL,
              length INTEGER
            )''');
          await customStatement('CREATE INDEX IF NOT EXISTS cache_object_touched ON cache_object (touched)');
        },
      );
}

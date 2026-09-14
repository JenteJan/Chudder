import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/providers/book_viewer_provider.dart';

void main() {
  test('a book\'s image pages are unpacked on an isolate, in archive order, and the archive is let go', () async {
    final directory = await Directory.systemTemp.createTemp('book_pages_test');
    addTearDown(() => directory.delete(recursive: true));

    final archive = Archive()
      ..addFile(ArchiveFile('001.jpg', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('notes.txt', 2, [4, 5]))
      ..addFile(ArchiveFile('002.PNG', 1, [6]));
    final archiveFile = File('${directory.path}/archive.book')..writeAsBytesSync(ZipEncoder().encode(archive));

    final archivePath = archiveFile.path;
    final directoryPath = directory.path;
    final pages = await Isolate.run(() => extractBookPages(archivePath, directoryPath));

    expect(pages, ['$directoryPath/Pages/001.jpg', '$directoryPath/Pages/002.PNG']);
    expect(File(pages.first).readAsBytesSync(), [1, 2, 3]);
    expect(File(pages.last).readAsBytesSync(), [6]);
    // Closed, so the downloaded archive can be deleted afterwards (Windows
    // refuses to delete an open file).
    archiveFile.deleteSync();
  });
}

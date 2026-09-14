import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/widgets.dart';

import 'package:archive/archive_io.dart';
import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/book_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/user_provider.dart';

class BookViewerModel {
  final BookModel? book;
  final bool loading;
  final List<String> pages;
  final int currentPage;
  BookViewerModel({
    this.book,
    this.loading = false,
    this.pages = const [],
    this.currentPage = 0,
  });

  int get clampedCurrentPage => currentPage.clamp(0, pages.length);

  BookViewerModel copyWith({
    ValueGetter<BookModel?>? book,
    bool? loading,
    List<String>? pages,
    int? currentPage,
  }) {
    return BookViewerModel(
      book: book != null ? book.call() : this.book,
      loading: loading ?? this.loading,
      pages: pages ?? this.pages,
      currentPage: currentPage ?? this.currentPage,
    );
  }
}

/// Writes the pages (the image files) of the book archive at [archivePath] to
/// `Pages/` under [directory], and returns their paths in archive order.
List<String> extractBookPages(String archivePath, String directory) {
  final inputStream = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(inputStream);
    final List<String> imagesPath = [];
    for (var file in archive.files) {
      //filter out files with image extension
      if (file.isFile && _isImageFile(file.name)) {
        final path = '$directory/Pages/${file.name}';
        final outputStream = OutputFileStream(path);
        file.writeContent(outputStream);
        imagesPath.add(path);
        outputStream.close();
      }
    }
    return imagesPath;
  } finally {
    inputStream.closeSync();
  }
}

//Simple file checker
bool _isImageFile(String filePath) {
  final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'tif', 'webp'];
  final fileExtension = filePath.toLowerCase().split('.').last;
  return imageExtensions.contains(fileExtension);
}

final bookViewerProvider = StateNotifierProvider<BookViewerNotifier, BookViewerModel>((ref) {
  return BookViewerNotifier(ref);
});

class BookViewerNotifier extends StateNotifier<BookViewerModel> {
  BookViewerNotifier(this.ref) : super(BookViewerModel());

  final Ref ref;

  late Directory savedDirectory;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<List<String>?> fetchBook(BookModel? book) async {
    final oldState = state.copyWith();
    state = state.copyWith(loading: true, book: () => book, currentPage: 0);

    //Stop and cleanup old state
    await _stopPlaybackOldState(oldState);

    if (state.book == null) return null;
    try {
      final response = await api.itemsItemIdDownloadGet(itemId: state.book?.id);

      final bookDirectory = state.book?.id;

      String tempDir = (await getTemporaryDirectory()).path;
      savedDirectory = Directory('$tempDir/$bookDirectory');
      await savedDirectory.create();
      File bookFile = File('${savedDirectory.path}/archive.book');
      await bookFile.writeAsBytes(response.bodyBytes);

      // Unpacking is synchronous file work the size of the whole book - tens
      // or hundreds of megabytes for a comic - so it runs on an isolate of its
      // own instead of freezing the app while it happens.
      final archivePath = bookFile.path;
      final directoryPath = savedDirectory.path;
      final imagesPath = await Isolate.run(() => extractBookPages(archivePath, directoryPath));
      state = state.copyWith(pages: imagesPath, loading: false);
      await bookFile.delete();
      return imagesPath;
    } catch (e) {
      log(e.toString());
      state = state.copyWith(loading: false);
    }
    return null;
  }

  Timer? _progressReport;

  /// The page is kept at once; the server hears about it a moment after the
  /// last turn. Flicking through a book used to be one request per page.
  Future<Response?> updatePlayback(int page) async {
    if (state.book == null) return null;
    if (page == state.currentPage) return null;
    state = state.copyWith(currentPage: page);
    _progressReport?.cancel();
    _progressReport = Timer(const Duration(seconds: 2), () {
      _progressReport = null;
      _reportProgress().ignore();
    });
    return null;
  }

  Future<Response?> _reportProgress() {
    if (state.book == null) return Future.value(null);
    return api.sessionsPlayingStoppedPost(
      body: PlaybackStopInfo(
        itemId: state.book?.id,
        mediaSourceId: state.book?.id,
        positionTicks: state.clampedCurrentPage * 10000,
      ),
    );
  }

  Future<Response?> _stopPlaybackOldState(BookViewerModel oldState) async {
    if (oldState.book == null) return null;

    if (oldState.clampedCurrentPage < oldState.pages.length && oldState.pages.isNotEmpty) {
      await ref.read(userProvider.notifier).markAsPlayed(false, oldState.book?.id ?? "");
    }

    final response = await api.sessionsPlayingStoppedPost(
        body: PlaybackStopInfo(
      itemId: oldState.book?.id,
      mediaSourceId: oldState.book?.id,
      positionTicks: oldState.clampedCurrentPage * 10000,
    ));

    if (oldState.clampedCurrentPage >= oldState.pages.length && oldState.pages.isNotEmpty) {
      await ref.read(userProvider.notifier).markAsPlayed(true, oldState.book?.id ?? "");
    }

    await _cleanUp();
    return response;
  }

  Future<Response?> stopPlayback() async {
    if (state.book == null) return null;

    if (state.clampedCurrentPage < state.pages.length && state.pages.isNotEmpty) {
      await ref.read(userProvider.notifier).markAsPlayed(false, state.book?.id ?? "");
    }

    final response = await api.sessionsPlayingStoppedPost(
        body: PlaybackStopInfo(
      itemId: state.book?.id,
      mediaSourceId: state.book?.id,
      positionTicks: state.clampedCurrentPage * 10000,
    ));

    if (state.clampedCurrentPage >= state.pages.length && state.pages.isNotEmpty) {
      await ref.read(userProvider.notifier).markAsPlayed(true, state.book?.id ?? "");
    }

    await _cleanUp();
    return response;
  }

  Future<void> _cleanUp() async {
    try {
      for (var i = 0; i < state.pages.length; i++) {
        final file = File(state.pages[i]);
        if (file.existsSync()) {
          await file.delete();
        }
      }
      final directoryExists = await savedDirectory.exists();
      if (directoryExists) {
        await savedDirectory.delete(recursive: true);
      }
    } catch (e) {
      log(e.toString());
    }
  }

  void setPage(double value) => state = state.copyWith(currentPage: value.toInt());

  void setBook(BookModel book) => state = state.copyWith(
        book: () => book,
      );
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/util/alist_download_client.dart';
import 'package:fladder/util/alist_sha256_verifier.dart';

part 'update_downloader_provider.g.dart';

enum UpdateDownloadStateKind {
  idle,
  downloading,
  verifying,
  ready,
  installing,
  done,
  failed,
}

enum DownloadFailure { network, cancelled, integrity, installRefused, unsupported }

class UpdateDownloadState {
  final UpdateDownloadStateKind kind;
  final double progress;
  final String? filePath;
  final DownloadFailure? failure;
  final String? message;

  const UpdateDownloadState({
    required this.kind,
    this.progress = 0,
    this.filePath,
    this.failure,
    this.message,
  });

  static const idle = UpdateDownloadState(kind: UpdateDownloadStateKind.idle);
}

@Riverpod(keepAlive: true)
AlistDownloadClient alistDownloadClient(Ref ref) =>
    BackgroundDownloaderAlistClient();

typedef AlistInstaller = Future<bool> Function(String filePath);

@Riverpod(keepAlive: true)
AlistInstaller alistInstaller(Ref ref) {
  return (path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  };
}

@Riverpod(keepAlive: true)
class UpdateDownloader extends _$UpdateDownloader {
  StreamSubscription<AlistDownloadEvent>? _sub;
  String? _activeTaskId;

  @override
  UpdateDownloadState build() {
    ref.onDispose(() {
      _sub?.cancel();
    });
    return UpdateDownloadState.idle;
  }

  Future<void> start({
    required String version,
    required String url,
    required String filename,
    String? expectedSha256,
  }) async {
    await _sub?.cancel();
    _sub = null;

    await _wipeCacheDir();

    state = const UpdateDownloadState(
      kind: UpdateDownloadStateKind.downloading,
      progress: 0,
    );

    _activeTaskId = version;
    final client = ref.read(alistDownloadClientProvider);
    _sub = client
        .download(taskId: version, url: url, filename: filename)
        .listen((event) async {
      switch (event.kind) {
        case AlistDownloadEventKind.progress:
          state = UpdateDownloadState(
            kind: UpdateDownloadStateKind.downloading,
            progress: event.progress,
          );
        case AlistDownloadEventKind.complete:
          if (expectedSha256 != null && expectedSha256.isNotEmpty) {
            state = const UpdateDownloadState(
              kind: UpdateDownloadStateKind.verifying,
            );
            final ok = await verifySha256(File(event.filePath!), expectedSha256);
            if (!ok) {
              state = const UpdateDownloadState(
                kind: UpdateDownloadStateKind.failed,
                failure: DownloadFailure.integrity,
              );
              return;
            }
          }
          state = UpdateDownloadState(
            kind: UpdateDownloadStateKind.ready,
            filePath: event.filePath,
          );
        case AlistDownloadEventKind.failed:
          state = UpdateDownloadState(
            kind: UpdateDownloadStateKind.failed,
            failure: DownloadFailure.network,
            message: event.error,
          );
        case AlistDownloadEventKind.cancelled:
          state = UpdateDownloadState.idle;
      }
    });
  }

  Future<void> cancel() async {
    final id = _activeTaskId;
    if (id == null) return;
    final client = ref.read(alistDownloadClientProvider);
    await client.cancel(id);
  }

  Future<void> install() async {
    final ready = state;
    if (ready.kind != UpdateDownloadStateKind.ready ||
        ready.filePath == null) {
      return;
    }
    state = UpdateDownloadState(
      kind: UpdateDownloadStateKind.installing,
      filePath: ready.filePath,
    );
    final installer = ref.read(alistInstallerProvider);
    final ok = await installer(ready.filePath!);
    if (ok) {
      state = const UpdateDownloadState(kind: UpdateDownloadStateKind.done);
    } else {
      state = const UpdateDownloadState(
        kind: UpdateDownloadStateKind.failed,
        failure: DownloadFailure.installRefused,
      );
    }
  }

  Future<void> _wipeCacheDir() async {
    try {
      final cache = await getTemporaryDirectory();
      final dir = Directory(p.join(cache.path, 'updates'));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    } catch (_) {
      // best effort: if it fails, the downloader will still try to write
    }
  }
}

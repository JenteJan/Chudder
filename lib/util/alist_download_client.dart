import 'dart:async';

import 'package:background_downloader/background_downloader.dart' as bd;

enum AlistDownloadEventKind { progress, complete, failed, cancelled }

class AlistDownloadEvent {
  final AlistDownloadEventKind kind;
  final double progress;
  final String? filePath;
  final String? error;

  const AlistDownloadEvent._(this.kind, {this.progress = 0, this.filePath, this.error});

  factory AlistDownloadEvent.progress(double p) =>
      AlistDownloadEvent._(AlistDownloadEventKind.progress, progress: p);
  factory AlistDownloadEvent.complete(String filePath) =>
      AlistDownloadEvent._(AlistDownloadEventKind.complete, filePath: filePath);
  factory AlistDownloadEvent.failed(String error) =>
      AlistDownloadEvent._(AlistDownloadEventKind.failed, error: error);
  factory AlistDownloadEvent.cancelled() =>
      const AlistDownloadEvent._(AlistDownloadEventKind.cancelled);
}

abstract class AlistDownloadClient {
  Stream<AlistDownloadEvent> download({
    required String taskId,
    required String url,
    required String filename,
  });

  Future<void> cancel(String taskId);
}

class BackgroundDownloaderAlistClient implements AlistDownloadClient {
  @override
  Stream<AlistDownloadEvent> download({
    required String taskId,
    required String url,
    required String filename,
  }) {
    final controller = StreamController<AlistDownloadEvent>();

    final task = bd.DownloadTask(
      taskId: taskId,
      url: url,
      filename: filename,
      baseDirectory: bd.BaseDirectory.temporary,
      directory: 'updates',
      updates: bd.Updates.statusAndProgress,
      retries: 1,
    );

    unawaited(bd.FileDownloader().download(
      task,
      onStatus: (status) {
        switch (status) {
          case bd.TaskStatus.complete:
            // ignore: discarded_futures
            task.filePath().then((path) {
              controller.add(AlistDownloadEvent.complete(path));
              controller.close();
            });
          case bd.TaskStatus.canceled:
            controller.add(AlistDownloadEvent.cancelled());
            controller.close();
          case bd.TaskStatus.failed:
            controller.add(AlistDownloadEvent.failed('download failed'));
            controller.close();
          default:
            break;
        }
      },
      onProgress: (p) {
        if (p > 0 && p < 1) {
          controller.add(AlistDownloadEvent.progress(p));
        }
      },
    ));

    return controller.stream;
  }

  @override
  Future<void> cancel(String taskId) async {
    await bd.FileDownloader().cancelTaskWithId(taskId);
  }
}

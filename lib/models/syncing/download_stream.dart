import 'package:background_downloader/background_downloader.dart' as dl;

class DownloadStream {
  final String id;
  final dl.DownloadTask? task;
  final double progress;
  final String downloadSpeed;
  final bool isTranscoding;
  final dl.TaskStatus status;

  /// Why the download stopped, in the downloader's words, when it failed.
  /// Kept with the task record, so it is still there after a restart.
  final String? error;

  /// Time left as the downloader estimates it, while running.
  final Duration? timeRemaining;

  /// Whether the server lets this one be paused and picked up again - null
  /// until it has said. A transcode is made on the fly and cannot be: pausing
  /// one threw the partial file away and the retries started it from zero.
  final bool? canResume;

  DownloadStream({
    required this.id,
    this.task,
    this.progress = -1,
    this.downloadSpeed = "",
    this.isTranscoding = false,
    required this.status,
    this.error,
    this.timeRemaining,
    this.canResume,
  });

  DownloadStream.empty()
      : id = '',
        task = null,
        progress = -1,
        downloadSpeed = "",
        isTranscoding = false,
        status = dl.TaskStatus.notFound,
        error = null,
        timeRemaining = null,
        canResume = null;

  bool get hasDownload => progress != -1.0 && status != dl.TaskStatus.notFound && status != dl.TaskStatus.complete;

  bool get isEnqueuedOrDownloading => status == dl.TaskStatus.enqueued || status == dl.TaskStatus.running;

  /// Still on its way: running, waiting its turn, paused, or about to retry.
  bool get isPending =>
      status == dl.TaskStatus.enqueued ||
      status == dl.TaskStatus.running ||
      status == dl.TaskStatus.paused ||
      status == dl.TaskStatus.waitingToRetry;

  bool get isFailed => status == dl.TaskStatus.failed;

  /// Failed, or gone from the downloader without arriving: what the Downloads
  /// tab counts as failed, and what its retry button starts over.
  bool get needsRetry => isFailed || status == dl.TaskStatus.notFound;

  /// Pausing is only offered where it will not lose what has come down.
  bool get canPause => canResume == true && (status == dl.TaskStatus.running || status == dl.TaskStatus.enqueued);

  DownloadStream copyWith({
    String? id,
    dl.DownloadTask? task,
    double? progress,
    String? downloadSpeed,
    dl.TaskStatus? status,
    String? Function()? error,
    Duration? Function()? timeRemaining,
    bool? canResume,
  }) {
    return DownloadStream(
      id: id ?? this.id,
      task: task ?? this.task,
      progress: progress ?? this.progress,
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      status: status ?? this.status,
      error: error != null ? error() : this.error,
      timeRemaining: timeRemaining != null ? timeRemaining() : this.timeRemaining,
      canResume: canResume ?? this.canResume,
    );
  }

  @override
  String toString() {
    return 'DownloadStream(id: $id, task: $task, progress: $progress, status: $status, error: $error)';
  }
}

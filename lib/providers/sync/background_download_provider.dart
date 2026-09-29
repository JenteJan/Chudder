import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/models/syncing/download_failure.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/util/localization_helper.dart';

part 'background_download_provider.g.dart';

final itemDownloadGroup = "ITEM_DOWNLOAD_GROUP";

@Riverpod(keepAlive: true)
class BackgroundDownloader extends _$BackgroundDownloader {
  late StreamSubscription<TaskUpdate> updateListener;

  @override
  FileDownloader build() {
    ref.onDispose(
      () => updateListener.cancel(),
    );

    final maxDownloads = ref.read(clientSettingsProvider.select((value) => value.maxConcurrentDownloads));
    // The default persistent storage keeps task records in the app-support
    // directory, and merely constructing it asks path_provider for that
    // directory, which the browser does not have: an unhandled
    // MissingPluginException at every launch. Nothing downloads on the web,
    // so an in-memory store is all it needs.
    final downloader = FileDownloader(persistentStorage: kIsWeb ? _MemoryPersistentStorage() : null)
      ..configure(
        globalConfig: globalConfig(maxDownloads),
        androidConfig: (Config.runInForeground, Config.always),
      );
    updateListener = downloader.updates.listen(updateTask);
    // Task tracking persists to the app-support directory, which the browser
    // does not have: asking for it throws an unhandled MissingPluginException
    // at every launch, and there are no downloads to track on the web anyway.
    if (!kIsWeb) {
      _restore(downloader);
      // Only on a change. Applying it at every launch rescheduled whatever
      // was running, which restarts a transcode from the beginning; the
      // downloader keeps the last setting itself.
      ref.listen(
        clientSettingsProvider.select((value) => value.requireWifi),
        (_, requireWifi) => _applyWifiRequirement(downloader, requireWifi),
      );
    }
    return downloader;
  }

  /// Picks up where the last run left off.
  ///
  /// The task state used to live only in memory, so after Android had killed
  /// the app everything that was on its way showed as "not found", and 15
  /// seconds later the partial files were swept up as litter. The downloader
  /// keeps its own record of every task, with why it failed; reading that
  /// back, and re-queueing what the system killed mid-way, is what lets the
  /// Downloads tab say what actually happened while you were away.
  Future<void> _restore(FileDownloader downloader) async {
    try {
      await downloader.trackTasks();
      await downloader.resumeFromBackground();
      final records = await downloader.database.allRecords();
      for (final record in records) {
        final task = record.task;
        if (task is! DownloadTask) continue;
        if (record.status == TaskStatus.complete || record.status == TaskStatus.canceled) {
          await downloader.database.deleteRecordWithId(record.taskId);
          continue;
        }
        _apply(
          task,
          record.status,
          progress: record.progress,
          error: record.status == TaskStatus.failed || record.status == TaskStatus.notFound
              ? describeDownloadFailure(record.exception, null)
              : null,
        );
      }
      Timer(const Duration(seconds: 5), () async {
        try {
          await downloader.rescheduleKilledTasks();
        } catch (e) {
          debugPrint('Rescheduling killed downloads failed: $e');
        }
      });
    } catch (e) {
      debugPrint('Restoring downloads failed: $e');
    }
  }

  /// The Wi-Fi-only setting, applied to downloads already waiting as well as
  /// new ones: turning it off lets the ones held back for Wi-Fi start now.
  Future<void> _applyWifiRequirement(FileDownloader downloader, bool requireWifi) async {
    try {
      await downloader.requireWiFi(
        requireWifi ? RequireWiFi.asSetByTask : RequireWiFi.forNoTasks,
        rescheduleRunningTasks: false,
      );
    } catch (e) {
      debugPrint('Applying the Wi-Fi requirement failed: $e');
    }
  }

  /// Whether any download is still on its way according to the downloader's
  /// own records - which, unlike the in-memory state, survive a restart.
  Future<bool> hasUnfinishedTasks() async {
    if (kIsWeb) return false;
    try {
      final records = await state.database.allRecords();
      return records.any((record) => const [
            TaskStatus.enqueued,
            TaskStatus.running,
            TaskStatus.paused,
            TaskStatus.waitingToRetry,
          ].contains(record.status));
    } catch (_) {
      return true;
    }
  }

  /// Drops every trace of a task: its record, and what the screens show for
  /// it. For a download that was deleted or is about to be started afresh.
  Future<void> forget(String taskId) async {
    try {
      await state.database.deleteRecordWithId(taskId);
    } catch (_) {}
    _clear(taskId);
  }

  void updateTask(TaskUpdate update) {
    final task = update.task;
    if (task is! DownloadTask) return;
    switch (update) {
      case TaskStatusUpdate():
        final status = update.status;
        if (status == TaskStatus.complete || status == TaskStatus.canceled) {
          _clear(task.taskId);
          if (status == TaskStatus.complete) {
            // Its record has done its job; left behind, the next launch
            // would read it back for nothing.
            state.database.deleteRecordWithId(task.taskId).ignore();
          }
          ref.read(syncProvider.notifier).cleanupTemporaryFiles();
          return;
        }
        _apply(
          task,
          status,
          error: status == TaskStatus.failed || status == TaskStatus.notFound
              ? describeDownloadFailure(update.exception, update.responseStatusCode)
              : null,
        );
      case TaskProgressUpdate():
        final progress = update.progress;
        // Negative progress is how the downloader signals a failure or a
        // pause; the status update that goes with it says which.
        if (progress < 0) return;
        final next = ref.read(downloadTasksProvider(task.taskId)).copyWith(
              id: task.taskId,
              task: task,
              progress: progress > 0 && progress < 1 ? progress : null,
              downloadSpeed: update.hasNetworkSpeed ? update.networkSpeedAsString : null,
              timeRemaining: () => update.hasTimeRemaining ? update.timeRemaining : null,
            );
        _store(task.taskId, next);
    }
  }

  void _apply(DownloadTask task, TaskStatus status, {double? progress, String? error}) {
    final next = ref.read(downloadTasksProvider(task.taskId)).copyWith(
          id: task.taskId,
          task: task,
          status: status,
          progress: progress != null && progress > 0 && progress < 1 ? progress : null,
          error: () => error,
          timeRemaining: status == TaskStatus.running ? null : () => null,
        );
    _store(task.taskId, next);

    if (status == TaskStatus.running && next.canResume == null) _learnCanResume(task);

    ref.read(activeDownloadTasksProvider.notifier).update((state) {
      final others = state.where((element) => element.taskId != task.taskId).toList();
      return next.isPending ? [...others, task] : others;
    });
  }

  /// Asks once the server has answered whether this download can be paused
  /// without losing it, so the pause button is only shown where it works.
  Future<void> _learnCanResume(DownloadTask task) async {
    try {
      final canResume = await state.taskCanResume(task).timeout(const Duration(minutes: 1));
      final current = ref.read(downloadTasksProvider(task.taskId));
      if (current.id != task.taskId) return;
      _store(task.taskId, current.copyWith(canResume: canResume));
    } catch (_) {}
  }

  void _store(String taskId, DownloadStream stream) {
    ref.read(downloadTasksProvider(taskId).notifier).state = stream;
    ref.read(downloadQueueProvider.notifier).update((state) => {...state, taskId: stream});
  }

  void _clear(String taskId) {
    ref.read(downloadTasksProvider(taskId).notifier).state = DownloadStream.empty();
    ref.read(downloadQueueProvider.notifier).update((state) => Map.of(state)..remove(taskId));
    ref
        .read(activeDownloadTasksProvider.notifier)
        .update((state) => state.where((element) => element.taskId != taskId).toList());
  }

  void setMaxConcurrent(int value) {
    state.configure(
      globalConfig: globalConfig(value),
      androidConfig: (Config.runInForeground, Config.always),
    );
  }

  void updateTranslations(BuildContext context) async {
    if (kIsWeb) return;
    state.configureNotification(
      running: TaskNotification(context.localized.notificationDownloadingDownloading, '{filename}\n{networkSpeed}'),
      complete: TaskNotification(context.localized.notificationDownloadingFinished, '{filename}'),
      paused: TaskNotification(context.localized.notificationDownloadingPaused, '{filename}'),
      error: TaskNotification(context.localized.notificationDownloadingError, '{filename}'),
      progressBar: true,
    );
  }

  (String, dynamic) globalConfig(int value) => value == 0
      ? (
          Config.holdingQueue,
          (
            null,
            null,
            null,
          )
        )
      : (
          Config.holdingQueue,
          (
            //maxConcurrent
            value,
            //maxConcurrentByHost
            value,
            //maxConcurrentByGroup
            value,
          ),
        );
}

/// Task bookkeeping that lives and dies with the page. Web only.
class _MemoryPersistentStorage implements PersistentStorage {
  final _taskRecords = <String, TaskRecord>{};
  final _pausedTasks = <String, Task>{};
  final _resumeData = <String, ResumeData>{};

  @override
  Future<void> initialize() async {}

  @override
  (String, int) get currentDatabaseVersion => ('memory', 1);

  @override
  Future<(String, int)> get storedDatabaseVersion async => currentDatabaseVersion;

  @override
  Future<void> storeTaskRecord(TaskRecord record) async => _taskRecords[record.taskId] = record;

  @override
  Future<TaskRecord?> retrieveTaskRecord(String taskId) async => _taskRecords[taskId];

  @override
  Future<List<TaskRecord>> retrieveAllTaskRecords() async => _taskRecords.values.toList();

  @override
  Future<void> removeTaskRecord(String? taskId) async => taskId == null ? _taskRecords.clear() : _taskRecords.remove(taskId);

  @override
  Future<void> storePausedTask(Task task) async => _pausedTasks[task.taskId] = task;

  @override
  Future<Task?> retrievePausedTask(String taskId) async => _pausedTasks[taskId];

  @override
  Future<List<Task>> retrieveAllPausedTasks() async => _pausedTasks.values.toList();

  @override
  Future<void> removePausedTask(String? taskId) async => taskId == null ? _pausedTasks.clear() : _pausedTasks.remove(taskId);

  @override
  Future<void> storeResumeData(ResumeData resumeData) async => _resumeData[resumeData.taskId] = resumeData;

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async => _resumeData[taskId];

  @override
  Future<List<ResumeData>> retrieveAllResumeData() async => _resumeData.values.toList();

  @override
  Future<void> removeResumeData(String? taskId) async => taskId == null ? _resumeData.clear() : _resumeData.remove(taskId);
}

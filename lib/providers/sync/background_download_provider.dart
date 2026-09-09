import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/models/syncing/download_stream.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/util/localization_helper.dart';

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
    // Task tracking persists to the app-support directory, which the browser
    // does not have: asking for it throws an unhandled MissingPluginException
    // at every launch, and there are no downloads to track on the web anyway.
    if (!kIsWeb) downloader.trackTasks();
    updateListener = downloader.updates.listen(updateTask);
    return downloader;
  }

  void updateTask(TaskUpdate update) {
    switch (update) {
      case TaskStatusUpdate():
        final status = update.status;
        ref.read(downloadTasksProvider(update.task.taskId).notifier).update(
              (state) => state.copyWith(status: status),
            );

        if (status == TaskStatus.complete || status == TaskStatus.canceled) {
          ref.read(downloadTasksProvider(update.task.taskId).notifier).update((state) => DownloadStream.empty());
          ref
              .read(activeDownloadTasksProvider.notifier)
              .update((state) => state.where((element) => element.taskId != update.task.taskId).toList());

          ref.read(syncProvider.notifier).cleanupTemporaryFiles();
        }
      case TaskProgressUpdate():
        final progress = update.progress;
        ref.read(downloadTasksProvider(update.task.taskId).notifier).update(
              (state) => state.copyWith(
                progress: progress > 0 && progress < 1 ? progress : null,
                downloadSpeed: update.networkSpeedAsString,
              ),
            );
    }
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

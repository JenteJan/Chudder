import 'package:flutter/material.dart';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/album_model.dart';
import 'package:fladder/models/items/artist_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/syncing/download_stream.dart';
import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/providers/sync/background_download_provider.dart';
import 'package:fladder/providers/sync/sync_provider_helpers.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/util/localization_helper.dart';

const _cancellableStatuses = {
  TaskStatus.canceled,
  TaskStatus.failed,
  TaskStatus.enqueued,
  TaskStatus.waitingToRetry,
};

class SyncLabel extends ConsumerWidget {
  final String? label;
  final TaskStatus status;
  const SyncLabel({this.label, required this.status, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: status.color(context).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label ?? status.name(context),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: status.color(context),
              ),
        ),
      ),
    );
  }
}

class SyncProgressBar extends ConsumerWidget {
  final SyncedItem item;
  final DownloadStream task;
  const SyncProgressBar({required this.item, required this.task, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadStatus = task.status;
    final downloadProgress = task.progress;
    final downloadSpeed = task.downloadSpeed;
    final downloadTask = task.task;

    if (!task.hasDownload) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IgnorePointer(
          child: Row(
            spacing: 8,
            children: [
              Text(downloadStatus.name(context)),
              if (downloadSpeed.isNotEmpty) Opacity(opacity: 0.45, child: Text("($downloadSpeed)")),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Flexible(
              child: IgnorePointer(
                child: TweenAnimationBuilder(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  tween: Tween<double>(
                    begin: 0,
                    end: downloadProgress,
                  ),
                  builder: (context, value, child) => LinearProgressIndicator(
                    minHeight: 8,
                    value: value,
                    color: downloadStatus.color(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Text(
              "${(downloadProgress * 100).toStringAsFixed(0)}%",
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)),
            ),
            if (downloadTask != null) ...{
              if (downloadStatus != TaskStatus.paused && downloadStatus != TaskStatus.enqueued)
                IconButton(
                  onPressed: () => ref.read(backgroundDownloaderProvider).pause(downloadTask),
                  icon: const Icon(IconsaxPlusBold.pause),
                ),
              if (downloadStatus == TaskStatus.paused) ...[
                IconButton(
                  onPressed: () => ref.read(syncProvider.notifier).deleteFullSyncFiles(item, downloadTask),
                  icon: const Icon(IconsaxPlusBold.stop),
                ),
                IconButton(
                  onPressed: () => ref.read(backgroundDownloaderProvider).resume(downloadTask),
                  icon: const Icon(IconsaxPlusBold.play),
                ),
              ],
              if (_cancellableStatuses.contains(downloadStatus)) ...[
                IconButton(
                  onPressed: () => ref.read(syncProvider.notifier).deleteFullSyncFiles(item, downloadTask),
                  icon: const Icon(IconsaxPlusBold.stop),
                ),
              ],
            },
          ],
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class SyncSubtitle extends ConsumerWidget {
  final SyncedItem syncItem;
  final List<SyncedItem> children;
  const SyncSubtitle({
    required this.syncItem,
    this.children = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseItem = syncItem.itemModel;
    final syncStatus = ref
        .watch(syncDownloadStatusProvider(syncItem, children).select((value) => value?.status ?? TaskStatus.notFound));
    return Container(
      decoration: BoxDecoration(
          color: syncStatus.color(context).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Material(
        color: const Color.fromARGB(0, 208, 130, 130),
        textStyle: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: syncStatus.color(context)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: switch (baseItem) {
            // Counts describe what is DOWNLOADED, not the show's catalogue.
            // Syncing one episode writes a row for every episode of the
            // series, so counting rows announced "Episodes: 106 | Synced: 0"
            // for a single download - which reads as though the whole show is
            // on its way down.
            SeasonModel _ => Builder(
                builder: (context) {
                  final downloaded = children
                      .where((element) => element.itemModel is EpisodeModel && element.videoFile.existsSync())
                      .length;
                  return Text("${context.localized.episode(2)}: $downloaded");
                },
              ),
            SeriesModel _ => Builder(
                builder: (context) {
                  final downloadedEpisodes = children
                      .where((element) => element.itemModel is EpisodeModel && element.videoFile.existsSync())
                      .toList();
                  final seasons = downloadedEpisodes
                      .map((element) => (element.itemModel as EpisodeModel).season)
                      .toSet()
                      .length;
                  return Text(
                    [
                      "${context.localized.season(2)}: $seasons",
                      "${context.localized.episode(2)}: ${downloadedEpisodes.length}",
                    ].join('\n'),
                  );
                },
              ),
            ArtistModel _ => Builder(
                builder: (context) {
                  final itemBaseModels = children.map((e) => e.itemModel);
                  final albums = itemBaseModels.whereType<AlbumModel>().length;
                  final tracks = itemBaseModels.whereType<AudioModel>().length;
                  final syncedTracks = children
                      .where((element) => element.itemModel is AudioModel && element.videoFile.existsSync())
                      .length;
                  return Text(
                    [
                      '${context.localized.musicAlbum(2)}: $albums',
                      '${context.localized.audio(2)}: $tracks | ${context.localized.syncStatusSynced}: $syncedTracks',
                    ].join('\n'),
                  );
                },
              ),
            AlbumModel _ => Builder(
                builder: (context) {
                  final tracks = children.where((element) => element.itemModel is AudioModel).length;
                  final syncedTracks = children
                      .where((element) => element.itemModel is AudioModel && element.videoFile.existsSync())
                      .length;
                  return Text(
                    '${context.localized.audio(2)}: $tracks | ${context.localized.syncStatusSynced}: $syncedTracks',
                  );
                },
              ),
            PlaylistModel _ => Builder(
                builder: (context) {
                  final totalTracks = children.where((element) => element.itemModel is AudioModel).length;
                  final syncedTracks = children
                      .where((element) => element.itemModel is AudioModel && element.videoFile.existsSync())
                      .length;
                  return Text(
                    '${context.localized.audio(2)}: $totalTracks | ${context.localized.syncStatusSynced}: $syncedTracks',
                  );
                },
              ),
            _ => Text(syncStatus.name(context)),
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' hide ConnectionState;

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/providers/sync/downloads_overview_provider.dart';
import 'package:chudder/providers/sync/sync_removal_plan.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/screens/shared/default_alert_dialog.dart';
import 'package:chudder/screens/syncing/downloads_widgets.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/play_item_helpers.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/util/size_formatting.dart';

/// Opens the download [syncItem] belongs to: the whole film, show or album,
/// whichever part of it was asked about.
Future<void> showSyncItemDetails(
  BuildContext context,
  SyncedItem syncItem,
  WidgetRef ref,
) async {
  SyncedItem root = syncItem;
  // Up to the top: an episode's page asks about the episode, and the thing
  // to manage is the show it came down with.
  for (var i = 0; i < 4 && root.parentId != null; i++) {
    final parent = await ref.read(syncProvider.notifier).getSyncedItem(root.parentId);
    if (parent == null) break;
    root = parent;
  }
  if (!context.mounted) return;
  await showDialogAdaptive(
    context: context,
    builder: (context) => DownloadedItemView(rootId: root.id, fallback: root),
  );
  if (context.mounted) context.refreshData();
}

/// One download, managed: what it is, what of it is on the device, and every
/// action on it written out - nothing behind an unlabelled icon that has to
/// be guessed at.
class DownloadedItemView extends ConsumerWidget {
  const DownloadedItemView({required this.rootId, required this.fallback, super.key});

  final String rootId;
  final SyncedItem fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localized = context.localized;
    final overview = ref.watch(downloadsOverviewProvider);
    final entry = overview.valueOrNull?.entries.where((entry) => entry.root.id == rootId).firstOrNull;
    final root = entry?.root ?? fallback;
    final model = root.itemModel;

    final files = entry?.files ?? const <SyncedItem>[];
    final several = entry?.hasSeveral ?? false;
    final missing = files.where((file) => !file.videoFile.existsSync()).length;
    final watchedOnDevice = entry?.watchedOnDevice ?? 0;
    final next = entry?.next?.itemModel;
    final single = !several ? files.firstOrNull : null;

    void openPage() {
      if (model == null) return;
      Navigator.of(context).pop();
      model.navigateTo(context, ref: ref);
    }

    final quality = entry == null || entry.onDevice.isEmpty
        ? null
        : [
            if (entry.bytes > 0) entry.bytes.byteFormat,
            entry.transcoded
                ? [entry.heightLabel, localized.downloadsConverted].nonNulls.join(' ')
                : [localized.qualityOptionsOriginal, entry.heightLabel].nonNulls.join(' '),
          ].nonNulls.join("  ·  ");

    return LayoutBuilder(builder: (context, constraints) {
      final posterWidth = constraints.maxWidth < 420 ? 96.0 : 128.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: localized.close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(IconsaxPlusLinear.arrow_left_2),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(localized.syncDetails, style: theme.textTheme.titleMedium)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    // The picture is the way to the item's own page, as it
                    // is everywhere else in the app.
                    SizedBox(
                      width: posterWidth,
                      child: AspectRatio(
                        aspectRatio: 2 / 3,
                        child: FocusButton(
                          onTap: model != null ? openPage : null,
                          borderRadius: FladderTheme.smallShape.borderRadius,
                          child: ClipRRect(
                            borderRadius: FladderTheme.smallShape.borderRadius,
                            child: FladderImage(image: root.images?.primary, decodeHeight: 400),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Text(
                            model?.name ?? localized.unknown,
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (entry != null) _Summary(entry: entry, single: single),
                          if (quality != null && quality.isNotEmpty)
                            Text(
                              quality,
                              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (next != null)
                      FilledButton.icon(
                        autofocus: true,
                        onPressed: () {
                          Navigator.of(context).pop();
                          next.play(context, ref);
                        },
                        icon: const Icon(IconsaxPlusBold.play),
                        label: Text(next is EpisodeModel
                            ? "${localized.downloadsPlay} ${next.seasonEpisodeLabel(localized)}"
                            : (next.progress > 0 ? localized.downloadResume : localized.downloadsPlay)),
                      ),
                    if (model != null)
                      OutlinedButton.icon(
                        onPressed: openPage,
                        icon: const Icon(IconsaxPlusLinear.info_circle),
                        label: Text(localized.downloadsOpenDetails),
                      ),
                    if (single != null) ..._singleFileActions(context, ref, single),
                  ],
                ),
                if (several) ...[
                  const SizedBox(height: 24),
                  ..._fileRows(context, files),
                ],
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (missing > 0 && several)
                      FilledButton.tonalIcon(
                        onPressed: () => ref.read(syncProvider.notifier).downloadRemaining(root),
                        icon: const Icon(IconsaxPlusLinear.import),
                        label: Text(localized.downloadsGetRemaining(missing)),
                      ),
                    if (watchedOnDevice > 0 && several)
                      FilledButton.tonalIcon(
                        onPressed: () => _confirmDeleteWatched(context, ref, root, watchedOnDevice),
                        icon: const Icon(IconsaxPlusLinear.tick_circle),
                        label: Text(localized.downloadsDeleteWatched(watchedOnDevice)),
                      ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                      onPressed: () => _confirmRemove(context, ref, root),
                      icon: const Icon(IconsaxPlusLinear.trash),
                      label: Text(localized.downloadsRemove),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// A film has one file, so what can be done to it sits with the other
  /// buttons, in words.
  List<Widget> _singleFileActions(BuildContext context, WidgetRef ref, SyncedItem file) {
    final localized = context.localized;
    final task = ref.watch(downloadTasksProvider(file.id));
    if (task.isPending) {
      return [
        if (task.canPause)
          OutlinedButton.icon(
            onPressed: () => ref.read(syncProvider.notifier).pauseTask(task),
            icon: const Icon(IconsaxPlusLinear.pause),
            label: Text(localized.downloadPause),
          ),
        if (task.status == TaskStatus.paused)
          OutlinedButton.icon(
            onPressed: () => ref.read(syncProvider.notifier).resumeTask(task),
            icon: const Icon(IconsaxPlusLinear.play),
            label: Text(localized.downloadResume),
          ),
        OutlinedButton.icon(
          onPressed: () => stopDownload(context, ref, file.id),
          icon: const Icon(IconsaxPlusLinear.stop_circle),
          label: Text(localized.downloadStop),
        ),
      ];
    }
    if (task.isFailed) {
      return [
        OutlinedButton.icon(
          onPressed: () => ref.read(syncProvider.notifier).retryDownload(file.id),
          icon: const Icon(IconsaxPlusLinear.refresh),
          label: Text(localized.retry),
        ),
      ];
    }
    if (!file.videoFile.existsSync()) {
      return [
        FilledButton.tonalIcon(
          onPressed: () => ref.read(syncProvider.notifier).syncFile(file, false),
          icon: const Icon(IconsaxPlusLinear.import),
          label: Text(localized.downloadsDownload),
        ),
      ];
    }
    return const [];
  }

  /// The files grouped the way they are watched: a heading per season, with
  /// how much of it is here.
  List<Widget> _fileRows(BuildContext context, List<SyncedItem> files) {
    final rows = <Widget>[];
    final seasons = <int?, List<SyncedItem>>{};
    for (final file in files) {
      final model = file.itemModel;
      seasons.putIfAbsent(model is EpisodeModel ? model.season : null, () => []).add(file);
    }
    for (final MapEntry(key: season, value: seasonFiles) in seasons.entries) {
      if (season != null) {
        final have = seasonFiles.where((file) => file.videoFile.existsSync()).length;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            "${context.localized.season(1)} $season  ·  ${context.localized.downloadsOnDeviceCount(have, seasonFiles.length)}",
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ));
      }
      rows.addAll(seasonFiles.map((file) => _FileRow(file: file)));
    }
    return rows;
  }

  Future<void> _confirmDeleteWatched(BuildContext context, WidgetRef ref, SyncedItem root, int count) {
    final localized = context.localized;
    return showDefaultAlertDialog(
      context,
      localized.downloadsDeleteWatchedTitle,
      localized.downloadsDeleteWatchedDesc(count),
      (dialogContext) async {
        Navigator.of(dialogContext).pop();
        await ref.read(syncProvider.notifier).deleteWatched(root);
      },
      localized.delete,
      (dialogContext) => Navigator.of(dialogContext).pop(),
      localized.cancel,
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref, SyncedItem root) async {
    final localized = context.localized;
    final sync = ref.read(syncProvider.notifier);

    Future<void> removeAfterConfirm() => showDefaultAlertDialog(
          context,
          localized.syncRemoveDataTitle,
          localized.syncRemoveDataDesc,
          (dialogContext) async {
            Navigator.of(dialogContext).pop();
            final removed = await sync.removeSync(context, root);
            if (removed && context.mounted) Navigator.of(context).pop();
          },
          localized.delete,
          (dialogContext) => Navigator.of(dialogContext).pop(),
          localized.cancel,
        );

    if (!SyncNotifier.isMusicRoot(root)) return removeAfterConfirm();

    // Music is shared: a track sits in its album, its artist and any number of
    // playlists, and taking it out of one must not quietly take it from the
    // rest. What would stay under "keep what is used elsewhere" is asked for
    // first, so the dialog can say so.
    final shared = await sync.planMusicRemovalFor(root, MusicRemovalMode.keepShared);
    if (!context.mounted) return;

    final MusicRemovalMode? mode;
    if (root.itemModel?.type == FladderItemType.playlist) {
      mode = await _askRemovalMode(
        context,
        title: localized.downloadsRemovePlaylistTitle,
        description: [
          localized.downloadsRemovePlaylistDesc,
          if (shared.keep.isNotEmpty) localized.downloadsTracksStay(shared.keep.length),
        ].join('\n\n'),
        options: [
          (localized.syncPlaylistKeepTracks, MusicRemovalMode.keepAll),
          (localized.downloadsRemoveUnusedTracks, MusicRemovalMode.keepShared),
        ],
      );
    } else if (shared.keep.isEmpty) {
      return removeAfterConfirm();
    } else {
      final names = await sync.playlistNames(shared.affectedPlaylists);
      if (!context.mounted) return;
      mode = await _askRemovalMode(
        context,
        title: localized.downloadsRemoveSharedTitle,
        description: localized.downloadsRemoveSharedDesc(shared.keep.length, names.join(', ')),
        options: [
          (localized.downloadsRemoveEverything, MusicRemovalMode.everything),
          (localized.downloadsKeepPlaylistTracks, MusicRemovalMode.keepShared),
        ],
      );
    }
    if (mode == null) return;

    final removed = await sync.removeMusic(context, root, mode);
    if (removed && context.mounted) Navigator.of(context).pop();
  }

  /// A choice with more than two answers, which the plain alert dialog cannot
  /// hold. Cancel is the one a D-pad lands on.
  Future<MusicRemovalMode?> _askRemovalMode(
    BuildContext context, {
    required String title,
    required String description,
    required List<(String, MusicRemovalMode)> options,
  }) {
    return showDialog<MusicRemovalMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            autofocus: AdaptiveLayout.inputDeviceOf(dialogContext) == InputDevice.dPad,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.localized.cancel),
          ),
          for (final (label, mode) in options)
            ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(mode), child: Text(label)),
        ],
      ),
    );
  }
}

/// Where the download as a whole stands, in one line with an icon.
class _Summary extends ConsumerWidget {
  const _Summary({required this.entry, this.single});

  final DownloadedEntry entry;
  final SyncedItem? single;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localized = context.localized;
    final file = single;
    if (file != null) {
      final task = ref.watch(downloadTasksProvider(file.id));
      final onDevice = file.videoFile.existsSync();
      if (task.isPending || task.isFailed) {
        final status = describeDownload(context, ref, task, expectedBytes: expectedDownloadBytes(task, file));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 6,
          children: [
            _StatusLine(icon: status.icon, text: status.text, color: status.color),
            if (task.status == TaskStatus.running || task.status == TaskStatus.paused)
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: task.progress >= 0 ? task.progress : null, minHeight: 4),
              ),
          ],
        );
      }
      return _StatusLine(
        icon: onDevice ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.import,
        text: onDevice ? localized.downloadsOnThisDevice : localized.downloadsNotDownloaded,
        color: onDevice ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      );
    }
    final have = entry.onDevice.length;
    return _StatusLine(
      icon: entry.isComplete ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.document_download,
      text: localized.downloadsOnDeviceCount(have, entry.files.length),
      color: have > 0 ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 8,
      children: [
        Icon(icon, size: 18, color: color),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color))),
      ],
    );
  }
}

/// One episode or track: where it stands, in words, and the action that fits
/// - with its name on it for anyone who hovers or holds it.
class _FileRow extends ConsumerWidget {
  const _FileRow({required this.file});

  final SyncedItem file;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localized = context.localized;
    final task = ref.watch(downloadTasksProvider(file.id));
    final model = file.itemModel;
    final onDevice = file.videoFile.existsSync();
    final watched = file.userData?.played == true;
    final name = model is EpisodeModel ? "${model.episode}. ${model.name}" : (model?.name ?? '');

    final ({IconData icon, String text, Color? color}) status;
    final List<Widget> actions;
    if (task.isPending || task.isFailed) {
      status = describeDownload(context, ref, task, expectedBytes: expectedDownloadBytes(task, file));
      actions = [
        if (task.canPause)
          IconButton(
            tooltip: localized.downloadPause,
            onPressed: () => ref.read(syncProvider.notifier).pauseTask(task),
            icon: const Icon(IconsaxPlusLinear.pause),
          ),
        if (task.status == TaskStatus.paused)
          IconButton(
            tooltip: localized.downloadResume,
            onPressed: () => ref.read(syncProvider.notifier).resumeTask(task),
            icon: const Icon(IconsaxPlusLinear.play),
          ),
        if (task.isFailed)
          IconButton(
            tooltip: localized.retry,
            onPressed: () => ref.read(syncProvider.notifier).retryDownload(file.id),
            icon: const Icon(IconsaxPlusLinear.refresh),
          ),
        IconButton(
          tooltip: localized.downloadStop,
          onPressed: () => stopDownload(context, ref, file.id),
          icon: const Icon(IconsaxPlusLinear.stop_circle),
        ),
      ];
    } else if (onDevice) {
      int size = 0;
      try {
        size = file.videoFile.lengthSync();
      } catch (_) {}
      status = (
        icon: watched ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.tick_circle,
        text: [size.byteFormat, if (watched) localized.watchedState].nonNulls.join("  ·  "),
        color: theme.colorScheme.primary,
      );
      actions = [
        IconButton(
          tooltip: localized.delete,
          onPressed: () => showDefaultAlertDialog(
            context,
            localized.downloadsDeleteFileTitle,
            localized.downloadsDeleteFileDesc(name),
            (dialogContext) async {
              Navigator.of(dialogContext).pop();
              await ref.read(syncProvider.notifier).deleteFullSyncFiles(file, null);
            },
            localized.delete,
            (dialogContext) => Navigator.of(dialogContext).pop(),
            localized.cancel,
          ),
          icon: const Icon(IconsaxPlusLinear.trash),
        ),
      ];
    } else {
      status = (
        icon: IconsaxPlusLinear.import,
        text: localized.downloadsNotDownloaded,
        color: theme.colorScheme.onSurfaceVariant,
      );
      actions = [
        IconButton(
          tooltip: localized.downloadsDownload,
          onPressed: () => ref.read(syncProvider.notifier).syncFile(file, false),
          icon: const Icon(IconsaxPlusLinear.import),
        ),
      ];
    }

    return FocusButton(
      onTap: onDevice && model != null ? () => model.play(context, ref) : null,
      borderRadius: FladderTheme.smallShape.borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          spacing: 12,
          children: [
            Icon(status.icon, size: 22, color: status.color),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(status.text, style: theme.textTheme.bodySmall?.copyWith(color: status.color)),
                  if (task.status == TaskStatus.running || task.status == TaskStatus.paused)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: task.progress >= 0 ? task.progress : null, minHeight: 3),
                      ),
                    ),
                ],
              ),
            ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

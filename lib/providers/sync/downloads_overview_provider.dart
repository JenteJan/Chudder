import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/providers/sync_provider.dart';

/// What the Downloads tab knows about one thing that was downloaded: a film,
/// a show, an album, a playlist - one root of the downloads.
class DownloadedEntry {
  const DownloadedEntry({
    required this.root,
    required this.files,
    required this.onDevice,
    required this.bytes,
    required this.watchedOnDevice,
    this.heightLabel,
    this.transcoded = false,
    this.next,
  });

  final SyncedItem root;

  /// Every file that could be downloaded under it - the film itself, each
  /// episode, each track - in the order they come in.
  final List<SyncedItem> files;

  /// The ones actually on the device.
  final List<SyncedItem> onDevice;

  /// What those take up.
  final int bytes;

  /// How many of the ones on the device have been watched.
  final int watchedOnDevice;

  /// "720p" and the like, from the first file on the device.
  final String? heightLabel;
  final bool transcoded;

  /// What Play starts: the film, or the first episode on the device not yet
  /// watched - the one in progress first.
  final SyncedItem? next;

  ItemBaseModel? get model => root.itemModel;
  bool get isComplete => files.isNotEmpty && onDevice.length == files.length;
  bool get hasSeveral => files.length > 1 || files.firstOrNull?.id != root.id;
}

class DownloadsOverview {
  const DownloadsOverview({required this.entries, required this.labels, required this.pendingUserData});

  final List<DownloadedEntry> entries;

  /// The root every downloadable file belongs to, by file id, so a row in the
  /// queue can say "Show - S1E3" rather than just the episode's name.
  final Map<String, ({SyncedItem file, SyncedItem root})> labels;

  /// Watch progress made offline that the server has not heard about yet.
  final int pendingUserData;

  int get bytes => entries.fold(0, (sum, entry) => sum + entry.bytes);
}

/// Everything the Downloads tab lists, worked out from the database and the
/// files on disk. Recomputed when the roots change or a download changes
/// state - not on every progress tick, which the queue rows follow by
/// themselves.
final downloadsOverviewProvider = FutureProvider.autoDispose<DownloadsOverview>((ref) async {
  final roots = ref.watch(syncProvider.select((value) => value.items));
  // A download finishing or failing changes what is on the device.
  ref.watch(downloadQueueProvider.select((queue) {
    final keys = queue.entries.map((entry) => '${entry.key}:${entry.value.status.name}').toList()..sort();
    return keys.join(',');
  }));
  final notifier = ref.read(syncProvider.notifier);

  final entries = <DownloadedEntry>[];
  final labels = <String, ({SyncedItem file, SyncedItem root})>{};
  for (final root in roots) {
    if (root.markedForDelete) continue;
    final children = await notifier.getNestedChildren(root);
    final files = [
      if (root.hasVideoFile) root,
      ...children.where((child) => child.hasVideoFile),
    ];
    _sortForPlaying(files);
    for (final file in files) {
      labels[file.id] = (file: file, root: root);
    }

    final onDevice = files.where((file) => file.videoFile.existsSync()).toList();
    int bytes = 0;
    for (final file in onDevice) {
      try {
        bytes += file.videoFile.lengthSync();
      } catch (_) {}
    }
    final watched = onDevice.where((file) => file.userData?.played == true).length;

    final first = onDevice.firstOrNull;
    final height = first?.itemModel?.streamModel?.videoStreams.firstOrNull?.height;

    // In progress first, then the first not yet watched, then from the top.
    final next = onDevice.firstWhereOrNull((file) => (file.userData?.progress ?? 0) > 0 && file.userData?.played != true) ??
        onDevice.firstWhereOrNull((file) => file.userData?.played != true) ??
        onDevice.firstOrNull;

    entries.add(DownloadedEntry(
      root: root,
      files: files,
      onDevice: onDevice,
      bytes: bytes,
      watchedOnDevice: watched,
      heightLabel: height != null && height > 0 ? '${height}p' : null,
      transcoded: first?.isTranscoded ?? false,
      next: next,
    ));
  }

  return DownloadsOverview(
    entries: entries,
    labels: labels,
    pendingUserData: await notifier.pendingUserDataCount(),
  );
});

/// Seasons and episodes in the order they are watched in; anything else
/// keeps the order it came in.
void _sortForPlaying(List<SyncedItem> files) {
  int keyOf(SyncedItem item) {
    final model = item.itemModel;
    if (model is EpisodeModel) return model.season * 100000 + model.episode;
    return -1;
  }

  if (!files.any((file) => file.itemModel is EpisodeModel)) return;
  files.sort((a, b) => keyOf(a).compareTo(keyOf(b)));
}

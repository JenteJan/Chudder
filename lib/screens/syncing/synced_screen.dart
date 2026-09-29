import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/providers/sync/downloads_overview_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/screens/settings/client_sections/client_settings_download.dart';
import 'package:chudder/screens/shared/nested_scaffold.dart';
import 'package:chudder/screens/shared/nested_sliver_appbar.dart';
import 'package:chudder/screens/syncing/downloads_widgets.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/sliver_list_padding.dart';
import 'package:chudder/widgets/navigation_scaffold/components/background_image.dart';
import 'package:chudder/widgets/shared/pull_to_refresh.dart';

/// The Downloads tab.
///
/// Built around three questions, in the order they matter: is anything
/// wrong or waiting (the status card), what is on its way (the queue), and
/// what can I watch without a connection (the library). Managing a single
/// download - its episodes, deleting, getting the rest - lives one tap away
/// in [showSyncItemDetails].
@RoutePage()
class SyncedScreen extends ConsumerStatefulWidget {
  const SyncedScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SyncedScreenState();
}

enum _LibraryFilter { all, films, shows, music, other }

class _SyncedScreenState extends ConsumerState<SyncedScreen> {
  _LibraryFilter filter = _LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final roots = ref.watch(syncProvider.select((value) => value.items));
    final overview = ref.watch(downloadsOverviewProvider);
    final queue = ref.watch(downloadQueueProvider);
    final padding = AdaptiveLayout.adaptivePadding(context);
    final data = overview.valueOrNull;

    final all = data?.entries ?? const <DownloadedEntry>[];
    // "On this device" means on this device: a download that has nothing
    // here yet is in the queue, and one that stopped with nothing here is
    // listed apart, under what it is.
    final entries = all.where((entry) => entry.onDevice.isNotEmpty).toList();
    final stalled =
        all.where((entry) => entry.onDevice.isEmpty && !entry.files.any((file) => queue.containsKey(file.id))).toList();
    final available = {for (final entry in entries) _filterOf(entry.model)};
    final shown = entries.where((entry) => filter == _LibraryFilter.all || _filterOf(entry.model) == filter).toList();

    return PullToRefresh(
      refreshOnStart: true,
      onRefresh: () async {
        await ref.read(syncProvider.notifier).refresh();
        ref.invalidate(downloadsOverviewProvider);
      },
      child: (context) => NestedScaffold(
        background: BackgroundImage(images: roots.map((value) => value.images).nonNulls.toList()),
        body: CustomScrollView(
          scrollCacheExtent: kPosterCacheExtent,
          physics: const AlwaysScrollableScrollPhysics(),
          controller: AdaptiveLayout.scrollOf(context, HomeTabs.sync),
          slivers: [
            if (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
              NestedSliverAppBar(
                parent: context,
                route: LibrarySearchRoute(),
              )
            else
              const DefaultSliverTopBadding(),
            SliverPadding(
              padding: padding,
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.localized.downloadsTitle,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (kDebugMode)
                      IconButton(
                        tooltip: "View database",
                        onPressed: () => ref.read(syncProvider.notifier).viewDatabase(context),
                        icon: const Icon(IconsaxPlusLinear.driver),
                      ),
                    IconButton(
                      tooltip: context.localized.downloadSettings,
                      onPressed: () => _showDownloadSettings(context),
                      icon: const Icon(IconsaxPlusLinear.setting_2),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: padding.copyWith(top: 12, bottom: 8),
              sliver: SliverToBoxAdapter(
                child: DownloadsStatusCard(queue: queue, overview: data),
              ),
            ),
            if (queue.isNotEmpty) ..._queueSlivers(context, queue, data, padding),
            if (entries.isNotEmpty) ...[
              SliverPadding(
                padding: padding.copyWith(top: 24, bottom: 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 8,
                    children: [
                      Text(
                        context.localized.downloadsOnDevice,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (available.length > 1)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            spacing: 8,
                            children: [
                              _LibraryFilter.all,
                              ..._LibraryFilter.values.where((value) => available.contains(value)),
                            ]
                                .map((value) => ChoiceChip(
                                      label: Text(_filterLabel(context, value)),
                                      selected: filter == value,
                                      onSelected: (_) => setState(() => filter = value),
                                    ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: padding,
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 560,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (context, index) => FocusProvider(
                    autoFocus: index == 0 && queue.isEmpty,
                    child: DownloadedRow(entry: shown[index]),
                  ),
                ),
              ),
            ],
            if (stalled.isNotEmpty) ...[
              SliverPadding(
                padding: padding.copyWith(top: 24, bottom: 4),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(context.localized.downloadsNotDownloadedTitle,
                          style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        context.localized.downloadsNotDownloadedDesc,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: padding,
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 560,
                    mainAxisExtent: 132,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: stalled.length,
                  itemBuilder: (context, index) => DownloadedRow(entry: stalled[index]),
                ),
              ),
            ],
            if (entries.isEmpty && stalled.isEmpty && overview.hasValue && queue.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: DownloadsEmptyState(),
              ),
            const DefaultSliverBottomPadding(),
          ],
        ),
      ),
    );
  }

  List<Widget> _queueSlivers(
    BuildContext context,
    Map<String, DownloadStream> queue,
    DownloadsOverview? overview,
    EdgeInsets padding,
  ) {
    // What needs a hand first, then what is moving, then what is waiting.
    int rank(DownloadStream stream) => switch (stream.status) {
          TaskStatus.failed || TaskStatus.notFound => 0,
          TaskStatus.running => 1,
          TaskStatus.enqueued || TaskStatus.waitingToRetry => 2,
          TaskStatus.paused => 3,
          _ => 4,
        };
    final streams = queue.values.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
    return [
      SliverPadding(
        padding: padding.copyWith(top: 16, bottom: 4),
        sliver: SliverToBoxAdapter(
          child: Text(
            context.localized.downloadsInProgress(streams.length),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      ),
      SliverPadding(
        padding: padding,
        sliver: SliverList.builder(
          itemCount: streams.length,
          itemBuilder: (context, index) {
            final stream = streams[index];
            return FocusProvider(
              autoFocus: index == 0,
              child: DownloadQueueRow(stream: stream, label: overview?.labels[stream.id]),
            );
          },
        ),
      ),
    ];
  }
}

_LibraryFilter _filterOf(ItemBaseModel? model) => switch (model?.type) {
      FladderItemType.movie => _LibraryFilter.films,
      FladderItemType.series => _LibraryFilter.shows,
      FladderItemType.musicAlbum ||
      FladderItemType.audio ||
      FladderItemType.playlist ||
      FladderItemType.musicArtist =>
        _LibraryFilter.music,
      _ => _LibraryFilter.other,
    };

String _filterLabel(BuildContext context, _LibraryFilter filter) => switch (filter) {
      _LibraryFilter.all => context.localized.all,
      _LibraryFilter.films => context.localized.downloadsFilterFilms,
      _LibraryFilter.shows => context.localized.downloadsFilterShows,
      _LibraryFilter.music => context.localized.downloadsFilterMusic,
      _LibraryFilter.other => context.localized.downloadsFilterOther,
    };

Future<void> _showDownloadSettings(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Consumer(
          builder: (context, ref, _) => StatefulBuilder(
            builder: (context, setState) => ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: buildClientSettingsDownload(context, ref, setState),
            ),
          ),
        ),
      ),
    ),
  );
}

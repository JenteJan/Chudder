import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/button_group.dart';
import 'package:fladder/widgets/shared/fladder_scrollbar.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

enum _DownloadFilter { all, running, queued, completed }

@RoutePage()
class JellybotDownloadsPage extends ConsumerStatefulWidget {
  const JellybotDownloadsPage({super.key});

  @override
  ConsumerState<JellybotDownloadsPage> createState() =>
      _JellybotDownloadsPageState();
}

class _JellybotDownloadsPageState extends ConsumerState<JellybotDownloadsPage> {
  final _scrollController = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  List<DownloadDto> _downloads = [];
  final bool _isLoading = false;
  Timer? _refreshTimer;
  _DownloadFilter _selectedFilter = _DownloadFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDownloads();
    });
    // Refresh every 5 seconds
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _loadDownloads());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  List<DownloadDto> get _filteredDownloads {
    switch (_selectedFilter) {
      case _DownloadFilter.running:
        return _downloads.where((d) => d.isRunning == true).toList();
      case _DownloadFilter.queued:
        return _downloads
            .where((d) =>
                d.isRunning != true &&
                d.isCompleted != true &&
                d.isCancelled != true)
            .toList();
      case _DownloadFilter.completed:
        return _downloads.where((d) => d.isCompleted == true).toList();
      case _DownloadFilter.all:
        return _downloads;
    }
  }

  Future<void> _loadDownloads() async {
    if (_isLoading) return;
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiDownloadsGet();
      if (response.isSuccessful && response.body != null && mounted) {
        setState(() => _downloads = response.body!);
      }
    } catch (e) {
      debugPrint('Error loading downloads: $e');
    }
  }

  Future<void> _cancelDownload(DownloadDto download) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotCancelDownload),
        content: Text(context.localized
            .jellybotCancelDownloadConfirm(download.name ?? 'Unknown')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.localized.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ref.read(jellybotApiProvider);
      await api.apiDownloadsDelete(url: download.url);
      _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotDownloadCancelled)),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling download: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final floatingAppBar =
        AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;
    final filteredDownloads = _filteredDownloads;

    // Stats for filter badges
    final runningCount = _downloads.where((d) => d.isRunning == true).length;
    final queuedCount = _downloads
        .where((d) =>
            d.isRunning != true &&
            d.isCompleted != true &&
            d.isCancelled != true)
        .length;

    return NestedScaffold(
      body: Padding(
        padding: EdgeInsets.only(left: AdaptiveLayout.of(context).sideBarWidth),
        child: Scaffold(
          backgroundColor: null,
          body: FladderScrollbar(
            controller: _scrollController,
            child: PullToRefresh(
              refreshKey: _refreshKey,
              onRefresh: () async {
                await _loadDownloads();
              },
              child: (context) => CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    floating: !floatingAppBar,
                    collapsedHeight: 80,
                    automaticallyImplyLeading: false,
                    leading: AdaptiveLayout.layoutModeOf(context) ==
                            LayoutMode.single
                        ? IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => context.router.maybePop(),
                          )
                        : null,
                    primary: true,
                    pinned: floatingAppBar,
                    elevation: 5,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    backgroundColor: null,
                    titleSpacing: 4,
                    flexibleSpace:
                        AdaptiveLayout.layoutModeOf(context) != LayoutMode.dual
                            ? Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      surfaceColor.withValues(alpha: 0.8),
                                      surfaceColor.withValues(alpha: 0.75),
                                      surfaceColor.withValues(alpha: 0.5),
                                      surfaceColor.withValues(alpha: 0),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              )
                            : null,
                    title: Card(
                      elevation: 2,
                      shadowColor: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(IconsaxPlusLinear.arrow_down_2),
                            const SizedBox(width: 12),
                            Text(
                              context.localized.jellybotDownloads,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (runningCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$runningCount ${context.localized.jellybotActive}',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    bottom: PreferredSize(
                      preferredSize: const Size(0, 50),
                      child: Transform.translate(
                        offset: Offset(0,
                            AdaptiveLayout.of(context).isDesktop ? -20 : -15),
                        child: IgnorePointer(
                          ignoring: _isLoading,
                          child: Opacity(
                            opacity: _isLoading ? 0.5 : 1,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(8),
                              scrollDirection: Axis.horizontal,
                              child: _buildFilterChips(
                                  context, runningCount, queuedCount),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Loading indicator
                  if (_isLoading && _downloads.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (filteredDownloads.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final download = filteredDownloads[index];
                            return _DownloadCard(
                              download: download,
                              onCancel: download.isCompleted != true
                                  ? () => _cancelDownload(download)
                                  : null,
                            );
                          },
                          childCount: filteredDownloads.length,
                        ),
                      ),
                    )
                  else
                    SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              IconsaxPlusLinear.arrow_down_2,
                              size: 64,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.localized.jellybotNoDownloads,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 80),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChips(
      BuildContext context, int runningCount, int queuedCount) {
    final filterChips = [
      _FilterChipData(
        label: context.localized.all,
        icon: IconsaxPlusLinear.category,
        selectedIcon: IconsaxPlusBold.category,
        value: _DownloadFilter.all,
        count: _downloads.length,
      ),
      _FilterChipData(
        label: context.localized.jellybotRunningDownloads,
        icon: IconsaxPlusLinear.play,
        selectedIcon: IconsaxPlusBold.play,
        value: _DownloadFilter.running,
        count: runningCount,
      ),
      _FilterChipData(
        label: context.localized.jellybotQueuedDownloads,
        icon: IconsaxPlusLinear.timer_1,
        selectedIcon: IconsaxPlusBold.timer_1,
        value: _DownloadFilter.queued,
        count: queuedCount,
      ),
      _FilterChipData(
        label: context.localized.jellybotCompletedDownloads,
        icon: IconsaxPlusLinear.tick_circle,
        selectedIcon: IconsaxPlusBold.tick_circle,
        value: _DownloadFilter.completed,
        count: _downloads.where((d) => d.isCompleted == true).length,
      ),
    ];

    return Row(
      spacing: 4,
      children: filterChips.asMap().entries.map((entry) {
        final index = entry.key;
        final chip = entry.value;
        final isSelected = _selectedFilter == chip.value;
        final position = index == 0
            ? PositionContext.first
            : (index == filterChips.length - 1
                ? PositionContext.last
                : PositionContext.middle);

        return PositionProvider(
          position: position,
          child: ExpressiveButton(
            isSelected: isSelected,
            icon: isSelected ? Icon(chip.selectedIcon) : null,
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chip.label),
                if (chip.count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context)
                              .colorScheme
                              .onPrimary
                              .withValues(alpha: 0.2)
                          : Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      chip.count.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            onPressed: () {
              setState(() {
                _selectedFilter = chip.value;
              });
            },
          ),
        );
      }).toList(),
    );
  }
}

class _FilterChipData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final _DownloadFilter value;
  final int count;

  const _FilterChipData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.value,
    this.count = 0,
  });
}

class _DownloadCard extends StatelessWidget {
  final DownloadDto download;
  final VoidCallback? onCancel;

  const _DownloadCard({required this.download, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final progress = download.progress ?? 0;
    final isRunning = download.isRunning ?? false;
    final isCompleted = download.isCompleted ?? false;
    final isDeadLink = download.isDeadLink ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isRunning
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1)
                        : (isCompleted
                            ? Colors.green.withValues(alpha: 0.1)
                            : (isDeadLink
                                ? Colors.red.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1))),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isRunning
                        ? IconsaxPlusBold.arrow_down
                        : (isCompleted
                            ? IconsaxPlusBold.tick_circle
                            : (isDeadLink
                                ? IconsaxPlusBold.link_21
                                : IconsaxPlusBold.timer_1)),
                    color: isRunning
                        ? Theme.of(context).colorScheme.primary
                        : (isCompleted
                            ? Colors.green
                            : (isDeadLink ? Colors.red : Colors.orange)),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.name ?? 'Unknown',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (download.fileName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          download.fileName!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Cancel button
                if (onCancel != null)
                  IconButton(
                    icon: const Icon(IconsaxPlusLinear.close_circle),
                    onPressed: onCancel,
                    tooltip: context.localized.cancel,
                  ),
              ],
            ),
            // Progress
            if (isRunning) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress / 100,
                  minHeight: 8,
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${progress.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  Text(
                    '${download.speed?.toStringAsFixed(1) ?? 0} ${download.speedUnit ?? 'MB/s'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${download.sizeReceived?.toStringAsFixed(1) ?? 0} / ${download.totalSize?.toStringAsFixed(1) ?? 0} ${download.totalSizeUnit ?? 'MB'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (download.estimatedTime != null)
                    Text(
                      '~${download.estimatedTime} ${download.estimatedTimeUnit ?? 'min'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? Colors.green.withValues(alpha: 0.1)
                      : (isDeadLink
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isCompleted
                      ? context.localized.jellybotCompleted
                      : (isDeadLink
                          ? context.localized.jellybotDeadLink
                          : context.localized.jellybotQueued),
                  style: TextStyle(
                    fontSize: 12,
                    color: isCompleted
                        ? Colors.green
                        : (isDeadLink ? Colors.red : Colors.orange),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class JellybotDownloadsPage extends ConsumerStatefulWidget {
  const JellybotDownloadsPage({super.key});

  @override
  ConsumerState<JellybotDownloadsPage> createState() => _JellybotDownloadsPageState();
}

class _JellybotDownloadsPageState extends ConsumerState<JellybotDownloadsPage> {
  List<DownloadDto> _downloads = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
    // Refresh every 5 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadDownloads());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
        content: Text(context.localized.jellybotCancelDownloadConfirm(download.name ?? 'Unknown')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.localized.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
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
    final runningDownloads = _downloads.where((d) => d.isRunning == true).toList();
    final queuedDownloads = _downloads.where((d) => d.isRunning != true && d.isCompleted != true && d.isCancelled != true).toList();
    final completedDownloads = _downloads.where((d) => d.isCompleted == true).toList();

    return SettingsScaffold(
      label: context.localized.jellybotDownloads,
      items: [
        if (_isLoading && _downloads.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ))
        else if (_downloads.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(context.localized.jellybotNoDownloads)),
          )
        else ...[
          if (runningDownloads.isNotEmpty) ...[
            _SectionHeader(title: context.localized.jellybotRunningDownloads),
            ...runningDownloads.map((d) => _DownloadTile(
              download: d,
              onCancel: () => _cancelDownload(d),
            )),
          ],
          if (queuedDownloads.isNotEmpty) ...[
            _SectionHeader(title: context.localized.jellybotQueuedDownloads),
            ...queuedDownloads.map((d) => _DownloadTile(
              download: d,
              onCancel: () => _cancelDownload(d),
            )),
          ],
          if (completedDownloads.isNotEmpty) ...[
            _SectionHeader(title: context.localized.jellybotCompletedDownloads),
            ...completedDownloads.map((d) => _DownloadTile(
              download: d,
              onCancel: null,
            )),
          ],
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadDto download;
  final VoidCallback? onCancel;

  const _DownloadTile({required this.download, this.onCancel});

  @override
  Widget build(BuildContext context) {
    final progress = download.progress ?? 0;
    final isRunning = download.isRunning ?? false;
    final isCompleted = download.isCompleted ?? false;
    final isDeadLink = download.isDeadLink ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.name ?? 'Unknown',
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (download.fileName != null)
                        Text(
                          download.fileName!,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onCancel,
                    tooltip: context.localized.cancel,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (isRunning) ...[
              LinearProgressIndicator(value: progress / 100),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${progress.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
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
                      '${download.estimatedTime} ${download.estimatedTimeUnit ?? 'min'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ] else if (isCompleted)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(context.localized.jellybotCompleted),
                ],
              )
            else if (isDeadLink)
              Row(
                children: [
                  const Icon(Icons.link_off, color: Colors.red, size: 16),
                  const SizedBox(width: 4),
                  Text(context.localized.jellybotDeadLink),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.hourglass_empty, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text(context.localized.jellybotQueued),
                ],
              ),
          ],
        ),
      ),
    );
  }
}


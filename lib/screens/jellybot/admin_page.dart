import 'dart:async';

import 'package:auto_route/annotations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/screens/settings/settings_scaffold.dart';
import 'package:fladder/util/localization_helper.dart';

@RoutePage()
class JellybotAdminPage extends ConsumerStatefulWidget {
  const JellybotAdminPage({super.key});

  @override
  ConsumerState<JellybotAdminPage> createState() => _JellybotAdminPageState();
}

class _JellybotAdminPageState extends ConsumerState<JellybotAdminPage> {
  List<ScheduledJob> _jobs = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  // Known job types from the API
  static const List<String> _availableJobTypes = [
    'CrawlJob',
    'CleanupJob',
    'ScanJob',
  ];

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadJobs());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    if (_isLoading) return;
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiJobsGet();
      if (response.isSuccessful && response.body != null && mounted) {
        setState(() => _jobs = response.body!);
      }
    } catch (e) {
      debugPrint('Error loading jobs: $e');
    }
  }

  Future<void> _triggerJob(String jobType) async {
    try {
      setState(() => _isLoading = true);
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiJobsPost(body: TriggerJobRequest(jobType: jobType));
      if (response.isSuccessful) {
        await _loadJobs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.localized.jellybotJobTriggered(jobType))),
          );
        }
      }
    } catch (e) {
      debugPrint('Error triggering job: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotErrorTriggeringJob)),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelJob(ScheduledJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.localized.jellybotCancelJob),
        content: Text(context.localized.jellybotCancelJobConfirm(job.type ?? 'Unknown')),
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
      await api.apiJobsDelete(body: job);
      await _loadJobs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.jellybotJobCancelled)),
        );
      }
    } catch (e) {
      debugPrint('Error cancelling job: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      label: context.localized.jellybotAdmin,
      items: [
        // Trigger Jobs Section
        _SectionHeader(title: context.localized.jellybotTriggerJob),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableJobTypes.map((jobType) => FilledButton.icon(
              onPressed: _isLoading ? null : () => _triggerJob(jobType),
              icon: const Icon(Icons.play_arrow),
              label: Text(jobType),
            )).toList(),
          ),
        ),
        const SizedBox(height: 24),
        // Running Jobs Section
        _SectionHeader(title: context.localized.jellybotRunningJobs),
        if (_jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.localized.jellybotNoRunningJobs),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _jobs.length,
            itemBuilder: (context, index) {
              final job = _jobs[index];
              return _JobTile(
                job: job,
                onCancel: () => _cancelJob(job),
              );
            },
          ),
        const SizedBox(height: 24),
        // Server Settings
        _SectionHeader(title: context.localized.jellybotServerSettings),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ServerUrlSetting(),
        ),
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

class _JobTile extends StatelessWidget {
  final ScheduledJob job;
  final VoidCallback onCancel;

  const _JobTile({required this.job, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: const CircularProgressIndicator(strokeWidth: 2),
        title: Text(job.type ?? 'Unknown Job'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${context.localized.status}: ${job.status ?? 'Running'}'),
            if (job.startedAt != null)
              Text('${context.localized.jellybotStartedAt}: ${_formatDateTime(job.startedAt!)}'),
          ],
        ),
        isThreeLine: true,
        trailing: IconButton(
          icon: Icon(Icons.stop, color: Theme.of(context).colorScheme.error),
          onPressed: onCancel,
          tooltip: context.localized.cancel,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class _ServerUrlSetting extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerUrlSetting> createState() => _ServerUrlSettingState();
}

class _ServerUrlSettingState extends ConsumerState<_ServerUrlSetting> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(jellybotBaseUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUsingDefault = ref.watch(jellybotBaseUrlProvider.notifier).isUsingDefault;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: context.localized.jellybotServerUrl,
                  border: const OutlineInputBorder(),
                  hintText: 'http://localhost:8888',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () async {
                await ref.read(jellybotBaseUrlProvider.notifier).setUrl(_controller.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.localized.jellybotServerUrlUpdated)),
                  );
                }
              },
              child: Text(context.localized.save),
            ),
          ],
        ),
        if (!isUsingDefault) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await ref.read(jellybotBaseUrlProvider.notifier).resetToDefault();
              _controller.text = ref.read(jellybotBaseUrlProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.localized.jellybotServerUrlReset)),
                );
              }
            },
            icon: const Icon(Icons.restore),
            label: Text(context.localized.jellybotResetToDefault),
          ),
        ],
      ],
    );
  }
}


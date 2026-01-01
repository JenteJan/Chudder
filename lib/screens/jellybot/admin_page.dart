import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/fladder_scrollbar.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

@RoutePage()
class JellybotAdminPage extends ConsumerStatefulWidget {
  const JellybotAdminPage({super.key});

  @override
  ConsumerState<JellybotAdminPage> createState() => _JellybotAdminPageState();
}

class _JellybotAdminPageState extends ConsumerState<JellybotAdminPage> {
  final _scrollController = ScrollController();
  final _refreshKey = GlobalKey<RefreshIndicatorState>();

  List<ScheduledJob> _jobs = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  // Known job types from the API
  static const List<_JobTypeData> _availableJobTypes = [
    _JobTypeData(
        type: 'CrawlJob',
        icon: IconsaxPlusLinear.global_search,
        label: 'Crawl'),
    _JobTypeData(
        type: 'DomainUpdateJob',
        icon: IconsaxPlusLinear.refresh,
        label: 'Domain Update'),
    _JobTypeData(
        type: 'LiveTvChannelsJob',
        icon: IconsaxPlusLinear.monitor,
        label: 'Live TV Channels'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadJobs();
    });
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _loadJobs());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
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
      final response =
          await api.apiJobsPost(body: TriggerJobRequest(jobType: jobType));
      if (response.isSuccessful) {
        await _loadJobs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(context.localized.jellybotJobTriggered(jobType))),
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
        content: Text(
            context.localized.jellybotCancelJobConfirm(job.type ?? 'Unknown')),
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
    final isAdmin = ref.watch(userProvider
        .select((value) => value?.policy?.isAdministrator ?? false));

    if (!isAdmin) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                IconsaxPlusLinear.lock,
                size: 64,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                context.localized.adminOnly,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    final surfaceColor = Theme.of(context).colorScheme.surface;
    final floatingAppBar =
        AdaptiveLayout.layoutModeOf(context) != LayoutMode.single;

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
                await _loadJobs();
              },
              child: CustomScrollView(
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
                    backgroundColor: Colors.transparent,
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
                            const Icon(IconsaxPlusLinear.setting_2),
                            const SizedBox(width: 12),
                            Text(
                              context.localized.jellybotAdmin,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (_jobs.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${_jobs.length}',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Trigger Jobs Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        context.localized.jellybotTriggerJob,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableJobTypes
                            .map(
                              (job) => _JobTriggerButton(
                                jobData: job,
                                isLoading: _isLoading,
                                onTrigger: () => _triggerJob(job.type),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  // Running Jobs Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        context.localized.jellybotRunningJobs,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                    ),
                  ),
                  if (_jobs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                IconsaxPlusLinear.task_square,
                                size: 48,
                                color: Theme.of(context).colorScheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                context.localized.jellybotNoRunningJobs,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final job = _jobs[index];
                            return _JobCard(
                              job: job,
                              onCancel: () => _cancelJob(job),
                            );
                          },
                          childCount: _jobs.length,
                        ),
                      ),
                    ),
                  // Server Settings Section
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                      child: Text(
                        context.localized.jellybotServerSettings,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ServerUrlCard(),
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
}

class _JobTypeData {
  final String type;
  final IconData icon;
  final String label;

  const _JobTypeData({
    required this.type,
    required this.icon,
    required this.label,
  });
}

class _JobTriggerButton extends StatelessWidget {
  final _JobTypeData jobData;
  final bool isLoading;
  final VoidCallback onTrigger;

  const _JobTriggerButton({
    required this.jobData,
    required this.isLoading,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isLoading ? null : onTrigger,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(jobData.icon, size: 20),
              const SizedBox(width: 8),
              Text(jobData.label),
              const SizedBox(width: 8),
              Icon(
                IconsaxPlusLinear.play,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final ScheduledJob job;
  final VoidCallback onCancel;

  const _JobCard({required this.job, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.type ?? 'Unknown Job',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          job.status ?? 'Running',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                      if (job.startedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${context.localized.jellybotStartedAt}: ${_formatDateTime(job.startedAt!)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: onCancel,
              style: IconButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
              ),
              icon: Icon(
                IconsaxPlusLinear.stop,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: context.localized.cancel,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class _ServerUrlCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ServerUrlCard> createState() => _ServerUrlCardState();
}

class _ServerUrlCardState extends ConsumerState<_ServerUrlCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(jellybotBaseUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUsingDefault =
        ref.watch(jellybotBaseUrlProvider.notifier).isUsingDefault;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(IconsaxPlusLinear.global),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.localized.jellybotServerUrl,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (!isUsingDefault)
                        Text(
                          'Custom URL',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'http://localhost:8888',
                suffixIcon: IconButton(
                  onPressed: () async {
                    await ref
                        .read(jellybotBaseUrlProvider.notifier)
                        .setUrl(_controller.text);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(
                                context.localized.jellybotServerUrlUpdated)),
                      );
                    }
                  },
                  icon: const Icon(IconsaxPlusLinear.tick_circle),
                  tooltip: context.localized.save,
                ),
              ),
            ),
            if (!isUsingDefault) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(jellybotBaseUrlProvider.notifier)
                      .resetToDefault();
                  _controller.text = ref.read(jellybotBaseUrlProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text(context.localized.jellybotServerUrlReset)),
                    );
                  }
                },
                icon: const Icon(IconsaxPlusLinear.refresh),
                label: Text(context.localized.jellybotResetToDefault),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

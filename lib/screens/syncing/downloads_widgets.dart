import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide ConnectionState;

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/syncing/download_failure.dart';
import 'package:chudder/models/syncing/download_stream.dart';
import 'package:chudder/models/syncing/sync_item.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/sync/downloads_overview_provider.dart';
import 'package:chudder/providers/sync/item_activity_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/screens/details_screens/components/item_toggle_buttons.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/syncing/downloaded_item_view.dart';
import 'package:chudder/services/battery_optimization.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/play_item_helpers.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/size_formatting.dart';
import 'package:chudder/widgets/shared/item_actions.dart';

/// The one line that matters most right now, and the one thing to do about
/// it: a failure to retry, a download held back for Wi-Fi, the progress of
/// what is running - or, with nothing going on, how much is on the device.
class DownloadsStatusCard extends ConsumerWidget {
  const DownloadsStatusCard({required this.queue, required this.overview, super.key});

  final Map<String, DownloadStream> queue;
  final DownloadsOverview? overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final localized = context.localized;
    final connection = ref.watch(connectivityStatusProvider);
    final requireWifi = ref.watch(clientSettingsProvider.select((value) => value.requireWifi));

    final streams = queue.values.toList();
    final failed = streams.where((stream) => stream.needsRetry).toList();
    final running = streams.where((stream) => stream.status == TaskStatus.running).toList();
    final waiting = streams
        .where((stream) => stream.status == TaskStatus.enqueued || stream.status == TaskStatus.waitingToRetry)
        .toList();
    final paused = streams.where((stream) => stream.status == TaskStatus.paused).toList();
    final pending = running.length + waiting.length;
    final offline = connection == ConnectionState.offline;
    final onWifi = connection.homeInternet;

    final pendingUserData = overview?.pendingUserData ?? 0;
    final extra = <Widget>[
      if (pendingUserData > 0)
        _StatusLine(
          icon: IconsaxPlusLinear.cloud_change,
          text: localized.downloadsPendingWatchState(pendingUserData),
        ),
      if (pending > 0) const _BackgroundHealth(),
    ];

    if (failed.isNotEmpty) {
      final reason = parseDownloadFailure(failed.first.error).kind.label(localized);
      return _card(
        context,
        background: colors.errorContainer,
        foreground: colors.onErrorContainer,
        icon: IconsaxPlusBold.danger,
        title: localized.downloadsFailedCount(failed.length),
        subtitle: reason,
        action: FilledButton.icon(
          onPressed: () => ref.read(syncProvider.notifier).retryAllFailed(),
          icon: const Icon(IconsaxPlusLinear.refresh),
          label: Text(localized.retry),
        ),
        extra: extra,
      );
    }

    if (waiting.isNotEmpty && running.isEmpty && !offline && requireWifi && !onWifi) {
      return _card(
        context,
        background: colors.tertiaryContainer,
        foreground: colors.onTertiaryContainer,
        icon: IconsaxPlusBold.wifi,
        title: localized.downloadsWaitingForWifi(waiting.length),
        subtitle: localized.downloadsWaitingForWifiDesc,
        action: FilledButton.tonal(
          onPressed: () =>
              ref.read(clientSettingsProvider.notifier).update((value) => value.copyWith(requireWifi: false)),
          child: Text(localized.downloadsUseMobileData),
        ),
        extra: extra,
      );
    }

    if (pending > 0 && offline) {
      return _card(
        context,
        background: colors.surfaceContainerHigh,
        foreground: colors.onSurface,
        icon: IconsaxPlusBold.cloud_cross,
        title: localized.downloadsWaitingForConnection(pending),
        subtitle: localized.downloadsWaitingForConnectionDesc,
        extra: extra,
      );
    }

    if (pending > 0) {
      final active = [...running, ...waiting];
      final progress = active.fold<double>(0, (sum, stream) => sum + stream.progress.clamp(0.0, 1.0)) / active.length;
      final remaining = running.map((stream) => stream.timeRemaining).nonNulls.fold<Duration?>(
            null,
            (longest, time) => longest == null || time > longest ? time : longest,
          );
      final speed = running.map((stream) => stream.downloadSpeed).where((speed) => speed.isNotEmpty).firstOrNull;
      return _card(
        context,
        background: colors.primaryContainer,
        foreground: colors.onPrimaryContainer,
        icon: IconsaxPlusBold.document_download,
        title: localized.downloadsDownloadingCount(pending),
        subtitle: [
          "${(progress * 100).round()}%",
          if (remaining != null) localized.downloadsTimeLeft(_shortDuration(context, remaining)),
          if (speed != null) speed,
        ].join("  ·  "),
        progress: progress,
        action: active.any((stream) => stream.canPause)
            ? IconButton.filledTonal(
                tooltip: localized.pauseAll,
                onPressed: () => ref.read(syncProvider.notifier).pauseAll(),
                icon: const Icon(IconsaxPlusBold.pause),
              )
            : null,
        extra: extra,
      );
    }

    if (paused.isNotEmpty) {
      return _card(
        context,
        background: colors.surfaceContainerHigh,
        foreground: colors.onSurface,
        icon: IconsaxPlusBold.pause,
        title: localized.downloadsPausedCount(paused.length),
        action: FilledButton.tonalIcon(
          onPressed: () => ref.read(syncProvider.notifier).resumeAll(),
          icon: const Icon(IconsaxPlusBold.play),
          label: Text(localized.resumeAll),
        ),
        extra: extra,
      );
    }

    final entries = overview?.entries ?? const [];
    if (entries.isEmpty && extra.isEmpty) return const SizedBox.shrink();
    return _card(
      context,
      background: colors.surfaceContainer,
      foreground: colors.onSurface,
      icon: IconsaxPlusBold.tick_circle,
      title: localized.downloadsAllReady,
      subtitle: localized.downloadsStorageSummary(entries.length, (overview?.bytes ?? 0).byteFormat ?? "0 B"),
      extra: extra,
    );
  }

  Widget _card(
    BuildContext context, {
    required Color background,
    required Color foreground,
    required IconData icon,
    required String title,
    String? subtitle,
    double? progress,
    Widget? action,
    List<Widget> extra = const [],
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: FladderTheme.largeShape.borderRadius,
      ),
      child: IconTheme(
        data: IconThemeData(color: foreground),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 16,
                children: [
                  Icon(icon, size: 28),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(title,
                            style:
                                theme.textTheme.titleMedium?.copyWith(color: foreground, fontWeight: FontWeight.bold)),
                        if (subtitle != null && subtitle.isNotEmpty)
                          Text(subtitle,
                              style: theme.textTheme.bodyMedium?.copyWith(color: foreground.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  if (action is IconButton) action,
                ],
              ),
              // A worded button beside the words squeezed them into a column
              // a word wide on a phone; it gets its own line instead.
              if (action != null && action is! IconButton)
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              if (progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    color: foreground,
                    backgroundColor: foreground.withValues(alpha: 0.15),
                  ),
                ),
              ...extra,
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        Icon(icon, size: 18),
        Expanded(
            child: Text(text,
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: DefaultTextStyle.of(context).style.color))),
        if (action != null) action!,
      ],
    );
  }
}

/// On Android a download only carries on in the background as long as the
/// system lets it; with battery optimisation on, it may be stopped after a
/// while and only picks up again when the app is opened. Said while
/// something is downloading, with the way to fix it.
class _BackgroundHealth extends StatefulWidget {
  const _BackgroundHealth();

  @override
  State<_BackgroundHealth> createState() => _BackgroundHealthState();
}

class _BackgroundHealthState extends State<_BackgroundHealth> with WidgetsBindingObserver {
  bool restricted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final ignoring = await BatteryOptimization.isIgnoringBatteryOptimizations();
    if (mounted && restricted == ignoring) setState(() => restricted = !ignoring);
  }

  @override
  Widget build(BuildContext context) {
    if (!restricted) return const SizedBox.shrink();
    return _StatusLine(
      icon: IconsaxPlusLinear.battery_disable,
      text: context.localized.downloadsBatteryRestricted,
      action: TextButton(
        onPressed: () => BatteryOptimization.openBatteryOptimizationSettings(),
        child: Text(context.localized.downloadsAllowBackground),
      ),
    );
  }
}

String _shortDuration(BuildContext context, Duration duration) {
  if (duration.inHours > 0) return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
  if (duration.inMinutes > 0) return "${duration.inMinutes}m";
  return "<1m";
}

/// One download on its way: what it is, where it has got to, and the one
/// action that fits its state.
class DownloadQueueRow extends ConsumerWidget {
  const DownloadQueueRow({required this.stream, this.label, super.key});

  final DownloadStream stream;
  final ({SyncedItem file, SyncedItem root})? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localized = context.localized;
    final live = ref.watch(downloadTasksProvider(stream.id));
    final current = live.id.isEmpty ? stream : live;
    final file = label?.file;
    final model = file?.itemModel;
    final rootModel = label?.root.itemModel;

    final title = rootModel != null && rootModel.id != model?.id ? rootModel.name : (model?.name ?? localized.unknown);
    final episodeLabel = model is EpisodeModel ? model.label(localized) : null;

    final status = describeDownload(context, ref, current, expectedBytes: expectedDownloadBytes(current, file));
    final state = status.text;
    final stateColor = status.color;

    final actions = <Widget>[
      if (current.canPause)
        IconButton(
          tooltip: localized.downloadPause,
          onPressed: () => ref.read(syncProvider.notifier).pauseTask(current),
          icon: const Icon(IconsaxPlusLinear.pause),
        ),
      if (current.status == TaskStatus.paused)
        IconButton(
          tooltip: localized.downloadResume,
          onPressed: () => ref.read(syncProvider.notifier).resumeTask(current),
          icon: const Icon(IconsaxPlusLinear.play),
        ),
      if (current.isFailed || current.status == TaskStatus.notFound)
        IconButton(
          tooltip: localized.retry,
          onPressed: () => ref.read(syncProvider.notifier).retryDownload(current.id),
          icon: const Icon(IconsaxPlusLinear.refresh),
        ),
    ];

    final failure = current.isFailed ? parseDownloadFailure(current.error).detail : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FocusButton(
        onTap: label != null ? () => showSyncItemDetails(context, label!.root, ref) : null,
        borderRadius: FladderTheme.smallShape.borderRadius,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 48,
                height: 72,
                child: ClipRRect(
                  borderRadius: FladderTheme.smallShape.borderRadius,
                  child: FladderImage(image: (label?.root.images ?? file?.images)?.primary, decodeHeight: 144),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                    if (episodeLabel != null)
                      Text(episodeLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    Text(
                      state,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: stateColor),
                    ),
                    if (failure.isNotEmpty)
                      Text(failure,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (current.status == TaskStatus.running || current.status == TaskStatus.paused)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: current.progress >= 0 ? current.progress : null,
                            minHeight: 4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              ...actions,
              IconButton(
                tooltip: localized.downloadStop,
                onPressed: () => stopDownload(context, ref, current.id),
                icon: const Icon(IconsaxPlusLinear.stop_circle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thing on the device: what it is, how much of it is here, what it
/// takes up and at what quality, and Play.
class DownloadedRow extends ConsumerWidget {
  const DownloadedRow({required this.entry, super.key});

  final DownloadedEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localized = context.localized;
    final model = entry.model;
    final next = entry.next;
    final nextModel = next?.itemModel;

    final nothingHere = entry.onDevice.isEmpty;
    final what = nothingHere
        ? localized.downloadsNothingOnDevice
        : switch (model?.type) {
            FladderItemType.series => entry.isComplete
                ? localized.downloadsEpisodesAll(entry.files.length)
                : localized.downloadsEpisodesOf(entry.onDevice.length, entry.files.length),
            _ when entry.hasSeveral => localized.downloadsFilesOf(entry.onDevice.length, entry.files.length),
            _ => model?.overview.yearAired?.toString() ?? '',
          };
    final quality = nothingHere
        ? ''
        : [
            if (entry.bytes > 0) entry.bytes.byteFormat,
            entry.transcoded
                ? [entry.heightLabel, localized.downloadsConverted].nonNulls.join(' ')
                : [localized.qualityOptionsOriginal, entry.heightLabel].nonNulls.join(' '),
          ].nonNulls.join("  ·  ");

    final progress = switch (model?.type) {
      FladderItemType.series => entry.onDevice.isEmpty ? 0.0 : entry.watchedOnDevice / entry.onDevice.length,
      _ => (nextModel?.progress ?? 0) / 100,
    };
    final nextLabel = model?.type == FladderItemType.series && nextModel is EpisodeModel
        ? nextModel.seasonEpisodeLabel(localized)
        : null;

    // Being removed or refreshed: the row says so and keeps still, rather
    // than opening something that is going away.
    final activity = ref.watch(itemActivityProvider.select((all) => all[entry.root.id]));
    final deleting = activity?.kind == ItemActivityKind.deleting;

    Future<void> openMenu() async {
      final item = model;
      if (item == null || activity != null) return;
      await showItemActionsSheet(context, ref, item, actions: [
        if (nextModel != null)
          ItemActionButton(
            icon: const Icon(IconsaxPlusLinear.play),
            label: Text(localized.downloadsPlay),
            action: () => nextModel.play(context, ref),
          ),
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.setting_2),
          label: Text(localized.syncDetails),
          action: () => showSyncItemDetails(context, entry.root, ref),
        ),
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.info_circle),
          label: Text(localized.downloadsOpenDetails),
          action: () => item.navigateTo(context, ref: ref),
        ),
        ItemActionDivider(),
        ItemActionButton(
          icon: const Icon(IconsaxPlusLinear.trash),
          label: Text(localized.downloadsRemove),
          foregroundColor: theme.colorScheme.error,
          action: () => confirmRemoveDownload(context, ref, entry.root),
        ),
      ]);
    }

    return FocusButton(
      onTap: activity != null ? null : () => showSyncItemDetails(context, entry.root, ref),
      onLongPress: model != null && activity == null ? openMenu : null,
      onSecondaryTapDown: model != null && activity == null ? (_) => openMenu() : null,
      borderRadius: FladderTheme.smallShape.borderRadius,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          spacing: 14,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: FladderTheme.smallShape.borderRadius,
                child: FladderImage(image: entry.root.images?.primary, decodeHeight: 240),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    model?.name ?? localized.unknown,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (what.isNotEmpty) Text(what, style: theme.textTheme.bodySmall),
                  if (quality.isNotEmpty)
                    Text(
                      quality,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  if (progress > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 24),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0), minHeight: 3),
                      ),
                    ),
                ],
              ),
            ),
            if (activity != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    value: deleting ? null : activity.fraction,
                    semanticsLabel: deleting ? localized.downloadsDeleting : localized.downloadsRefreshingPlain,
                  ),
                ),
              )
            else if (nextModel != null)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 2,
                children: [
                  IconButton.filledTonal(
                    tooltip: localized.play(nextModel.name),
                    onPressed: () => nextModel.play(context, ref),
                    icon: const Icon(IconsaxPlusBold.play),
                  ),
                  if (nextLabel != null) Text(nextLabel, style: theme.textTheme.labelSmall),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DownloadsEmptyState extends StatelessWidget {
  const DownloadsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Icon(IconsaxPlusLinear.document_download, size: 56, color: theme.colorScheme.primary),
              Text(context.localized.downloadsEmptyTitle,
                  textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
              Text(
                context.localized.downloadsEmptyDesc,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a download is doing, in words, with the icon and colour that go with
/// it - one wording for the queue, the status card and the item view alike.
({IconData icon, String text, Color? color}) describeDownload(
  BuildContext context,
  WidgetRef ref,
  DownloadStream stream, {
  int? expectedBytes,
}) {
  final theme = Theme.of(context);
  final localized = context.localized;
  switch (stream.status) {
    case TaskStatus.running:
      final progress = stream.progress >= 0 ? stream.progress : null;
      final size = expectedBytes != null && expectedBytes > 0
          ? localized.downloadsSizeOf(
              ((progress ?? 0) * expectedBytes).round().byteFormat ?? '0 B', expectedBytes.byteFormat ?? '')
          : null;
      return (
        icon: IconsaxPlusLinear.import,
        text: [
          if (progress != null) "${(progress * 100).round()}%",
          size,
          if (stream.timeRemaining != null) localized.downloadsTimeLeft(_shortDuration(context, stream.timeRemaining!)),
          if (stream.downloadSpeed.isNotEmpty) stream.downloadSpeed,
        ].nonNulls.join("  ·  "),
        color: theme.colorScheme.primary,
      );
    case TaskStatus.enqueued:
      final requireWifi = ref.watch(clientSettingsProvider.select((value) => value.requireWifi));
      final connection = ref.watch(connectivityStatusProvider);
      final wifi = requireWifi && !connection.homeInternet && connection != ConnectionState.offline;
      return (
        icon: wifi ? IconsaxPlusLinear.wifi : IconsaxPlusLinear.clock,
        text: [
          wifi ? localized.downloadsStateWifi : localized.downloadsStateQueued,
          if (expectedBytes != null && expectedBytes > 0) "~${expectedBytes.byteFormat}",
        ].join("  ·  "),
        color: theme.colorScheme.onSurfaceVariant,
      );
    case TaskStatus.waitingToRetry:
      return (
        icon: IconsaxPlusLinear.refresh,
        text: localized.downloadsStateRetrying,
        color: theme.colorScheme.tertiary
      );
    case TaskStatus.paused:
      return (
        icon: IconsaxPlusLinear.pause,
        text: localized.downloadsStatePaused,
        color: theme.colorScheme.onSurfaceVariant
      );
    case TaskStatus.failed || TaskStatus.notFound:
      return (
        icon: IconsaxPlusLinear.danger,
        text: localized.downloadsFailedBecause(parseDownloadFailure(stream.error).kind.label(localized)),
        color: theme.colorScheme.error,
      );
    default:
      return (icon: IconsaxPlusLinear.clock, text: localized.downloadsStateQueued, color: null);
  }
}

/// How big a download will be once it is done: the server's estimate for a
/// transcode, which the task carries, or the original file's size.
int? expectedDownloadBytes(DownloadStream stream, SyncedItem? file) {
  final known = int.tryParse(stream.task?.headers['Known-Content-Length'] ?? '');
  if (known != null && known > 0) return known;
  final size = file?.fileSize;
  return size != null && size > 1 ? size : null;
}

/// Stops a download. It asks nothing: what was fetched can be fetched again.
/// The message it leaves has a way back instead, for the press that was a
/// slip - on a television the button sits right next to Pause.
Future<void> stopDownload(BuildContext context, WidgetRef ref, String id) async {
  final localized = context.localized;
  final sync = ref.read(syncProvider.notifier);
  await sync.cancelDownload(id);
  if (!context.mounted) return;
  FladderSnack.show(
    localized.downloadsStopped,
    context: context,
    actionLabel: localized.downloadsRestart,
    onActionPressed: () => sync.retryDownload(id),
  );
}

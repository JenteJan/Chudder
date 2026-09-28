import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/subtitles/subtitle_text_tools.dart';
import 'package:chudder/providers/subtitles/subtitle_file_actions.dart';
import 'package:chudder/providers/subtitles/subtitle_fix_service.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/screens/video_player/components/subtitle_fixes.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/util/subtitle_names.dart';

/// Whether this account might be able to remove a subtitle file: an admin
/// through Jellyfin, anyone with Bazarr for the files Bazarr knows.
bool mightRemoveSubtitles(WidgetRef ref) {
  final user = ref.read(userProvider);
  return user?.policy?.isAdministrator == true || (user?.bazarrCredentials?.isConfigured ?? false);
}

/// Asks before removing a subtitle file, offering what this setup can do.
/// Resolves with the removal the viewer chose, or null. The file itself
/// goes through [scheduleSubtitleRemoval], after its undo window.
Future<({SubtitleRemoval plan, bool block})?> confirmRemoveSubtitle(
  BuildContext context,
  WidgetRef ref, {
  required String itemId,
  String? mediaSourceId,
  required int index,
  required String? path,
  required String label,
}) {
  return showDialog<({SubtitleRemoval plan, bool block})>(
    context: context,
    builder: (context) => _RemoveDialog(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      index: index,
      path: path,
      label: label,
    ),
  );
}

/// Queues [choice] and says so, with an undo for as long as the file is
/// still there. [onUndone] puts the row back; the returned future resolves
/// with whether the server re-lists the item, or null if it was undone.
/// A failed removal is reported here and also calls [onUndone], since the
/// file is still there.
Future<bool?> scheduleSubtitleRemoval(
  WidgetRef ref,
  ({SubtitleRemoval plan, bool block}) choice, {
  required String name,
  required AppLocalizations localized,
  required VoidCallback onUndone,
}) async {
  final pending = ref.read(subtitleRemovalQueueProvider).schedule(choice.plan, block: choice.block);
  FladderSnack.show(
    localized.subtitleRemoved(name),
    duration: SubtitleRemovalQueue.undoWindow,
    actionLabel: localized.subtitleRemoveUndo,
    onActionPressed: () {
      if (pending.undo()) onUndone();
    },
  );
  try {
    return await pending.result;
  } on SubtitleRemovalException catch (error) {
    FladderSnack.show(error.error == SubtitleRemovalError.notAllowed
        ? localized.subtitleRemoveNotAllowed
        : localized.subtitleRemoveFailed('$error'));
  } catch (error) {
    FladderSnack.show(localized.subtitleRemoveFailed('$error'));
  }
  onUndone();
  return null;
}

class _RemoveDialog extends ConsumerStatefulWidget {
  const _RemoveDialog({
    required this.itemId,
    required this.mediaSourceId,
    required this.index,
    required this.path,
    required this.label,
  });

  final String itemId;
  final String? mediaSourceId;
  final int index;
  final String? path;
  final String label;

  @override
  ConsumerState<_RemoveDialog> createState() => _RemoveDialogState();
}

class _RemoveDialogState extends ConsumerState<_RemoveDialog> {
  late final Future<SubtitleRemoval> _plan = ref.read(subtitleFileActionsProvider).plan(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
        index: widget.index,
        path: widget.path,
      );
  void _remove(SubtitleRemoval plan, {required bool block}) => Navigator.of(context).pop((plan: plan, block: block));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<SubtitleRemoval>(
      future: _plan,
      builder: (context, snapshot) {
        final plan = snapshot.data;
        final loading = snapshot.connectionState != ConnectionState.done;
        final name = plan?.fileName.isNotEmpty == true ? plan!.fileName : widget.label;

        final body = <Widget>[
          Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            )
          else if (plan == null || !plan.possible)
            Text(context.localized.subtitleRemoveNotAllowed)
          else ...[
            Text(context.localized.subtitleRemoveExplainer),
            if (plan.canBlock) Text(context.localized.subtitleRemoveBazarrExplainer),
            if (plan.bazarrFile != null && !plan.canBlock) Text(context.localized.subtitleRemoveBazarrKnows),
          ],
        ];

        final error = theme.colorScheme.error;
        return AlertDialog(
          icon: const Icon(IconsaxPlusLinear.trash),
          title: Text(context.localized.subtitleRemoveTitle),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: body),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.localized.cancel),
            ),
            if (plan != null && plan.possible) ...[
              if (plan.canBlock)
                OutlinedButton(
                  onPressed: () => _remove(plan, block: false),
                  child: Text(context.localized.subtitleRemoveOnly),
                ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: error, foregroundColor: theme.colorScheme.onError),
                onPressed: () => _remove(plan, block: plan.canBlock),
                child: Text(plan.canBlock ? context.localized.subtitleRemoveAndBlock : context.localized.subtitleRemove),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The item's subtitles away from the player: what is there, a way to take
/// a file away or swap it for a better one, and the finder.
Future<bool> showSubtitleManager(
  BuildContext context, {
  required String itemId,
  required String itemName,
  String? mediaSourceId,
}) async {
  var changed = false;
  await showDialogAdaptive(
    context: context,
    builder: (context) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
      child: _SubtitleManager(
        itemId: itemId,
        itemName: itemName,
        mediaSourceId: mediaSourceId,
        onChanged: () => changed = true,
      ),
    ),
  );
  return changed;
}

class _SubtitleManager extends ConsumerStatefulWidget {
  const _SubtitleManager({
    required this.itemId,
    required this.itemName,
    required this.mediaSourceId,
    required this.onChanged,
  });

  final String itemId;
  final String itemName;
  final String? mediaSourceId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_SubtitleManager> createState() => _SubtitleManagerState();
}

class _SubtitleManagerState extends ConsumerState<_SubtitleManager> {
  ({String itemId, String? mediaSourceId}) get _key => (itemId: widget.itemId, mediaSourceId: widget.mediaSourceId);

  /// Removed here, while the server has not re-listed the item yet.
  final Set<String> _gone = {};

  Future<void> _refreshSoon({required bool relisted}) async {
    widget.onChanged();
    // The server re-lists after its refresh has run; give it a moment.
    if (relisted) await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) ref.invalidate(subtitleItemProvider(_key));
  }

  Future<void> _find({dto.MediaStream? replacing}) async {
    final localized = context.localized;
    final result = await showSubtitleFinder(
      context,
      itemId: widget.itemId,
      itemName: widget.itemName,
      mediaSourceId: widget.mediaSourceId,
      replacingName: replacing == null ? null : _name(replacing),
      replacingLanguage: replacing?.language,
    );
    if (result == null || !mounted) return;
    widget.onChanged();
    // Bazarr may have written over the very file being replaced.
    if (replacing != null && !result.pending && result.stream?.path != replacing.path) {
      await _removeQuietly(replacing);
    }
    FladderSnack.show(result.pending ? localized.subtitleSavedPending : localized.subtitleAdded(_name(result.stream!)));
    await _refreshSoon(relisted: true);
  }

  /// The old file after a replacement: no second question, the viewer said
  /// "swap it" already. Blocked when Bazarr downloaded it, so it does not
  /// come back.
  Future<void> _removeQuietly(dto.MediaStream stream) async {
    final actions = ref.read(subtitleFileActionsProvider);
    try {
      // Numbers moved when the new file arrived: find the old one by path.
      final fresh = await ref.refresh(subtitleItemProvider(_key).future);
      final current = fresh.item.subtitleStreams.where((s) => s.path == stream.path).firstOrNull;
      if (current?.index == null) return;
      final plan = await actions.plan(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
        index: current!.index!,
        path: current.path,
      );
      if (!plan.possible) return;
      await actions.remove(plan, block: plan.canBlock);
      if (stream.path != null) _gone.add(stream.path!);
    } catch (error) {
      FladderSnack.show(context.localized.subtitleRemoveFailed('$error'));
    }
  }

  Future<void> _remove(dto.MediaStream stream) async {
    final choice = await confirmRemoveSubtitle(
      context,
      ref,
      itemId: widget.itemId,
      mediaSourceId: widget.mediaSourceId,
      index: stream.index ?? -1,
      path: stream.path,
      label: _name(stream),
    );
    if (choice == null || !mounted) return;
    final path = stream.path;
    if (path != null) setState(() => _gone.add(path));
    widget.onChanged();
    final relisted = await scheduleSubtitleRemoval(
      ref,
      choice,
      name: _name(stream),
      localized: context.localized,
      onUndone: () {
        if (mounted && path != null) setState(() => _gone.remove(path));
      },
    );
    if (relisted != null) await _refreshSoon(relisted: relisted);
  }

  /// The file being fixed right now, by path.
  String? _fixing;

  bool _canFix(dto.MediaStream stream) {
    final user = ref.read(userProvider);
    final text = subtitleTextFormatOf(stream.codec) != null;
    return (text && canManageSubtitles(user)) ||
        (stream.isExternal == true && (user?.bazarrCredentials?.isConfigured ?? false));
  }

  /// The menu hands over placeholders for the fixes that need an amount;
  /// those are asked for here.
  Future<void> _fix(dto.MediaStream stream, SubtitleFix? picked) async {
    final localized = context.localized;
    final lookup = ref.read(subtitleItemProvider(_key)).value;
    final SubtitleFix? fix = switch (picked) {
      ShiftFix() => await askShift(context),
      FrameRateFix() => await askFrameRate(context, videoRate: lookup?.item.frameRate),
      TranslateFix() => await askTranslation(context, ref),
      _ => picked,
    };
    if (fix == null || !mounted || stream.index == null) return;
    setState(() => _fixing = stream.path ?? '');
    try {
      final service = ref.read(subtitleFixServiceProvider);
      final plan = await service.plan(SubtitleFileRef(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
        index: stream.index!,
        path: stream.path,
        codec: stream.codec,
        language: stream.language,
        forced: stream.isForced ?? false,
        hearingImpaired: stream.isHearingImpaired ?? false,
        isExternal: stream.isExternal ?? false,
      ));
      if (!plan.supports(fix)) throw SubtitleFixException(localized.subtitleFixUnavailable);
      await service.apply(plan, fix);
      FladderSnack.show(plan.leavesCopy(fix) ? localized.subtitleFixDoneCopy : localized.subtitleFixDone);
      await _refreshSoon(relisted: true);
    } catch (error) {
      FladderSnack.show(localized.subtitleFixFailed('$error'), duration: const Duration(seconds: 8));
    } finally {
      if (mounted) setState(() => _fixing = null);
    }
  }

  String _name(dto.MediaStream stream) {
    final path = stream.path;
    if (path != null && path.isNotEmpty) {
      final separator = path.lastIndexOf(RegExp(r'[\\/]'));
      return separator == -1 ? path : path.substring(separator + 1);
    }
    return stream.displayTitle ?? stream.language ?? '';
  }

  /// Files next to the video first - the ones that can be changed - then
  /// the tracks inside it, each under its own heading.
  List<Object> _ordered(List<dto.MediaStream> streams) {
    final files = streams.where((s) => s.isExternal == true).toList();
    final inside = streams.where((s) => s.isExternal != true).toList();
    return [
      if (files.isNotEmpty) ...[context.localized.subtitleManagerFiles, ...files],
      if (inside.isNotEmpty) ...[context.localized.subtitleManagerInside, ...inside],
    ];
  }

  Widget _row(BuildContext context, dto.MediaStream stream, {required bool canFind, required bool canRemove}) {
    final theme = Theme.of(context);
    return ListTile(
                            leading: Icon(stream.isExternal == true
                                ? IconsaxPlusLinear.document_text
                                : IconsaxPlusLinear.video_square),
                            title: Text(stream.displayTitle ?? stream.language?.capitalize() ?? '?'),
                            subtitle: Text(
                              stream.isExternal == true
                                  ? shortSubtitleName(_name(stream), max: 60)
                                  : (stream.codec ?? '').toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: (stream.isExternal == true && (canRemove || canFind)) || _canFix(stream)
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_canFix(stream))
                                        PopupMenuButton<SubtitleFix?>(
                                          tooltip: context.localized.subtitleFixMenu,
                                          icon: const Icon(IconsaxPlusLinear.magicpen),
                                          enabled: _fixing == null,
                                          onSelected: (fix) => _fix(stream, fix),
                                          itemBuilder: (context) => [
                                            if (stream.isExternal == true &&
                                                (ref.read(userProvider)?.bazarrCredentials?.isConfigured ?? false))
                                              PopupMenuItem(
                                                value: const SyncToAudioFix(),
                                                child: ListTile(
                                                  leading: const Icon(IconsaxPlusLinear.sound),
                                                  title: Text(context.localized.subtitleFixSync),
                                                  subtitle: Text(context.localized.subtitleFixSyncHint),
                                                ),
                                              ),
                                            if (stream.isExternal == true &&
                                                (ref.read(userProvider)?.bazarrCredentials?.isConfigured ?? false)) ...[
                                              PopupMenuItem(
                                                value: const TranslateFix(''),
                                                child: ListTile(
                                                  leading: const Icon(Icons.translate_rounded),
                                                  title: Text(context.localized.subtitleFixTranslate),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: const CommonErrorsFix(),
                                                child: ListTile(
                                                  leading: const Icon(IconsaxPlusLinear.magicpen),
                                                  title: Text(context.localized.subtitleFixCommonErrors),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: const UppercaseFix(),
                                                child: ListTile(
                                                  leading: const Icon(Icons.text_fields_rounded),
                                                  title: Text(context.localized.subtitleFixUppercase),
                                                ),
                                              ),
                                            ],
                                            PopupMenuItem(
                                              value: const ShiftFix(Duration.zero),
                                              child: ListTile(
                                                leading: const Icon(IconsaxPlusLinear.timer_1),
                                                title: Text(context.localized.subtitleFixShift),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: const FrameRateFix(0, 0),
                                              child: ListTile(
                                                leading: const Icon(IconsaxPlusLinear.video_time),
                                                title: Text(context.localized.subtitleFixFrameRate),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: const RemoveHearingImpairedFix(),
                                              child: ListTile(
                                                leading: const Icon(IconsaxPlusLinear.headphone),
                                                title: Text(context.localized.subtitleFixRemoveHi),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (_fixing == stream.path && stream.path != null)
                                        const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox.square(
                                              dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                        ),
                                      if (canFind && stream.isExternal == true)
                                        IconButton(
                                          tooltip: context.localized.subtitleReplace,
                                          onPressed: () => _find(replacing: stream),
                                          icon: const Icon(IconsaxPlusLinear.arrow_swap_horizontal),
                                        ),
                                      if (canRemove && stream.isExternal == true)
                                        IconButton(
                                          tooltip: context.localized.subtitleRemove,
                                          onPressed: () => _remove(stream),
                                          icon: Icon(IconsaxPlusLinear.trash, color: theme.colorScheme.error),
                                        ),
                                    ],
                                  )
                                : null,
                          );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lookup = ref.watch(subtitleItemProvider(_key));
    final user = ref.watch(userProvider);
    final canFind = canFindSubtitles(user);
    final canRemove = mightRemoveSubtitles(ref);
    final streams =
        (lookup.value?.item.subtitleStreams ?? const <dto.MediaStream>[]).where((s) => !_gone.contains(s.path)).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(IconsaxPlusBold.document_text, color: theme.colorScheme.onSecondaryContainer),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(context.localized.subtitleManage, style: theme.textTheme.titleLarge),
                    Text(
                      widget.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.localized.close,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(IconsaxPlusLinear.close_circle),
              ),
            ],
          ),
        ),
        Flexible(
          child: lookup.isLoading && lookup.value == null
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              : streams.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        lookup.hasError ? '${lookup.error}' : context.localized.subtitleManagerNone,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: [
                        for (final entry in _ordered(streams))
                          entry is String
                              ? _ManagerSection(title: entry)
                              : _row(context, entry as dto.MediaStream, canFind: canFind, canRemove: canRemove),
                      ],
                    ),
        ),
        if (canFind)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: () => _find(),
              icon: const Icon(IconsaxPlusLinear.search_normal_1),
              label: Text(context.localized.subtitleFinderTitle),
            ),
          ),
      ],
    );
  }
}

/// The finder for [item] from outside the player, then the page reloaded so
/// the new track is in its picker.
Future<void> findSubtitlesFor(BuildContext context, ItemBaseModel item, {String? mediaSourceId}) async {
  final localized = context.localized;
  final downloaded = await showSubtitleFinder(
    context,
    itemId: item.id,
    itemName: item.detailedName(localized) ?? item.name,
    mediaSourceId: mediaSourceId,
  );
  if (downloaded == null) return;
  final stream = downloaded.stream;
  FladderSnack.show(downloaded.pending
      ? localized.subtitleSavedPending
      : localized.subtitleAdded(stream?.displayTitle ?? stream?.language ?? ''));
  if (context.mounted) await context.refreshData();
}

/// The subtitle files of [item], then the page reloaded if any changed.
Future<void> manageSubtitlesFor(BuildContext context, ItemBaseModel item, {String? mediaSourceId}) async {
  final queue = ProviderScope.containerOf(context, listen: false).read(subtitleRemovalQueueProvider);
  final changed = await showSubtitleManager(
    context,
    itemId: item.id,
    itemName: item.detailedName(context.localized) ?? item.name,
    mediaSourceId: mediaSourceId,
  );
  if (!changed) return;
  // A removal still inside its undo window has not reached the server yet.
  await queue.settled;
  if (context.mounted) await context.refreshData();
}

/// Asks how far to move a subtitle, in seconds; negative is earlier.
Future<ShiftFix?> askShift(BuildContext context) {
  final controller = TextEditingController();
  ShiftFix? parse() {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    if (value == null || value == 0 || value.abs() > 600) return null;
    return ShiftFix(Duration(milliseconds: (value * 1000).round()));
  }

  return showDialog<ShiftFix>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: const Icon(IconsaxPlusLinear.timer_1),
        title: Text(context.localized.subtitleFixShift),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(context.localized.subtitleFixShiftBody),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: context.localized.subtitleFixShiftSeconds,
                  hintText: '-1.5',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  final fix = parse();
                  if (fix != null) Navigator.of(context).pop(fix);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
          FilledButton(
            onPressed: parse() == null ? null : () => Navigator.of(context).pop(parse()),
            child: Text(context.localized.subtitleFixApply),
          ),
        ],
      ),
    ),
  );
}

class _ManagerSection extends StatelessWidget {
  const _ManagerSection({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.8),
      ),
    );
  }
}

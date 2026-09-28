import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/l10n/generated/app_localizations.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/subtitles/subtitle_line_match.dart';
import 'package:chudder/models/subtitles/subtitle_text_tools.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_fix_service.dart';
import 'package:chudder/providers/subtitles/subtitle_timing_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/video_player/components/video_player_options_sheet.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/duration_extensions.dart';
import 'package:chudder/util/localization_helper.dart';

/// The subtitle [sub] of the playing video, in the terms the fix service
/// takes.
SubtitleFileRef subtitleFileRefOf(PlaybackModel playback, SubStreamModel sub) {
  final name = sub.fileName.toLowerCase();
  return SubtitleFileRef(
    itemId: playback.item.id,
    mediaSourceId: playback.mediaStreams?.currentVersionStream?.id,
    index: sub.index,
    path: sub.path,
    codec: sub.codec,
    language: sub.language.isEmpty || sub.language == 'Unknown' ? null : sub.language,
    forced: name.contains('.forced.') || sub.displayTitle.toLowerCase().contains('forced'),
    hearingImpaired: RegExp(r'\.(sdh|hi|cc)\.').hasMatch(name),
    isExternal: sub.isExternal,
  );
}

/// Whether the fix menu is worth showing for [sub] at all - cheap checks
/// only; what is really possible is worked out when a fix is picked.
bool mightFixSubtitle(WidgetRef ref, SubStreamModel sub) {
  if (sub.index == -1) return false;
  final user = ref.read(userProvider);
  final bazarr = user?.bazarrCredentials?.isConfigured ?? false;
  final text = subtitleTextFormatOf(sub.codec) != null;
  return (text && canManageSubtitles(user)) || (bazarr && sub.isExternal);
}

/// Puts [fix] into the file behind [sub] for everyone, then plays the
/// fixed subtitle: the new file when the fix made one, the same file read
/// again when it was rewritten in place. Resolves with whether it worked;
/// what went wrong is shown to the viewer.
Future<bool> applySubtitleFixInPlayer(
  WidgetRef ref,
  AppLocalizations localized,
  SubStreamModel sub,
  SubtitleFix fix,
) async {
  final playback = ref.read(playBackModel);
  if (playback == null) return false;
  final timing = ref.read(subtitleTimingProvider.notifier);
  final service = ref.read(subtitleFixServiceProvider);

  void phase(SubtitleFixPhase phase) => timing.setBusy(switch (phase) {
        SubtitleFixPhase.syncing => localized.subtitleFixSyncing,
        SubtitleFixPhase.translating => localized.subtitleFixTranslating,
        SubtitleFixPhase.adding => localized.subtitleFinderPhaseAdding,
        SubtitleFixPhase.working => localized.subtitleFixWorking,
      });

  try {
    phase(SubtitleFixPhase.working);
    final plan = await service.plan(subtitleFileRefOf(playback, sub));
    if (!plan.supports(fix)) {
      throw SubtitleFixException(localized.subtitleFixUnavailable);
    }
    final result = await service.apply(plan, fix, onPhase: phase);

    final current = ref.read(playBackModel);
    if (current != null) {
      await ref.read(playbackModelHelper).refreshSubtitleStreams(
            current,
            attempts: 3,
            retryDelay: const Duration(milliseconds: 1200),
          );
    }
    String name(String? path) => path == null ? '' : path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1);
    final listed = ref.read(playBackModel)?.subStreams ?? const <SubStreamModel>[];
    final target = listed.firstWhereOrNull((s) => result.path != null && s.fileName == name(result.path)) ??
        listed.firstWhereOrNull((s) => s.path == sub.path);
    // The player keeps the files it has read by name and number; the fixed
    // one can have both of the old one's (rewritten in place, or given the
    // old number once that was removed), so it has to be read anew.
    ref.read(videoPlayerProvider).forgetLoadedSubtitles();
    timing.fileChanged();
    if (target != null) {
      if (ref.read(playBackModel)?.mediaStreams?.defaultSubStreamIndex == target.index) {
        await selectSubtitleInPlayer(ref, SubStreamModel.no());
      }
      await selectSubtitleInPlayer(ref, target);
      // The timing is in the file now - only once the fixed file is on, or
      // the old one plays unmoved in between.
      if (fix is ShiftFix) await timing.baked();
    }
    timing.setBusy(null);
    markSubtitlesChanged(ref.read(subtitleChangeProvider.notifier), playback.item.id, playback.item.parentId);
    FladderSnack.show(plan.leavesCopy(fix) ? localized.subtitleFixDoneCopy : localized.subtitleFixDone);
    return true;
  } catch (error) {
    timing.setBusy(null);
    FladderSnack.show(localized.subtitleFixFailed('$error'), duration: const Duration(seconds: 8));
    return false;
  }
}

/// Asks which frame rate the subtitle was made for and which it should play
/// at. The video's own rate is the default target.
Future<FrameRateFix?> askFrameRate(BuildContext context, {double? videoRate}) {
  const rates = [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94];
  double nearest(double value) => rates.reduce((a, b) => (a - value).abs() <= (b - value).abs() ? a : b);
  final to = nearest(videoRate ?? 23.976);
  var from = to == 25.0 ? 23.976 : (to < 25 ? 25.0 : 23.976);
  var target = to;

  String label(double rate) => rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';

  return showDialog<FrameRateFix>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        icon: const Icon(IconsaxPlusLinear.timer_1),
        title: Text(context.localized.subtitleFixFrameRateTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 12,
            children: [
              Text(context.localized.subtitleFixFrameRateBody),
              Row(
                spacing: 12,
                children: [
                  Expanded(child: Text(context.localized.subtitleFixFrameRateFrom)),
                  DropdownButton<double>(
                    value: from,
                    items: [for (final r in rates) DropdownMenuItem(value: r, child: Text('${label(r)} fps'))],
                    onChanged: (value) => setState(() => from = value ?? from),
                  ),
                ],
              ),
              Row(
                spacing: 12,
                children: [
                  Expanded(child: Text(context.localized.subtitleFixFrameRateTo)),
                  DropdownButton<double>(
                    value: target,
                    items: [for (final r in rates) DropdownMenuItem(value: r, child: Text('${label(r)} fps'))],
                    onChanged: (value) => setState(() => target = value ?? target),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
          FilledButton(
            onPressed: from == target ? null : () => Navigator.of(context).pop(FrameRateFix(from, target)),
            child: Text(context.localized.subtitleFixApply),
          ),
        ],
      ),
    ),
  );
}

/// The subtitle timing bar: move the lines earlier or later while watching,
/// then keep the timing that fits. It sits at the top of the picture, clear
/// of the subtitles being lined up, and suits the hand it is used with:
/// large buttons that repeat while held for touch, the bound keys shown on
/// a desktop, focus on a button straight away for a remote.
class SubtitleTimingBar extends ConsumerWidget {
  /// Whether the player's controls are up; while they are, a moved timing is
  /// shown as a small chip even when the bar is closed.
  final bool controlsVisible;

  const SubtitleTimingBar({this.controlsVisible = false, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timing = ref.watch(subtitleTimingProvider);
    final notifier = ref.read(subtitleTimingProvider.notifier);
    ref.watch(playBackModel.select((p) => p?.mediaStreams?.defaultSubStreamIndex));
    ref.watch(videoPlayerProvider.select((p) => p.isCasting));
    final mode = notifier.mode;

    final chip = !timing.open && timing.moved && controlsVisible;
    return Align(
      alignment: const Alignment(0, -0.8),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutCubic,
        child: timing.open
            ? _TimingPanel(key: const ValueKey('panel'), timing: timing, mode: mode)
            : chip
                ? _TimingChip(key: const ValueKey('chip'), delay: timing.delay, onTap: notifier.show)
                : const SizedBox.shrink(key: ValueKey('none')),
      ),
    );
  }
}

String _seconds(Duration delay) {
  final ms = delay.inMilliseconds.abs();
  final digits = ms % 100 == 0 ? 1 : 2;
  return (ms / 1000).toStringAsFixed(digits);
}

class _TimingChip extends StatelessWidget {
  const _TimingChip({required this.delay, required this.onTap, super.key});
  final Duration delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final later = delay > Duration.zero;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(IconsaxPlusLinear.timer_1, size: 16, color: scheme.primary),
              Text(
                later
                    ? context.localized.subtitleTimingChipLater(_seconds(delay))
                    : context.localized.subtitleTimingChipEarlier(_seconds(delay)),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimingPanel extends ConsumerWidget {
  const _TimingPanel({required this.timing, required this.mode, super.key});
  final SubtitleTiming timing;
  final SubtitleTimingMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(subtitleTimingProvider.notifier);
    final playback = ref.watch(playBackModel);
    final sub = playback?.mediaStreams?.currentSubStream;
    final input = AdaptiveLayout.inputDeviceOf(context);
    final keys = ref.watch(videoPlayerSettingsProvider.select((s) => s.currentShortcuts));
    final stepMs = ref.watch(videoPlayerSettingsProvider.select((s) => s.subtitleDelayStepMs));
    final bazarr = ref.watch(userProvider.select((u) => u?.bazarrCredentials?.isConfigured ?? false));
    final canMove = mode == SubtitleTimingMode.player || mode == SubtitleTimingMode.app;
    final busy = timing.busy != null;
    final hasSub = sub != null && sub.index != -1;
    final canKeep = canMove && hasSub && timing.moved && mightFixSubtitle(ref, sub);
    final canSync = hasSub && bazarr && sub.isExternal;
    final canMatch = notifier.canMatchLine;
    final match = timing.match;
    final showKeys = input == InputDevice.pointer;

    final readout = switch (timing.delay) {
      Duration.zero => context.localized.subtitleTimingAsFile,
      final d when d > Duration.zero => context.localized.subtitleTimingLaterBy(_seconds(d)),
      final d => context.localized.subtitleTimingEarlierBy(_seconds(d)),
    };

    final message = switch (mode) {
      SubtitleTimingMode.picture => context.localized.subtitleTimingPicture,
      SubtitleTimingMode.casting => context.localized.subtitleTimingCasting,
      SubtitleTimingMode.none => context.localized.subtitleTimingNoTrack,
      _ => null,
    };

    return MouseRegion(
      onEnter: (_) => notifier.hold(),
      onExit: (_) => notifier.release(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Material(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
            elevation: 8,
            shadowColor: Colors.black54,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: [
                  Row(
                    spacing: 10,
                    children: [
                      Icon(IconsaxPlusLinear.timer_1, size: 20, color: scheme.primary),
                      Expanded(child: Text(context.localized.subtitleTimingTitle, style: theme.textTheme.titleMedium)),
                      IconButton(
                        tooltip: context.localized.close,
                        visualDensity: VisualDensity.compact,
                        onPressed: notifier.close,
                        icon: const Icon(IconsaxPlusLinear.close_circle),
                      ),
                    ],
                  ),
                  if (match?.picked != null)
                    _LineTapView(key: ValueKey(match!.picked!.cue), candidate: match.picked!)
                  else if (match != null)
                    Flexible(child: _LineMatchView(key: ValueKey(match.heardAt), match: match, delay: timing.delay))
                  else if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StepButton(
                          icon: Icons.remove_rounded,
                          tooltip: context.localized.subtitleTimingEarlier,
                          keyHint: showKeys ? keys[VideoHotKeys.subtitlesEarlier]?.label : null,
                          enabled: !busy,
                          onStep: () => notifier.nudge(-1),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _DelayReadout(
                                readout: readout,
                                delay: timing.delay,
                                enabled: !busy,
                                onSet: notifier.set,
                              ),
                              Text(
                                timing.loadingCues
                                    ? context.localized.subtitleTimingPreparing
                                    : context.localized.subtitleTimingStep('${stepMs / 1000}'),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        _StepButton(
                          icon: Icons.add_rounded,
                          tooltip: context.localized.subtitleTimingLater,
                          keyHint: showKeys ? keys[VideoHotKeys.subtitlesLater]?.label : null,
                          enabled: !busy,
                          autofocus: input == InputDevice.dPad && timing.pinned,
                          onStep: () => notifier.nudge(1),
                        ),
                      ],
                    ),
                  ],
                  if (match != null)
                    const SizedBox.shrink()
                  else if (busy)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 10,
                      children: [
                        const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        Flexible(child: Text(timing.busy!, style: theme.textTheme.bodyMedium)),
                      ],
                    )
                  else if (timing.moved || canSync || canMatch)
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canMatch)
                          Tooltip(
                            message: context.localized.subtitleMatchLineHint,
                            child: FilledButton.tonalIcon(
                              onPressed: notifier.startLineMatch,
                              icon: const Icon(IconsaxPlusLinear.message_search, size: 18),
                              label: Text(context.localized.subtitleMatchLine),
                            ),
                          ),
                        if (timing.moved)
                          TextButton.icon(
                            onPressed: notifier.reset,
                            icon: const Icon(IconsaxPlusLinear.refresh_left_square, size: 18),
                            label: Text(context.localized.subtitleTimingReset),
                          ),
                        if (canKeep)
                          Tooltip(
                            message: context.localized.subtitleTimingKeepHint,
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  applySubtitleFixInPlayer(ref, context.localized, sub, ShiftFix(timing.delay)),
                              icon: const Icon(IconsaxPlusLinear.tick_circle, size: 18),
                              label: Text(context.localized.subtitleTimingKeep),
                            ),
                          ),
                        if (canSync)
                          Tooltip(
                            message: context.localized.subtitleFixSyncHint,
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  applySubtitleFixInPlayer(ref, context.localized, sub, const SyncToAudioFix()),
                              icon: const Icon(IconsaxPlusLinear.sound, size: 18),
                              label: Text(context.localized.subtitleFixSync),
                            ),
                          ),
                      ],
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

String _signedSeconds(BuildContext context, Duration delay) {
  // A line minutes away is a different part of the film, not a fine timing.
  if (delay.abs() >= const Duration(minutes: 1)) {
    final minutes = '${(delay.abs().inSeconds / 60).round()}';
    return delay.isNegative
        ? context.localized.subtitleMatchMinutesEarlier(minutes)
        : context.localized.subtitleMatchMinutesLater(minutes);
  }
  return switch (delay) {
    Duration.zero => context.localized.subtitleTimingAsFile,
    final d when d > Duration.zero => context.localized.subtitleTimingLaterBy(_seconds(d)),
    final d => context.localized.subtitleTimingEarlierBy(_seconds(d)),
  };
}

/// The timing as it is, which turns into a field on a tap: the exact number
/// is quicker typed than stepped to.
class _DelayReadout extends StatefulWidget {
  const _DelayReadout({required this.readout, required this.delay, required this.onSet, this.enabled = true});
  final String readout;
  final Duration delay;
  final bool enabled;
  final Future<void> Function(Duration) onSet;

  @override
  State<_DelayReadout> createState() => _DelayReadoutState();
}

class _DelayReadoutState extends State<_DelayReadout> {
  final _text = TextEditingController();
  bool _editing = false;
  bool _invalid = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _edit() {
    final ms = widget.delay.inMilliseconds;
    _text.text = ms == 0 ? '' : '${ms > 0 ? '+' : '-'}${_seconds(widget.delay)}';
    _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
    setState(() {
      _editing = true;
      _invalid = false;
    });
  }

  void _submit() {
    final value = _text.text.trim().isEmpty ? Duration.zero : parseSubtitleDelay(_text.text);
    if (value == null) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _editing = false);
    widget.onSet(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = (theme.textTheme.headlineSmall ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: widget.delay != Duration.zero ? scheme.primary : scheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    if (_editing) {
      return Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
            setState(() => _editing = false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: _text,
            autofocus: true,
            textAlign: TextAlign.center,
            style: style,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-.,:s ]'))],
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
            onSubmitted: (_) => _submit(),
            onTapOutside: (_) => _submit(),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              hintText: '+1.5',
              suffixText: 's',
              errorText: _invalid ? context.localized.subtitleTimingTypeInvalid : null,
              helperText: _invalid ? null : context.localized.subtitleTimingTypeHint,
              helperMaxLines: 2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: context.localized.subtitleTimingTypeTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.enabled ? _edit : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 150),
                  style: style,
                  child: Text(widget.readout, textAlign: TextAlign.center),
                ),
              ),
              Icon(IconsaxPlusLinear.edit_2, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Finding the line just heard: a search field over the subtitle's lines,
/// with the lines around the paused moment below it for when the words do
/// not find one - a translation, most often.
class _LineMatchView extends ConsumerStatefulWidget {
  const _LineMatchView({required this.match, required this.delay, super.key});
  final SubtitleLineMatch match;
  final Duration delay;

  @override
  ConsumerState<_LineMatchView> createState() => _LineMatchViewState();
}

class _LineMatchViewState extends ConsumerState<_LineMatchView> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(subtitleTimingProvider.notifier).cancelLineMatch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(subtitleTimingProvider.notifier);
    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final cues = widget.match.cues;
    final search = cues == null
        ? null
        : searchSubtitleLines(cues, _query.text, heardAt: widget.match.heardAt, currentDelay: widget.delay);
    final typed = _query.text.trim().isNotEmpty;
    final showNearby = search != null && (!typed || search.matches.isEmpty);

    // Room for the list above a phone's keyboard: the panel sits near the top.
    // Read from the window, since a page that makes room for the keyboard
    // hides it from those below.
    final window = MediaQueryData.fromView(View.of(context));
    final free = window.size.height - window.viewInsets.bottom;
    // A phone on its side with the keyboard up: only the lines themselves.
    final compact = free < 360;
    final listHeight = (free - (compact ? 120 : 170)).clamp(56.0, 380.0);

    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
        );

    return Focus(
      onKeyEvent: _onKey,
      skipTraversal: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            spacing: 4,
            children: [
              IconButton(
                tooltip: context.localized.cancel,
                onPressed: notifier.cancelLineMatch,
                icon: const Icon(IconsaxPlusLinear.arrow_left),
              ),
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: !dPad,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    // Only a line well ahead of the rest: otherwise the
                    // viewer picks, rather than Enter taking a lookalike.
                    final best = search?.matches.firstOrNull;
                    if (best != null && search!.clearBest) notifier.pickLine(best);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    hintText: context.localized.subtitleMatchSearchHint,
                    prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1, size: 18),
                    suffixIcon: typed
                        ? IconButton(
                            onPressed: _query.clear,
                            icon: const Icon(IconsaxPlusLinear.close_circle, size: 18),
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ],
          ),
          if (!compact)
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Text(
              context.localized.subtitleMatchPausedAt(widget.match.heardAt.readAbleDuration),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (widget.match.failed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.localized.subtitleMatchFailed, textAlign: TextAlign.center),
            )
          else if (search == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 10,
                children: [
                  const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  Text(context.localized.subtitleMatchLoading),
                ],
              ),
            )
          else
            Flexible(
              child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listHeight),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(right: 8),
                children: [
                  if (typed) ...[
                    if (search.matches.isNotEmpty) ...[
                      if (!compact) header(context.localized.subtitleMatchMatches),
                      for (final (i, candidate) in search.matches.indexed)
                        _LineRow(
                          candidate: candidate,
                          best: i == 0 && search.clearBest,
                          onTap: () => notifier.pickLine(candidate),
                        ),
                    ] else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(context.localized.subtitleMatchNone, style: theme.textTheme.bodyMedium),
                      ),
                  ],
                  if (showNearby) ...[
                    if (!compact) header(context.localized.subtitleMatchNearby),
                    if (!typed && !compact)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                        child: Text(
                          context.localized.subtitleMatchNearbyHint,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    for (final (i, candidate) in search.nearby.indexed)
                      _LineRow(
                        candidate: candidate,
                        best: i == search.nearest,
                        autofocus: dPad && i == search.nearest,
                        onTap: () => notifier.pickLine(candidate),
                      ),
                  ],
                ],
              ),
            ),
            ),
        ],
      ),
    );
  }
}

/// Timing the picked line by ear: it plays again from a little before, the
/// subtitles out of sight, and a tap as it starts sets the timing. Space,
/// Enter or the remote's select key tap as well.
class _LineTapView extends ConsumerStatefulWidget {
  const _LineTapView({required this.candidate, super.key});
  final SubtitleLineCandidate candidate;

  @override
  ConsumerState<_LineTapView> createState() => _LineTapViewState();
}

class _LineTapViewState extends ConsumerState<_LineTapView> {
  /// The last position the player reported, and when: reports come a few
  /// times a second, a tap lands between them.
  Duration _anchor = Duration.zero;
  final Stopwatch _since = Stopwatch()..start();
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    _anchor = ref.read(mediaPlaybackProvider).position;
  }

  Duration get _position {
    final playback = ref.read(mediaPlaybackProvider);
    if (!playback.playing) return _anchor;
    final speed = ref.read(playbackRateProvider);
    return _anchor + Duration(milliseconds: (_since.elapsedMilliseconds.clamp(0, 1000) * speed).round());
  }

  void _tap() {
    if (_tapped) return;
    _tapped = true;
    ref.read(subtitleTimingProvider.notifier).tapLine(_position);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      _tap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      ref.read(subtitleTimingProvider.notifier).unpickLine();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mediaPlaybackProvider.select((p) => p.position), (_, next) {
      _anchor = next;
      _since
        ..reset()
        ..start();
    });
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(subtitleTimingProvider.notifier);
    return Focus(
      onKeyEvent: _onKey,
      skipTraversal: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 4,
            children: [
              IconButton(
                tooltip: context.localized.subtitleMatchTapBack,
                onPressed: notifier.unpickLine,
                icon: const Icon(IconsaxPlusLinear.arrow_left),
              ),
              Expanded(child: Text(context.localized.subtitleMatchTapTitle, style: theme.textTheme.titleSmall)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              widget.candidate.cue.text.replaceAll('\n', ' '),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            context.localized.subtitleMatchTapHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Center(
            child: FilledButton.icon(
              autofocus: true,
              style: FilledButton.styleFrom(minimumSize: const Size(180, 52)),
              onPressed: _tap,
              icon: const Icon(IconsaxPlusBold.volume_high),
              label: Text(context.localized.subtitleMatchTapNow, style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
              )),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: notifier.replayLine,
                icon: const Icon(IconsaxPlusLinear.refresh_left_square, size: 18),
                label: Text(context.localized.subtitleMatchTapReplay),
              ),
              TextButton(
                onPressed: notifier.useGuess,
                child: Text(context.localized.subtitleMatchTapGuess(_signedSeconds(context, widget.candidate.delay))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final _wordPattern = RegExp(r"[\p{L}\p{N}'’]+", unicode: true);

/// One line of the subtitle as a result: where it is in the file, its text
/// with the typed words picked out, and what choosing it would do.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.candidate, required this.onTap, this.best = false, this.autofocus = false});
  final SubtitleLineCandidate candidate;
  final VoidCallback onTap;
  final bool best;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = candidate.cue.text.replaceAll('\n', ' ');
    final spans = <TextSpan>[];
    var at = 0;
    for (final word in _wordPattern.allMatches(text)) {
      if (word.start > at) spans.add(TextSpan(text: text.substring(at, word.start)));
      final hit = candidate.matched.contains(normaliseSubtitleText(word[0]!));
      spans.add(TextSpan(
        text: word[0],
        style: hit ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w700) : null,
      ));
      at = word.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: best ? scheme.primaryContainer.withValues(alpha: 0.45) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          autofocus: autofocus,
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    candidate.cue.start.readAbleDuration,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: spans),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  _signedSeconds(context, candidate.delay),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: best ? scheme.primary : scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round step button that keeps stepping while held, with the key that
/// does the same shown under it on a desktop.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onStep,
    this.keyHint,
    this.enabled = true,
    this.autofocus = false,
  });

  final IconData icon;
  final String tooltip;
  final String? keyHint;
  final VoidCallback onStep;
  final bool enabled;
  final bool autofocus;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  void _startRepeat() {
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 120), (_) => widget.onStep());
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Tooltip(
          message: widget.keyHint == null ? widget.tooltip : '${widget.tooltip} (${widget.keyHint})',
          child: GestureDetector(
            onLongPressStart: widget.enabled ? (_) => _startRepeat() : null,
            onLongPressEnd: (_) => _stopRepeat(),
            onLongPressCancel: _stopRepeat,
            child: IconButton.filledTonal(
              autofocus: widget.autofocus,
              iconSize: 28,
              style: IconButton.styleFrom(minimumSize: const Size(56, 56)),
              onPressed: widget.enabled ? widget.onStep : null,
              icon: Icon(widget.icon),
            ),
          ),
        ),
        if (widget.keyHint != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(widget.keyHint!, style: theme.textTheme.labelSmall),
          ),
      ],
    );
  }
}

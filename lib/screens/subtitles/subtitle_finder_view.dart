import 'package:flutter/material.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/subtitles/release_info.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/util/localization_helper.dart';

/// One language the finder offers as a chip.
class FinderLanguage {
  const FinderLanguage(this.code, this.label);

  /// Three letters.
  final String code;
  final String label;
}

/// What the finder says about the video it matches against.
class FinderFile {
  const FinderFile({
    required this.release,
    this.releaseName,
    this.fromBazarr = false,
    this.named = false,
    this.frameRate,
  });

  final ReleaseInfo release;

  /// The name the release was read from, if any name said something.
  final String? releaseName;

  /// [releaseName] is Bazarr's scene name: the file's name before Sonarr or
  /// Radarr renamed it.
  final bool fromBazarr;
  final bool named;
  final double? frameRate;
}

/// Why nothing is listed, when nothing is.
enum FinderEmptyReason {
  /// The server has no subtitle source installed (only an admin can tell).
  noSources,

  /// This account may not use the server's sources, and has no Bazarr.
  notAllowed,

  /// Sources were asked and found nothing in this language.
  nothingFound,
}

/// A subtitle the viewer already has in another language, which Bazarr could
/// translate into the one being looked for.
class FinderTranslation {
  const FinderTranslation({required this.fromLabel, required this.toLabel, required this.onTranslate});
  final String fromLabel;
  final String toLabel;
  final VoidCallback onTranslate;
}

/// The subtitle finder, drawn from plain values so it can be shown (and
/// tested) without a server. [SubtitleFinder] feeds it.
class SubtitleFinderView extends StatefulWidget {
  const SubtitleFinderView({
    required this.itemName,
    required this.languages,
    required this.language,
    required this.results,
    required this.onLanguage,
    required this.onUse,
    required this.onClose,
    this.file,
    this.fileLoading = false,
    this.fileError,
    this.onMoreLanguages,
    this.onRetry,
    this.onConnectBazarr,
    this.onLetBazarrChoose,
    this.translation,
    this.preferHearingImpaired,
    this.onHearingImpaired,
    this.downloadingKey,
    this.phase,
    this.tried = const {},
    this.replacingName,
    this.emptyReason,
    this.bazarrConnected = false,
    this.bazarrMissing = false,
    this.isEpisode = false,
    super.key,
  });

  final String itemName;
  final List<FinderLanguage> languages;
  final String? language;
  final LanguageResults results;
  final ValueChanged<String> onLanguage;
  final ValueChanged<SubtitleMatch> onUse;

  /// Null while a download runs: closing then would lose track of it.
  final VoidCallback? onClose;
  final FinderFile? file;
  final bool fileLoading;
  final String? fileError;
  final VoidCallback? onMoreLanguages;
  final VoidCallback? onRetry;
  final VoidCallback? onConnectBazarr;

  /// Bazarr picks and downloads the best one itself, when it manages this
  /// item.
  final VoidCallback? onLetBazarrChoose;
  final FinderTranslation? translation;
  final bool? preferHearingImpaired;
  final ValueChanged<bool?>? onHearingImpaired;
  final String? downloadingKey;
  final DownloadPhase? phase;
  final Set<String> tried;

  /// The file a pick will replace, when there is one.
  final String? replacingName;
  final FinderEmptyReason? emptyReason;
  final bool bazarrConnected;

  /// Bazarr is connected but does not manage this item.
  final bool bazarrMissing;
  final bool isEpisode;

  @override
  State<SubtitleFinderView> createState() => _SubtitleFinderViewState();
}

/// How the results are grouped, best first.
enum _Group { forYourFile, sameKind, unchecked, unlikely }

_Group _groupOf(SubtitleMatch match) => switch (match.verdict) {
      MatchVerdict.exact || MatchVerdict.release => _Group.forYourFile,
      MatchVerdict.likely => _Group.sameKind,
      MatchVerdict.unknown => _Group.unchecked,
      MatchVerdict.unlikely => _Group.unlikely,
    };

class _SubtitleFinderViewState extends State<SubtitleFinderView> {
  bool _showUnlikely = false;

  @override
  void didUpdateWidget(covariant SubtitleFinderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _showUnlikely = false;
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.results.matches;
    final groups = <_Group, List<SubtitleMatch>>{};
    for (final match in matches) {
      groups.putIfAbsent(_groupOf(match), () => []).add(match);
    }
    final best = matches.where((m) => !m.isUnlikely).firstOrNull;
    final busy = widget.downloadingKey != null;

    Widget tile(SubtitleMatch match) => _ResultCard(
          match: match,
          best: identical(match, best),
          isEpisode: widget.isEpisode,
          file: widget.file,
          downloading: widget.downloadingKey == match.candidate.key,
          phase: widget.phase,
          enabled: !busy,
          tried: widget.tried.contains(match.candidate.key),
          onUse: () => widget.onUse(match),
        );

    final sections = <Widget>[];
    for (final group in [_Group.forYourFile, _Group.sameKind, _Group.unchecked]) {
      final list = groups[group];
      if (list == null || list.isEmpty) continue;
      sections.add(_SectionHeader(title: _groupTitle(context, group), count: list.length));
      sections.addAll(list.map(tile));
    }
    final unlikely = groups[_Group.unlikely] ?? const <SubtitleMatch>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        Flexible(
          child: CustomScrollView(
            shrinkWrap: true,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.list(
                  children: [
                    if (widget.replacingName != null) _replacing(context),
                    _FileStrip(file: widget.file, loading: widget.fileLoading, error: widget.fileError),
                    const SizedBox(height: 14),
                    _languageRow(context),
                    const SizedBox(height: 10),
                    _statusRow(context),
                  ],
                ),
              ),
              if (matches.isEmpty)
                SliverToBoxAdapter(child: _empty(context))
              else ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  sliver: SliverList.list(children: sections),
                ),
                if (sections.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Text(context.localized.subtitleFinderNoneFit,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  ),
                if (unlikely.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    sliver: SliverToBoxAdapter(
                      child: _UnlikelyToggle(
                        count: unlikely.length,
                        open: _showUnlikely,
                        onTap: () => setState(() => _showUnlikely = !_showUnlikely),
                      ),
                    ),
                  ),
                if (_showUnlikely)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverList.list(children: unlikely.map(tile).toList()),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ],
          ),
        ),
      ],
    );
  }

  String _groupTitle(BuildContext context, _Group group) => switch (group) {
        _Group.forYourFile => context.localized.subtitleFinderGroupYourFile,
        _Group.sameKind => context.localized.subtitleFinderGroupSameKind,
        _Group.unchecked => context.localized.subtitleFinderGroupUnchecked,
        _Group.unlikely => '',
      };

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(IconsaxPlusBold.subtitle, color: theme.colorScheme.onPrimaryContainer),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(context.localized.subtitleFinderTitle, style: theme.textTheme.titleLarge),
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
            onPressed: widget.onClose,
            icon: const Icon(IconsaxPlusLinear.close_circle),
          ),
        ],
      ),
    );
  }

  Widget _replacing(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(14)),
        child: Row(
          spacing: 10,
          children: [
            Icon(IconsaxPlusLinear.arrow_swap_horizontal, size: 20, color: scheme.onSecondaryContainer),
            Expanded(
              child: Text(
                context.localized.subtitleFinderReplacing(widget.replacingName!),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageRow(BuildContext context) {
    final selected = widget.language;
    final known = widget.languages.any((l) => l.code == selected);
    final chips = <Widget>[
      for (final language in widget.languages)
        ChoiceChip(
          label: Text(language.label),
          selected: language.code == selected,
          onSelected: (_) => widget.onLanguage(language.code),
        ),
      if (!known && selected != null) ChoiceChip(label: Text(selected.toUpperCase()), selected: true),
      if (widget.onMoreLanguages != null)
        ActionChip(
          avatar: const Icon(IconsaxPlusLinear.add, size: 18),
          label: Text(context.localized.subtitleFinderMoreLanguages),
          onPressed: widget.onMoreLanguages,
        ),
      if (widget.onHearingImpaired != null)
        Tooltip(
          message: context.localized.subtitleFinderHearingImpairedHint,
          child: FilterChip(
            label: Text(context.localized.subtitleFinderSdh),
            selected: widget.preferHearingImpaired == true,
            onSelected: (value) => widget.onHearingImpaired!(value ? true : null),
          ),
        ),
    ];
    // One line that scrolls sideways: wrapped onto three lines on a phone
    // it pushed the results off the screen.
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Center(child: chips[index]),
      ),
    );
  }

  /// Which sources were asked and where each one is, as quiet badges, with
  /// the one-tap Bazarr choice beside them.
  Widget _statusRow(BuildContext context) {
    final results = widget.results;
    int countOf(SubtitleSourceKind kind) => results.matches.where((m) => m.candidate.source == kind).length;
    final badges = <Widget>[];
    switch (results.jellyfin) {
      case SourceStatus.searching:
        badges.add(_SourceBadge(label: context.localized.subtitleFinderSourceServer, searching: true));
      case SourceStatus.done:
        badges.add(_SourceBadge(
            label: context.localized.subtitleFinderSourceServer, count: countOf(SubtitleSourceKind.jellyfin)));
      case SourceStatus.failed:
        badges.add(_SourceBadge(
            label: context.localized.subtitleFinderSourceServer,
            problem: context.localized.subtitleFinderServerFailedShort));
      case SourceStatus.off:
        break;
    }
    switch (results.bazarr) {
      case SourceStatus.searching:
        badges.add(_SourceBadge(
            label: 'Bazarr', searching: true, hint: context.localized.subtitleFinderBazarrSearching));
      case SourceStatus.done:
        badges.add(_SourceBadge(label: 'Bazarr', count: countOf(SubtitleSourceKind.bazarr)));
      case SourceStatus.failed:
        final missing = widget.bazarrMissing || results.bazarrError == 'not-in-bazarr';
        badges.add(_SourceBadge(
          label: 'Bazarr',
          quiet: missing,
          problem: switch (results.bazarrError) {
            _ when missing => context.localized.subtitleFinderBazarrMissing,
            'unauthorized' => context.localized.subtitleFinderBazarrKeyRefused,
            'slow' => context.localized.subtitleFinderBazarrSlow,
            'server' => context.localized.subtitleFinderBazarrServerError,
            _ => context.localized.subtitleFinderBazarrUnreachable,
          },
        ));
      case SourceStatus.off:
        break;
    }
    final choosing = widget.downloadingKey == SubtitleFinderNotifier.bazarrChoiceKey;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...badges,
        if (widget.onLetBazarrChoose != null)
          Tooltip(
            message: context.localized.subtitleFinderLetBazarrChooseHint,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: widget.downloadingKey == null ? widget.onLetBazarrChoose : null,
              icon: choosing
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(IconsaxPlusLinear.magic_star, size: 18),
              label: Text(choosing ? phaseLabel(context, widget.phase) : context.localized.subtitleFinderLetBazarrChoose),
            ),
          ),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final results = widget.results;
    if (results.searching) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(children: List.generate(3, (_) => const _SkeletonCard())),
      );
    }
    final failed = results.jellyfin == SourceStatus.failed &&
        (results.bazarr == SourceStatus.off || results.bazarr == SourceStatus.failed);

    final (IconData icon, String title, String body) = switch (widget.emptyReason) {
      _ when failed => (
          IconsaxPlusLinear.cloud_cross,
          context.localized.subtitleFinderFailedTitle,
          context.localized.subtitleFinderFailedBody,
        ),
      FinderEmptyReason.noSources => (
          IconsaxPlusLinear.box_remove,
          context.localized.subtitleFinderNoSourcesTitle,
          context.localized.subtitleFinderNoSourcesBody,
        ),
      FinderEmptyReason.notAllowed => (
          IconsaxPlusLinear.lock,
          context.localized.subtitleFinderNotAllowedTitle,
          context.localized.subtitleFinderNotAllowedBody,
        ),
      _ => (
          IconsaxPlusLinear.document_text,
          context.localized.subtitleFinderNothingTitle,
          widget.bazarrConnected
              ? context.localized.subtitleFinderNothingBody
              : context.localized.subtitleFinderNothingBodyNoBazarr,
        ),
    };
    final translation = widget.translation;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 8),
      child: Column(
        spacing: 10,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: theme.colorScheme.onSurfaceVariant),
          ),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (translation != null)
                FilledButton.icon(
                  onPressed: widget.downloadingKey == null ? translation.onTranslate : null,
                  icon: const Icon(Icons.translate_rounded),
                  label: Text(context.localized.subtitleFinderTranslateFrom(translation.fromLabel, translation.toLabel)),
                ),
              if (widget.onRetry != null && widget.emptyReason != FinderEmptyReason.notAllowed)
                OutlinedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(IconsaxPlusLinear.refresh),
                  label: Text(context.localized.retry),
                ),
              if (widget.onConnectBazarr != null && !widget.bazarrConnected)
                FilledButton.tonalIcon(
                  onPressed: widget.onConnectBazarr,
                  icon: const Icon(IconsaxPlusLinear.link),
                  label: Text(context.localized.subtitleFinderConnectBazarr),
                ),
            ],
          ),
          if (translation != null && widget.downloadingKey != null)
            Text(phaseLabel(context, widget.phase), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// The file every result is held up against, in one quiet strip.
class _FileStrip extends StatelessWidget {
  const _FileStrip({required this.file, required this.loading, required this.error});
  final FinderFile? file;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final file = this.file;
    final facts = <String>[
      if (file?.release.resolution != null) file!.release.resolution!,
      if (file?.release.source != null) file!.release.source!.label,
      if (file?.release.streamingService != null) file!.release.streamingService!,
      if (file?.release.videoCodec != null) file!.release.videoCodec!,
      if (file?.release.audioCodec != null) file!.release.audioCodec!,
      if (file?.frameRate != null) '${_fps(file!.frameRate!)} fps',
      if (file?.release.releaseGroup != null) file!.release.releaseGroup!,
    ];
    final note = file == null
        ? null
        : file.fromBazarr
            ? context.localized.subtitleFinderFileFromBazarr
            : file.named
                ? context.localized.subtitleFinderFileNamed
                : context.localized.subtitleFinderFileUnnamed;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(IconsaxPlusLinear.video_square, size: 16, color: scheme.onSurfaceVariant),
              Text(
                context.localized.subtitleFinderYourFile.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, letterSpacing: 0.8),
              ),
              if (file?.fromBazarr == true)
                _Pill(text: 'Bazarr', color: scheme.tertiaryContainer, foreground: scheme.onTertiaryContainer),
              const Spacer(),
              if (loading) const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              if (note != null)
                Tooltip(
                  message: note,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(IconsaxPlusLinear.info_circle, size: 16, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          if (error != null)
            Text(error!, style: TextStyle(color: scheme.error))
          else if (file != null) ...[
            if (file.releaseName != null)
              Text(
                breakableRelease(file.releaseName!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              )
            else
              Text(note!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            if (facts.isNotEmpty)
              Wrap(spacing: 6, runSpacing: 6, children: [for (final fact in facts) _Pill(text: fact)]),
          ],
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.label,
    this.count,
    this.searching = false,
    this.problem,
    this.quiet = false,
    this.hint,
  });

  final String label;
  final int? count;
  final bool searching;
  final String? problem;
  final bool quiet;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bad = problem != null && !quiet;
    final background = bad ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final foreground = bad ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (searching)
            SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: foreground))
          else
            Icon(
              problem != null ? IconsaxPlusLinear.info_circle : IconsaxPlusLinear.tick_circle,
              size: 14,
              color: foreground,
            ),
          Flexible(
            child: Text(
              problem ?? (count == null ? label : '$label · $count'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
    final message = hint ?? (problem != null ? '$label: $problem' : null);
    return message == null ? badge : Tooltip(message: message, child: badge);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
      child: Row(
        spacing: 8,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          Text('$count', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _UnlikelyToggle extends StatelessWidget {
  const _UnlikelyToggle({required this.count, required this.open, required this.onTap});
  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            spacing: 12,
            children: [
              Icon(open ? IconsaxPlusLinear.arrow_up_2 : IconsaxPlusLinear.arrow_down_1, size: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.localized.subtitleFinderUnlikely(count), style: theme.textTheme.titleSmall),
                    Text(
                      context.localized.subtitleFinderUnlikelyHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.match,
    required this.best,
    required this.isEpisode,
    required this.file,
    required this.downloading,
    required this.phase,
    required this.enabled,
    required this.tried,
    required this.onUse,
  });

  final SubtitleMatch match;
  final bool best;
  final bool isEpisode;
  final FinderFile? file;
  final bool downloading;
  final DownloadPhase? phase;
  final bool enabled;
  final bool tried;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final candidate = match.candidate;
    final color = verdictColor(scheme, match.verdict);
    final release = match.scoredRelease ?? candidate.releaseName;
    // Timed for another frame rate: the finder rescales it after the
    // download, so the button says so.
    final fixesFps = match.mismatched.containsKey(MatchField.frameRate) && candidate.frameRate != null;
    final useLabel = fixesFps ? context.localized.subtitleFinderUseAndFix : context.localized.subtitleFinderUse;

    final meta = <String>[
      candidate.provider,
      if (candidate.source == SubtitleSourceKind.bazarr) context.localized.subtitleFinderViaBazarr,
      if (candidate.downloads != null && candidate.downloads! > 0)
        context.localized.subtitleDownloadCount(candidate.downloads!),
      if (candidate.rating != null && candidate.rating! > 0) '★ ${candidate.rating!.toStringAsFixed(1)}',
      if (candidate.uploader?.isNotEmpty == true) candidate.uploader!,
      if (candidate.uploaded != null) '${candidate.uploaded!.year}',
    ];

    final useButton = best
        ? FilledButton(onPressed: enabled ? onUse : null, child: Text(useLabel))
        : FilledButton.tonal(onPressed: enabled ? onUse : null, child: Text(useLabel));
    // On a phone the button beside the text left the release name a few
    // letters a line.
    final narrow = MediaQuery.sizeOf(context).width < 520;

    final background = best
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : match.isUnlikely
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerHigh.withValues(alpha: 0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // The whole card picks it, not just the button: it is a list of
          // choices, and the button is only there to say what a press does.
          onTap: enabled && !downloading ? onUse : null,
          canRequestFocus: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 14,
                  children: [
                    _FitRing(percent: match.percent, color: color),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 6,
                        children: [
                          if (best || tried || match.isUnlikely)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (best)
                                  _Pill(
                                    text: context.localized.subtitleFinderBest,
                                    color: scheme.primary,
                                    foreground: scheme.onPrimary,
                                    icon: IconsaxPlusBold.star_1,
                                  ),
                                if (match.isUnlikely)
                                  _Pill(
                                    text: verdictLabel(context, match),
                                    color: scheme.errorContainer,
                                    foreground: scheme.onErrorContainer,
                                  ),
                                if (tried)
                                  _Pill(
                                    text: context.localized.subtitleFinderTried,
                                    color: scheme.tertiaryContainer,
                                    foreground: scheme.onTertiaryContainer,
                                  ),
                              ],
                            ),
                          Text(
                            release == null ? context.localized.subtitleFinderNoReleaseName : breakableRelease(release),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: release == null ? scheme.onSurfaceVariant : null,
                              fontStyle: release == null ? FontStyle.italic : null,
                              height: 1.25,
                            ),
                          ),
                          _reasons(context),
                          Text(
                            meta.join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (!downloading && !narrow) useButton,
                  ],
                ),
              ),
              if (!downloading && narrow)
                Padding(
                  padding: const EdgeInsets.fromLTRB(76, 0, 14, 12),
                  child: Align(alignment: Alignment.centerRight, child: useButton),
                ),
              if (downloading) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(76, 0, 14, 8),
                  child: Row(
                    children: [
                      Text(phaseLabel(context, phase),
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
                    ],
                  ),
                ),
                const LinearProgressIndicator(minHeight: 3),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// What agrees with the file and what does not, in the file's own terms.
  Widget _reasons(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final release = match.release;
    final ofFile = file?.release;
    final tags = <Widget>[];

    void good(String text) => tags.add(_Pill(
          text: text,
          icon: Icons.check_rounded,
          color: scheme.primary.withValues(alpha: 0.14),
          foreground: scheme.primary,
        ));
    // Red only for what rules a subtitle out; another release group is worth
    // knowing, not worth alarm.
    void bad(String text, {bool serious = false}) => tags.add(_Pill(
          text: text,
          icon: Icons.close_rounded,
          color: serious ? scheme.errorContainer : scheme.surfaceContainerHighest,
          foreground: serious ? scheme.onErrorContainer : scheme.onSurfaceVariant,
        ));

    final matched = match.matched;
    if (matched.contains(MatchField.hash)) good(context.localized.subtitleFinderHashMatch);
    if (isEpisode && release.episodes.isNotEmpty && matched.contains(MatchField.episode)) {
      good(_episode(release.season, release.episodes));
    }
    if (matched.contains(MatchField.releaseGroup)) {
      good(release.releaseGroup ?? ofFile?.releaseGroup ?? context.localized.subtitleFinderReleaseGroup);
    }
    if (matched.contains(MatchField.source)) {
      good(release.source?.label ?? ofFile?.source?.label ?? context.localized.subtitleFinderFieldSource);
    }
    if (matched.contains(MatchField.streamingService) && release.streamingService != null) {
      good(release.streamingService!);
    }
    if (matched.contains(MatchField.edition) && release.edition != null) good(release.edition!);
    if (matched.contains(MatchField.resolution)) good(release.resolution ?? ofFile?.resolution ?? '');
    if (matched.contains(MatchField.videoCodec)) good(release.videoCodec ?? ofFile?.videoCodec ?? '');
    if (matched.contains(MatchField.frameRate) && match.candidate.frameRate != null) {
      good('${_fps(match.candidate.frameRate!)} fps');
    }

    for (final entry in match.mismatched.entries) {
      final (ofSubtitle, ofVideo) = entry.value;
      switch (entry.key) {
        case MatchField.episode:
          bad(context.localized.subtitleFinderOtherEpisode(ofSubtitle), serious: true);
        case MatchField.frameRate:
          bad(context.localized.subtitleFinderOtherFps(ofSubtitle, ofVideo), serious: true);
        case MatchField.edition:
          bad(
              ofVideo.isEmpty
                  ? context.localized.subtitleFinderEditionUnknown(ofSubtitle)
                  : context.localized.subtitleFinderVersus(ofSubtitle, ofVideo),
              serious: match.isUnlikely);
        case MatchField.year:
          bad(context.localized.subtitleFinderVersus(ofSubtitle, ofVideo), serious: match.isUnlikely);
        default:
          bad(ofSubtitle.isEmpty
              ? _fieldName(context, entry.key)
              : context.localized.subtitleFinderVersus(ofSubtitle, ofVideo));
      }
    }

    final candidate = match.candidate;
    if (candidate.hearingImpaired || release.hearingImpaired) {
      tags.add(_Pill(text: context.localized.subtitleFinderSdh));
    }
    if (candidate.forced) {
      tags.add(_Pill(
          text: context.localized.subtitleFinderForced,
          color: scheme.tertiaryContainer,
          foreground: scheme.onTertiaryContainer));
    }
    if (candidate.machineTranslated || candidate.aiTranslated) {
      tags.add(_Pill(
        text: candidate.machineTranslated ? context.localized.machineTranslated : context.localized.aiTranslated,
        color: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
      ));
    }

    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: tags);
  }

  static String _fieldName(BuildContext context, MatchField field) => switch (field) {
        MatchField.releaseGroup => context.localized.subtitleFinderReleaseGroup,
        MatchField.source => context.localized.subtitleFinderFieldSource,
        MatchField.resolution => context.localized.subtitleFinderFieldResolution,
        MatchField.videoCodec => context.localized.subtitleFinderFieldVideoCodec,
        MatchField.audioCodec => context.localized.subtitleFinderFieldAudioCodec,
        MatchField.streamingService => context.localized.subtitleFinderFieldService,
        MatchField.edition => context.localized.subtitleFinderFieldEdition,
        _ => field.name,
      };
}

/// A card-shaped placeholder while the first answers are on their way.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.surfaceContainerHigh;
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: scheme.surfaceContainer, borderRadius: BorderRadius.circular(18)),
        child: Row(
          spacing: 14,
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [bar(double.infinity, 14), bar(180, 12), bar(120, 10)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A release name that may wrap after its dots and dashes: it has no spaces,
/// so a narrow line otherwise broke it anywhere ("DS / NP").
String breakableRelease(String name) => name.replaceAllMapped(RegExp(r'([._\-])'), (m) => '${m[1]}\u200B');

String _episode(int? season, List<int> episodes) {
  final s = season == null ? '' : 'S${season.toString().padLeft(2, '0')}';
  return '$s${episodes.map((e) => 'E${e.toString().padLeft(2, '0')}').join()}';
}

String _fps(double value) {
  final rounded = (value * 1000).round() / 1000;
  return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : '$rounded';
}

Color verdictColor(ColorScheme scheme, MatchVerdict verdict) => switch (verdict) {
      MatchVerdict.exact || MatchVerdict.release => scheme.primary,
      MatchVerdict.likely => scheme.tertiary,
      MatchVerdict.unknown => scheme.outline,
      MatchVerdict.unlikely => scheme.error,
    };

/// The one line that says why a result will not fit, or how well it does.
String verdictLabel(BuildContext context, SubtitleMatch match) {
  if (match.isUnlikely) {
    if (match.mismatched.containsKey(MatchField.episode)) return context.localized.subtitleFinderVerdictWrongEpisode;
    if (match.mismatched.containsKey(MatchField.frameRate)) return context.localized.subtitleFinderVerdictWrongFps;
    if (match.mismatched.containsKey(MatchField.edition)) return context.localized.subtitleFinderVerdictWrongCut;
    if (match.mismatched.containsKey(MatchField.year)) return context.localized.subtitleFinderVerdictWrongYear;
    return context.localized.subtitleFinderVerdictUnlikely;
  }
  return switch (match.verdict) {
    MatchVerdict.exact => context.localized.subtitleFinderVerdictExact,
    MatchVerdict.release => context.localized.subtitleFinderVerdictRelease,
    MatchVerdict.likely => context.localized.subtitleFinderVerdictLikely,
    _ => context.localized.subtitleFinderVerdictUnknown,
  };
}

String phaseLabel(BuildContext context, DownloadPhase? phase) => switch (phase) {
      DownloadPhase.saving => context.localized.subtitleFinderPhaseSaving,
      DownloadPhase.adding => context.localized.subtitleFinderPhaseAdding,
      _ => context.localized.subtitleFinderPhaseFetching,
    };

/// How well it fits, as a ring in the verdict's colour; a dash when there
/// was nothing to compare.
class _FitRing extends StatelessWidget {
  const _FitRing({required this.percent, required this.color});

  /// Null when there was nothing to compare.
  final double? percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = percent;
    return Tooltip(
      message: value == null ? context.localized.subtitleFinderFitUnknown : context.localized.subtitleFinderScoreHint,
      child: SizedBox.square(
        dimension: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: ((value ?? 0) / 100).clamp(0, 1),
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: color.withValues(alpha: 0.14),
              ),
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value == null ? '–' : '${value.round()}'),
                  if (value != null)
                    TextSpan(text: '%', style: theme.textTheme.labelSmall?.copyWith(color: color, fontSize: 9)),
                ],
              ),
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded label: a fact about a file, a reason, a flag.
class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon, this.color, this.foreground});
  final String text;
  final IconData? icon;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = foreground ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color ?? scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          if (icon != null) Icon(icon, size: 12, color: fg),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

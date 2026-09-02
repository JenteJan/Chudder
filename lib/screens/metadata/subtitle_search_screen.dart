import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/account_model.dart';
import 'package:fladder/providers/cultures_provider.dart';
import 'package:fladder/providers/items/subtitle_search_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/screens/shared/adaptive_dialog.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/util/jellyfin_extension.dart';
import 'package:fladder/util/localization_helper.dart';

/// Whether the server would let this account search for and download
/// subtitles (the SubtitleManagement policy; admins have it implicitly).
bool canManageSubtitles(AccountModel? user) =>
    user?.policy?.enableSubtitleManagement == true || user?.policy?.isAdministrator == true;

/// Search the server's subtitle providers for [itemId] and download a
/// result. Resolves with the downloaded subtitle, or null when dismissed.
/// The server stores the file next to the media and re-lists the item on its
/// own; callers refresh what they show once that has had a moment to run.
Future<RemoteSubtitleInfo?> showSubtitleSearchDialog(
  BuildContext context, {
  required String itemId,
  required String itemName,
}) async {
  RemoteSubtitleInfo? downloaded;
  await showDialogAdaptive(
    context: context,
    builder: (context) => SubtitleSearchScreen(
      itemId: itemId,
      itemName: itemName,
      onDownloaded: (subtitle) => downloaded = subtitle,
    ),
  );
  return downloaded;
}

class SubtitleSearchScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String itemName;
  final void Function(RemoteSubtitleInfo subtitle) onDownloaded;

  const SubtitleSearchScreen({
    required this.itemId,
    required this.itemName,
    required this.onDownloaded,
    super.key,
  });

  @override
  ConsumerState<SubtitleSearchScreen> createState() => _SubtitleSearchScreenState();
}

class _SubtitleSearchScreenState extends ConsumerState<SubtitleSearchScreen> {
  AutoDisposeStateNotifierProvider<SubtitleSearchNotifier, SubtitleSearchModel> get provider =>
      subtitleSearchProvider(widget.itemId);

  /// Set once the person picks a language; before that the default follows
  /// the profile's subtitle preference as the culture list arrives.
  bool _languageChosen = false;
  bool _defaultApplied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyDefaultLanguage(ref.read(culturesProvider)));
  }

  void _applyDefaultLanguage(List<CultureDto> cultures) {
    if (_languageChosen || _defaultApplied || !mounted) return;
    final preference = ref.read(userProvider)?.userConfiguration?.subtitleLanguagePreference?.trim().toLowerCase();
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();

    CultureDto? culture;
    if (preference != null && preference.isNotEmpty) {
      culture = cultures.firstWhereOrNull((e) => e.matchesLanguageCode(preference));
    }
    culture ??= cultures.firstWhereOrNull((e) => e.matchesLanguageCode(locale));

    final code = culture?.threeLetterISOLanguageName?.toLowerCase() ??
        ((preference?.length ?? 0) == 3 ? preference : null) ??
        (cultures.isEmpty ? null : 'eng');
    // Cultures not in yet: the listener in build tries again when they land.
    if (code == null) return;
    _defaultApplied = true;
    ref.read(provider.notifier).setLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(culturesProvider, (_, next) => _applyDefaultLanguage(next));
    final state = ref.watch(provider);
    final cultures = ref.watch(culturesProvider);
    final theme = Theme.of(context);

    final entries = cultures
        .where((e) => e.threeLetterISOLanguageName?.isNotEmpty == true)
        .map((e) => DropdownMenuEntry<String>(
              value: e.threeLetterISOLanguageName!.toLowerCase(),
              label: e.displayName ?? e.name ?? e.threeLetterISOLanguageName!,
            ))
        .toList();
    final hasCurrent = entries.any((e) => e.value == state.language);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(top: 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.localized.downloadSubtitles, style: theme.textTheme.titleLarge),
                      Opacity(
                        opacity: 0.7,
                        child: Text(widget.itemName, maxLines: 2, overflow: TextOverflow.ellipsis),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: entries.isEmpty
                      ? TextFormField(
                          initialValue: state.language,
                          decoration: InputDecoration(
                            labelText: context.localized.subtitleSearchLanguage,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (value) {
                            _languageChosen = true;
                            ref.read(provider.notifier).setLanguage(value.trim().toLowerCase());
                          },
                        )
                      : DropdownMenu<String>(
                          // Rebuild when the default lands so the field shows it.
                          key: ValueKey(hasCurrent ? state.language : ''),
                          expandedInsets: EdgeInsets.zero,
                          enableFilter: true,
                          requestFocusOnTap: true,
                          label: Text(context.localized.subtitleSearchLanguage),
                          initialSelection: hasCurrent ? state.language : null,
                          menuHeight: 320,
                          dropdownMenuEntries: entries,
                          onSelected: (value) {
                            if (value == null) return;
                            _languageChosen = true;
                            ref.read(provider.notifier).setLanguage(value);
                          },
                        ),
                ),
                Tooltip(
                  message: context.localized.perfectSubtitleMatchDescription,
                  child: FilterChip(
                    label: Text(context.localized.perfectMatchOnly),
                    selected: state.perfectMatch,
                    onSelected: (value) => ref.read(provider.notifier).setPerfectMatch(value),
                  ),
                ),
              ],
            ),
          ),
          Flexible(child: _results(context, state)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 16,
              children: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.localized.cancel),
                ),
                FilledButton.icon(
                  onPressed: !state.processing && state.language.isNotEmpty
                      ? () => ref.read(provider.notifier).search()
                      : null,
                  icon: state.processing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            backgroundColor: theme.colorScheme.onPrimary,
                            strokeCap: StrokeCap.round,
                          ),
                        )
                      : const Icon(IconsaxPlusLinear.search_normal_1),
                  label: Text(context.localized.search),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(BuildContext context, SubtitleSearchModel state) {
    final theme = Theme.of(context);
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          context.localized.subtitleSearchFailed(state.error!),
          style: TextStyle(color: theme.colorScheme.error),
        ),
      );
    }
    if (state.results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: state.processing
              ? const CircularProgressIndicator(strokeCap: StrokeCap.round)
              : Opacity(
                  opacity: 0.7,
                  child: Text(
                    state.searched ? context.localized.noResults : context.localized.subtitleSearchHint,
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: state.results.length,
      itemBuilder: (context, index) {
        final result = state.results[index];
        final downloading = state.downloadingId != null && state.downloadingId == result.id;
        return ListTile(
          title: Text(result.name ?? context.localized.unknown, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (result.providerName?.isNotEmpty == true) _tag(context, result.providerName!),
                if (result.format?.isNotEmpty == true) _tag(context, result.format!.toUpperCase()),
                if (result.communityRating != null)
                  _tag(context, '★ ${result.communityRating!.toStringAsFixed(1)}'),
                if (result.downloadCount != null)
                  _tag(context, context.localized.subtitleDownloadCount(result.downloadCount!)),
                if (result.isHashMatch == true) _tag(context, context.localized.hashMatch, highlight: true),
                if (result.hearingImpaired == true) _tag(context, context.localized.hearingImpaired),
                if (result.forced == true) _tag(context, context.localized.forcedSubtitle),
                if (result.aiTranslated == true) _tag(context, context.localized.aiTranslated),
                if (result.machineTranslated == true) _tag(context, context.localized.machineTranslated),
                if (result.author?.isNotEmpty == true) Opacity(opacity: 0.6, child: Text(result.author!)),
              ],
            ),
          ),
          trailing: downloading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5, strokeCap: StrokeCap.round),
                )
              : IconButton(
                  tooltip: context.localized.downloadSubtitle,
                  onPressed: state.downloadingId == null ? () => _download(result) : null,
                  icon: const Icon(IconsaxPlusLinear.document_download),
                ),
        );
      },
    );
  }

  Widget _tag(BuildContext context, String text, {bool highlight = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight ? scheme.onPrimaryContainer : null,
            ),
      ),
    );
  }

  Future<void> _download(RemoteSubtitleInfo result) async {
    final name = result.name ?? context.localized.subtitle;
    try {
      await FladderSnack.showResponse(
        ref.read(provider.notifier).download(result),
        successTitle: context.localized.subtitleDownloaded(name),
        errorTitle: (error) => context.localized.subtitleDownloadFailed(error),
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    widget.onDownloaded(result);
    Navigator.of(context).pop();
  }
}

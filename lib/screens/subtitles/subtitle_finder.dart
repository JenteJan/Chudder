import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/models/subtitles/subtitle_match.dart';
import 'package:chudder/providers/cultures_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_fix_service.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/screens/settings/widgets/bazarr_connection_dialog.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/subtitles/subtitle_finder_view.dart';
import 'package:chudder/util/jellyfin_extension.dart';
import 'package:chudder/util/localization_helper.dart';

/// Opens the subtitle finder for [itemId] and resolves with what was
/// downloaded, or null when the viewer closed it without picking.
///
/// It searches as it opens, in the language the viewer most likely wants,
/// and lists what the server's plugins and a connected Bazarr found, best
/// fit to this particular file first. A pick is downloaded and waited on
/// until the server lists it, so the caller can switch it straight on.
///
/// [replacingName] and [replacingLanguage] say that the pick is meant to
/// take the place of a file already there; the caller removes that one.
Future<SubtitleDownload?> showSubtitleFinder(
  BuildContext context, {
  required String itemId,
  required String itemName,
  String? mediaSourceId,
  String? replacingName,
  String? replacingLanguage,
}) async {
  SubtitleDownload? downloaded;
  await showDialogAdaptive(
    context: context,
    builder: (context) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
      child: SubtitleFinder(
        itemId: itemId,
        itemName: itemName,
        mediaSourceId: mediaSourceId,
        replacingName: replacingName,
        replacingLanguage: replacingLanguage,
        onDownloaded: (result) => downloaded = result,
      ),
    ),
  );
  return downloaded;
}

class SubtitleFinder extends ConsumerStatefulWidget {
  const SubtitleFinder({
    required this.itemId,
    required this.itemName,
    required this.onDownloaded,
    this.mediaSourceId,
    this.replacingName,
    this.replacingLanguage,
    super.key,
  });

  final String itemId;
  final String itemName;
  final String? mediaSourceId;
  final String? replacingName;
  final String? replacingLanguage;
  final ValueChanged<SubtitleDownload> onDownloaded;

  @override
  ConsumerState<SubtitleFinder> createState() => _SubtitleFinderState();
}

class _SubtitleFinderState extends ConsumerState<SubtitleFinder> {
  ({String itemId, String? mediaSourceId}) get _key => (itemId: widget.itemId, mediaSourceId: widget.mediaSourceId);

  /// Languages picked from "More languages" this time, kept as chips.
  final List<String> _extra = [];
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (_started || !mounted) return;
    final cultures = ref.read(culturesProvider);
    final suggestions = _suggestions(cultures, ref.read(subtitleItemProvider(_key)).value);
    // Without the culture list the codes cannot be told apart from names yet;
    // the listener in build starts once it lands.
    if (cultures.isEmpty && widget.replacingLanguage == null) return;
    _started = true;
    final first = _resolve(cultures, widget.replacingLanguage) ?? suggestions.firstOrNull?.code ?? 'eng';
    ref.read(subtitleFinderProvider(_key).notifier).selectLanguage(first);
  }

  String? _resolve(List<CultureDto> cultures, String? code) {
    if (code == null || code.isEmpty) return null;
    final culture = cultures.firstWhereOrNull((c) => c.matchesLanguageCode(code));
    return culture?.threeLetterISOLanguageName?.toLowerCase() ?? (code.length == 3 ? code.toLowerCase() : null);
  }

  /// The profile's subtitle language, the app's language, and whatever is
  /// spoken in the file - the ones a person here is likely to want.
  List<FinderLanguage> _suggestions(List<CultureDto> cultures, SubtitleLookup? lookup) {
    final user = ref.read(userProvider);
    final codes = <String?>[
      _resolve(cultures, user?.userConfiguration?.subtitleLanguagePreference?.trim()),
      _resolve(cultures, Localizations.localeOf(context).languageCode),
      for (final audio in lookup?.item.audioLanguages ?? const <String>[]) _resolve(cultures, audio),
      _resolve(cultures, widget.replacingLanguage),
      ..._extra,
    ].nonNulls;
    final seen = <String>{};
    return [
      for (final code in codes)
        if (seen.add(code)) FinderLanguage(code, _label(cultures, code)),
    ];
  }

  String _label(List<CultureDto> cultures, String code) {
    final culture = cultures.firstWhereOrNull((c) => c.matchesLanguageCode(code));
    return culture == null ? code.toUpperCase() : cultureLabel(culture);
  }

  Future<void> _moreLanguages(List<CultureDto> cultures) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _LanguagePicker(cultures: cultures),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!_extra.contains(picked)) _extra.add(picked);
    });
    ref.read(subtitleFinderProvider(_key).notifier).selectLanguage(picked);
  }

  Future<void> _use(SubtitleMatch match) async {
    final localized = context.localized;
    try {
      var result = await ref.read(subtitleFinderProvider(_key).notifier).download(match);
      result = await _fixFrameRate(match, result);
      // Handed over even if the finder is gone by now: the file is on the
      // server either way, and whoever opened the finder has to know - a
      // replacement still has an old file to take away.
      widget.onDownloaded(result);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      FladderSnack.show(localized.subtitleDownloadFailed('$error'), duration: const Duration(seconds: 8));
    }
  }

  /// A subtitle timed for another frame rate is made to fit before it is
  /// handed over: rescaled from its rate to the video's. If that cannot be
  /// done here, the download stands as it is.
  Future<SubtitleDownload> _fixFrameRate(SubtitleMatch match, SubtitleDownload result) async {
    final localized = context.localized;
    final from = match.candidate.frameRate;
    final to = ref.read(subtitleItemProvider(_key)).value?.item.frameRate;
    final stream = result.stream;
    if (!match.mismatched.containsKey(MatchField.frameRate) || from == null || to == null || stream?.index == null) {
      return result;
    }
    try {
      final service = ref.read(subtitleFixServiceProvider);
      final plan = await service.plan(SubtitleFileRef(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
        index: stream!.index!,
        path: stream.path,
        codec: stream.codec,
        language: stream.language,
        forced: stream.isForced ?? false,
        hearingImpaired: stream.isHearingImpaired ?? false,
        isExternal: stream.isExternal ?? true,
      ));
      final fix = FrameRateFix(from, to);
      if (!plan.supports(fix)) return result;
      final fixed = await service.apply(plan, fix);
      return SubtitleDownload(match: match, stream: fixed.stream ?? stream, savedPath: fixed.path);
    } catch (error) {
      FladderSnack.show(localized.subtitleFixFailed('$error'));
      return result;
    }
  }

  Future<void> _letBazarrChoose() async {
    final localized = context.localized;
    try {
      final result = await ref.read(subtitleFinderProvider(_key).notifier).letBazarrChoose();
      widget.onDownloaded(result);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      FladderSnack.show(localized.subtitleDownloadFailed('$error'), duration: const Duration(seconds: 8));
    }
  }

  /// A subtitle next to the video in another language, for Bazarr to
  /// translate from - English first, as the likeliest to be good.
  dto.MediaStream? _translationSource(SubtitleLookup? lookup, String? language) {
    if (lookup?.bazarr == null || language == null) return null;
    final files = lookup!.item.subtitleStreams
        .where((s) => s.isExternal == true && s.path != null && s.language?.toLowerCase() != language)
        .toList();
    return files.firstWhereOrNull((s) => s.language?.toLowerCase() == 'eng') ?? files.firstOrNull;
  }

  Future<void> _translate(dto.MediaStream source, String language) async {
    final localized = context.localized;
    final cultures = ref.read(culturesProvider);
    final two = cultures.firstWhereOrNull((c) => c.matchesLanguageCode(language))?.twoLetterISOLanguageName;
    if (two == null || source.index == null) return;
    setState(() => _translating = true);
    try {
      final service = ref.read(subtitleFixServiceProvider);
      final plan = await service.plan(SubtitleFileRef(
        itemId: widget.itemId,
        mediaSourceId: widget.mediaSourceId,
        index: source.index!,
        path: source.path,
        codec: source.codec,
        language: source.language,
        forced: source.isForced ?? false,
        hearingImpaired: source.isHearingImpaired ?? false,
      ));
      final fix = TranslateFix(two.toLowerCase());
      if (!plan.supports(fix)) throw SubtitleFixException(localized.subtitleFixUnavailable);
      final result = await service.apply(plan, fix);
      widget.onDownloaded(SubtitleDownload(stream: result.stream, savedPath: result.path));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      FladderSnack.show(localized.subtitleFixFailed('$error'), duration: const Duration(seconds: 8));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  bool _translating = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(culturesProvider, (_, __) => _start());
    final state = ref.watch(subtitleFinderProvider(_key));
    final lookup = ref.watch(subtitleItemProvider(_key));
    final cultures = ref.watch(culturesProvider);
    final user = ref.watch(userProvider);
    final sources = ref.watch(serverSubtitleSourcesProvider).value;
    final tried = ref.watch(triedSubtitlesProvider.select((t) => t[widget.itemId]))?.keys.toSet() ?? const {};
    final bazarrConnected = user?.bazarrCredentials?.isConfigured ?? false;
    final isAdmin = user?.policy?.isAdministrator == true;

    final item = lookup.value?.item;
    final release = item?.release;

    final FinderEmptyReason? emptyReason;
    if (!canFindSubtitles(user)) {
      emptyReason = FinderEmptyReason.notAllowed;
    } else if (sources != null && sources.isEmpty && !bazarrConnected) {
      emptyReason = FinderEmptyReason.noSources;
    } else {
      emptyReason = FinderEmptyReason.nothingFound;
    }

    // Mid-download a stray Escape would drop the hand-off, and a replacement
    // would leave the old file behind: hold still until it is done.
    final translateFrom = state.current.finished && state.current.matches.isEmpty
        ? _translationSource(lookup.value, state.language)
        : null;
    final busy = state.downloadingKey != null || _translating;

    return PopScope(
      canPop: !busy,
      child: SubtitleFinderView(
      itemName: widget.itemName,
      isEpisode: item?.isEpisode ?? false,
      languages: _suggestions(cultures, lookup.value),
      language: state.language,
      results: state.current,
      tried: tried,
      replacingName: widget.replacingName,
      emptyReason: emptyReason,
      bazarrConnected: bazarrConnected,
      bazarrMissing: lookup.value?.bazarrMissing ?? false,
      fileLoading: lookup.isLoading,
      fileError: lookup.hasError ? '${lookup.error}' : null,
      file: item == null
          ? null
          : FinderFile(
              release: release!.release,
              releaseName: release.from,
              fromBazarr: item.sceneName != null && release.from == item.sceneName,
              named: release.named,
              frameRate: item.frameRate,
            ),
      preferHearingImpaired: state.preferHearingImpaired,
      onHearingImpaired: (value) => ref.read(subtitleFinderProvider(_key).notifier).setHearingImpaired(value),
      downloadingKey: _translating ? 'translating' : state.downloadingKey,
      onLetBazarrChoose: lookup.value?.bazarr != null ? _letBazarrChoose : null,
      translation: translateFrom == null || state.language == null
          ? null
          : FinderTranslation(
              fromLabel: _label(cultures, translateFrom.language ?? ''),
              toLabel: _label(cultures, state.language!),
              onTranslate: () => _translate(translateFrom, state.language!),
            ),
      phase: state.phase,
      onLanguage: (code) => ref.read(subtitleFinderProvider(_key).notifier).selectLanguage(code),
      onMoreLanguages: cultures.isEmpty ? null : () => _moreLanguages(cultures),
      onRetry: () => ref.read(subtitleFinderProvider(_key).notifier).retry(),
      onConnectBazarr: isAdmin && !bazarrConnected
          ? () async {
              await showBazarrConnectionDialog(context);
              if (!mounted) return;
              ref.invalidate(subtitleItemProvider(_key));
              ref.read(subtitleFinderProvider(_key).notifier).retry();
            }
          : null,
      onUse: _use,
      onClose: busy ? null : () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// Asks which language to have Bazarr translate a subtitle into: the
/// profile's subtitle language first, any other from the full list.
Future<TranslateFix?> askTranslation(BuildContext context, WidgetRef ref) async {
  final cultures = ref.read(culturesProvider);
  final preference = ref.read(userProvider)?.userConfiguration?.subtitleLanguagePreference?.trim();
  final preferred = preference == null || preference.isEmpty
      ? null
      : cultures.firstWhereOrNull((c) => c.matchesLanguageCode(preference));
  final locale = cultures.firstWhereOrNull((c) => c.matchesLanguageCode(Localizations.localeOf(context).languageCode));
  final suggestions =
      {preferred, locale}.nonNulls.where((c) => c.twoLetterISOLanguageName?.isNotEmpty == true).toList();

  final picked = await showDialog<CultureDto>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.localized.subtitleFixTranslateTitle),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(context.localized.subtitleFixTranslateBody),
        ),
        for (final culture in suggestions)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(culture),
            child: ListTile(leading: const Icon(Icons.translate_rounded), title: Text(cultureLabel(culture))),
          ),
        SimpleDialogOption(
          onPressed: () async {
            final code = await showDialog<String>(
              context: context,
              builder: (context) => _LanguagePicker(cultures: cultures),
            );
            if (!context.mounted) return;
            Navigator.of(context).pop(code == null ? null : cultures.firstWhereOrNull((c) => c.matchesLanguageCode(code)));
          },
          child: ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(context.localized.subtitleFinderMoreLanguages),
          ),
        ),
      ],
    ),
  );
  final two = picked?.twoLetterISOLanguageName?.toLowerCase();
  return two == null || two.isEmpty ? null : TranslateFix(two);
}

/// A language's everyday name: "Dutch" for "Dutch; Flemish", "Spanish"
/// for "Spanish; Castilian".
String cultureLabel(CultureDto culture) {
  final name = culture.displayName ?? culture.name ?? culture.threeLetterISOLanguageName ?? '';
  return name.split(RegExp(r'[;(]')).first.trim();
}

/// Languages people write subtitles in: the ones with a two-letter code.
/// The full ISO 639-2 list also carries Afrihili and Middle Dutch.
List<CultureDto> subtitleCultures(List<CultureDto> cultures) {
  final list = cultures
      .where((c) => c.threeLetterISOLanguageName?.isNotEmpty == true && c.twoLetterISOLanguageName?.isNotEmpty == true)
      .toList()
    ..sort((a, b) => cultureLabel(a).toLowerCase().compareTo(cultureLabel(b).toLowerCase()));
  return list;
}

/// Every language worth subtitling in, searchable by name or code, with
/// the keyboard as well as the pointer: type, Enter takes the top match,
/// Down walks into the list.
class _LanguagePicker extends StatefulWidget {
  const _LanguagePicker({required this.cultures});
  final List<CultureDto> cultures;

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  String _query = '';
  late final List<CultureDto> _all = subtitleCultures(widget.cultures);
  final FocusNode _firstResult = FocusNode();

  @override
  void dispose() {
    _firstResult.dispose();
    super.dispose();
  }

  List<CultureDto> get _matches {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _all;
    final starts = <CultureDto>[];
    final contains = <CultureDto>[];
    for (final c in _all) {
      final label = cultureLabel(c).toLowerCase();
      if (label.startsWith(query) || c.matchesLanguageCode(query)) {
        starts.add(c);
      } else if (label.contains(query)) {
        contains.add(c);
      }
    }
    return [...starts, ...contains];
  }

  void _pick(CultureDto culture) => Navigator.of(context).pop(culture.threeLetterISOLanguageName!.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final list = _matches;
    return AlertDialog(
      title: Text(context.localized.subtitleFinderMoreLanguages),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () => _firstResult.requestFocus(),
                },
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: context.localized.search,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                  onSubmitted: (_) {
                    if (list.isNotEmpty) _pick(list.first);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text(context.localized.noResults))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final culture = list[index];
                        return ListTile(
                          focusNode: index == 0 ? _firstResult : null,
                          dense: true,
                          title: Text(cultureLabel(culture)),
                          trailing: Opacity(
                            opacity: 0.6,
                            child: Text(culture.threeLetterISOLanguageName!.toUpperCase()),
                          ),
                          onTap: () => _pick(culture),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.localized.cancel)),
      ],
    );
  }
}

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/bazarr_credentials_model.dart';
import 'package:chudder/models/subtitles/subtitle_match.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/cultures_provider.dart';
import 'package:chudder/providers/subtitles/bazarr_client.dart';
import 'package:chudder/providers/subtitles/subtitle_item.dart';
import 'package:chudder/providers/user_provider.dart';

final _log = Logger('SubtitleFinder');

/// Whether the server lets this account search for and download subtitles
/// through its own plugins (the SubtitleManagement policy; admins have it).
bool canManageSubtitles(AccountModel? user) =>
    user?.policy?.enableSubtitleManagement == true || user?.policy?.isAdministrator == true;

/// Whether this account can find subtitles at all: through the server, or
/// through a Bazarr it is connected to.
bool canFindSubtitles(AccountModel? user) =>
    canManageSubtitles(user) || (user?.bazarrCredentials?.isConfigured ?? false);

/// The Bazarr connection for the signed-in account, or null.
///
/// Kept for the whole session, not auto-disposed: it is read once by
/// whatever uses it, and an auto-disposed one was torn down between the read
/// and the request - closing its own connection mid-search.
final bazarrClientProvider = Provider<BazarrClient?>((ref) {
  final credentials = ref.watch(userProvider.select((u) => u?.bazarrCredentials));
  if (credentials == null || !credentials.isConfigured) return null;
  final client = BazarrClient(credentials);
  ref.onDispose(client.close);
  return client;
});

/// The item, read fresh from the server, with Bazarr's scene name folded in
/// when Bazarr has it. Kept for as long as someone is looking at it.
final subtitleItemProvider =
    FutureProvider.autoDispose.family<SubtitleLookup, ({String itemId, String? mediaSourceId})>(
  (ref, key) => loadSubtitleLookup(ref, itemId: key.itemId, mediaSourceId: key.mediaSourceId),
);

/// What [subtitleItemProvider] holds, for callers that need it once.
Future<SubtitleLookup> loadSubtitleLookup(Ref ref, {required String itemId, String? mediaSourceId}) async {
  final api = ref.read(jellyApiProvider).api;
  final userId = ref.read(userProvider)?.id;
  final response = await api.itemsItemIdGet(itemId: itemId, userId: userId);
  final body = response.body;
  if (!response.isSuccessful || body == null) {
    throw Exception('The server did not return the item (${response.statusCode})');
  }
  dto.BaseItemDto? series;
  if (body.type == dto.BaseItemKind.episode && body.seriesId != null) {
    series = (await api.itemsItemIdGet(itemId: body.seriesId, userId: userId)).body;
  }
  final item = SubtitleItem.fromDto(body, series: series, mediaSourceId: mediaSourceId);

  final bazarr = ref.read(bazarrClientProvider);
  if (bazarr == null) return SubtitleLookup(item: item);
  try {
    final target = await findBazarrTarget(bazarr, item);
    if (target == null) return SubtitleLookup(item: item, bazarrMissing: true);
    return SubtitleLookup(item: item.withSceneName(target.sceneName), bazarr: target);
  } catch (error) {
    _log.warning('Bazarr lookup failed: $error');
    return SubtitleLookup(item: item, bazarrError: error);
  }
}

Future<BazarrTarget?> findBazarrTarget(BazarrClient bazarr, SubtitleItem item) {
  if (item.isEpisode) {
    if (item.season == null || item.episode == null) return Future.value(null);
    return bazarr.findEpisode(
      seriesTitle: item.seriesTitle ?? item.title,
      seriesImdbId: item.seriesImdbId,
      seriesTvdbId: item.seriesTvdbId,
      seriesYear: item.seriesYear,
      season: item.season!,
      episode: item.episode!,
      fileName: item.fileName,
    );
  }
  return bazarr.findMovie(title: item.title, imdbId: item.imdbId, year: item.year, fileName: item.fileName);
}

/// The subtitle sources the server has installed, by name. Only an admin
/// may ask, so null means "cannot tell", not "none".
final serverSubtitleSourcesProvider = FutureProvider.autoDispose<List<String>?>((ref) async {
  if (ref.watch(userProvider.select((u) => u?.policy?.isAdministrator)) != true) return null;
  final api = ref.read(jellyApiProvider).api;
  final names = <String>{};
  for (final type in [
    dto.LibrariesAvailableOptionsGetLibraryContentType.movies,
    dto.LibrariesAvailableOptionsGetLibraryContentType.tvshows,
  ]) {
    final response = await api.librariesAvailableOptionsGet(libraryContentType: type);
    if (!response.isSuccessful) return null;
    names.addAll((response.body?.subtitleFetchers ?? const []).map((e) => e.name).nonNulls);
  }
  return names.toList();
});

/// What went wrong with Bazarr, as one of a few codes the screen puts into
/// words - never the exception itself, which carries the server's address.
String bazarrErrorCode(Object error) => switch (error) {
      BazarrException(error: BazarrError.unauthorized) => 'unauthorized',
      BazarrException(error: BazarrError.notFound) => 'not-in-bazarr',
      BazarrException(error: BazarrError.server) => 'server',
      BazarrException(error: BazarrError.notBazarr) => 'unreachable',
      TimeoutException() => 'slow',
      _ => 'unreachable',
    };

class SubtitleLookup {
  const SubtitleLookup({required this.item, this.bazarr, this.bazarrMissing = false, this.bazarrError});
  final SubtitleItem item;

  /// The item on Bazarr's side, when a Bazarr is connected and knows it.
  final BazarrTarget? bazarr;
  final bool bazarrMissing;
  final Object? bazarrError;
}

/// Where one source stands for the language being looked at.
enum SourceStatus { off, searching, done, failed }

class LanguageResults {
  const LanguageResults({
    this.matches = const [],
    this.jellyfin = SourceStatus.off,
    this.bazarr = SourceStatus.off,
    this.jellyfinError,
    this.bazarrError,
  });

  final List<SubtitleMatch> matches;
  final SourceStatus jellyfin;
  final SourceStatus bazarr;
  final String? jellyfinError;
  final String? bazarrError;

  bool get searching => jellyfin == SourceStatus.searching || bazarr == SourceStatus.searching;
  bool get finished => !searching;

  LanguageResults copyWith({
    List<SubtitleMatch>? matches,
    SourceStatus? jellyfin,
    SourceStatus? bazarr,
    String? jellyfinError,
    String? bazarrError,
  }) =>
      LanguageResults(
        matches: matches ?? this.matches,
        jellyfin: jellyfin ?? this.jellyfin,
        bazarr: bazarr ?? this.bazarr,
        jellyfinError: jellyfinError ?? this.jellyfinError,
        bazarrError: bazarrError ?? this.bazarrError,
      );
}

/// How far a download has come.
enum DownloadPhase {
  /// The source is fetching it from the site.
  fetching,

  /// Bazarr is writing the file next to the video.
  saving,

  /// Waiting for the server to list the new file.
  adding,
}

class SubtitleFinderState {
  const SubtitleFinderState({
    this.language,
    this.results = const {},
    this.preferHearingImpaired,
    this.downloadingKey,
    this.phase,
  });

  /// Three letters, as the server's providers want it.
  final String? language;
  final Map<String, LanguageResults> results;
  final bool? preferHearingImpaired;
  final String? downloadingKey;
  final DownloadPhase? phase;

  LanguageResults get current => results[language] ?? const LanguageResults();

  SubtitleFinderState copyWith({
    String? language,
    Map<String, LanguageResults>? results,
    bool? Function()? preferHearingImpaired,
    String? Function()? downloadingKey,
    DownloadPhase? Function()? phase,
  }) =>
      SubtitleFinderState(
        language: language ?? this.language,
        results: results ?? this.results,
        preferHearingImpaired: preferHearingImpaired != null ? preferHearingImpaired() : this.preferHearingImpaired,
        downloadingKey: downloadingKey != null ? downloadingKey() : this.downloadingKey,
        phase: phase != null ? phase() : this.phase,
      );
}

/// What a finished download left behind.
class SubtitleDownload {
  const SubtitleDownload({this.match, this.stream, this.savedPath});

  /// The search result it came from; none when Bazarr chose or translated.
  final SubtitleMatch? match;

  /// The new stream as the server lists it, once it does.
  final dto.MediaStream? stream;

  /// Where Bazarr wrote the file, if Bazarr did it.
  final String? savedPath;

  /// Saved, but the server has not listed it yet (it will at its next scan).
  bool get pending => stream == null;
}

class SubtitleDownloadException implements Exception {
  const SubtitleDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The last item whose subtitle files changed from inside the player, so a
/// details page underneath can reload rather than list files that are gone.
class SubtitleChange {
  const SubtitleChange(this.itemId, this.parentId, this.revision);
  final String itemId;

  /// The series, for an episode: a show page lists its episodes' tracks.
  final String? parentId;
  final int revision;

  bool concerns(String id) => itemId == id || parentId == id;
}

final subtitleChangeProvider = StateProvider<SubtitleChange?>((ref) => null);

/// Tells pages that [itemId]'s subtitle files changed.
void markSubtitlesChanged(StateController<SubtitleChange?> controller, String itemId, String? parentId) {
  controller.state = SubtitleChange(itemId, parentId, (controller.state?.revision ?? 0) + 1);
}

/// Subtitles the viewer downloaded this session and the file each became,
/// per item - so the list can say "you tried this one", and "try another"
/// knows which file to take away.
final triedSubtitlesProvider = StateProvider<Map<String, Map<String, String?>>>((ref) => const {});

final subtitleFinderProvider = StateNotifierProvider.autoDispose
    .family<SubtitleFinderNotifier, SubtitleFinderState, ({String itemId, String? mediaSourceId})>(
  (ref, key) => SubtitleFinderNotifier(ref, key.itemId, key.mediaSourceId),
);

class SubtitleFinderNotifier extends StateNotifier<SubtitleFinderState> {
  SubtitleFinderNotifier(this.ref, this.itemId, this.mediaSourceId) : super(const SubtitleFinderState());

  final Ref ref;
  final String itemId;
  final String? mediaSourceId;

  /// One Bazarr search covers every language of the item's profile, and
  /// takes as long as its slowest provider - so it runs once and every
  /// language picks its share out of it.
  Future<List<BazarrResult>>? _bazarrSearch;

  ({String itemId, String? mediaSourceId}) get _key => (itemId: itemId, mediaSourceId: mediaSourceId);

  Future<SubtitleLookup> get _lookup => ref.read(subtitleItemProvider(_key).future);

  void setHearingImpaired(bool? value) {
    state = state.copyWith(preferHearingImpaired: () => value);
    _rescore();
  }

  /// Shows [language], searching it the first time it is asked for.
  Future<void> selectLanguage(String language) async {
    final code = language.toLowerCase();
    state = state.copyWith(language: code);
    if (state.results[code] != null && state.results[code]!.jellyfin != SourceStatus.failed) return;
    await search(code);
  }

  Future<void> retry() async {
    final language = state.language;
    if (language == null) return;
    // A lookup that failed stays failed until it is asked again.
    ref.invalidate(subtitleItemProvider(_key));
    await search(language, force: true);
  }

  Future<void> search(String language, {bool force = false}) async {
    if (force) _bazarrSearch = null;
    final user = ref.read(userProvider);
    final useJellyfin = canManageSubtitles(user);
    final bazarr = ref.read(bazarrClientProvider);

    _put(
      language,
      LanguageResults(
        jellyfin: useJellyfin ? SourceStatus.searching : SourceStatus.off,
        bazarr: bazarr != null ? SourceStatus.searching : SourceStatus.off,
      ),
    );

    final SubtitleLookup lookup;
    try {
      lookup = await _lookup;
    } catch (error) {
      _put(language, LanguageResults(jellyfin: SourceStatus.failed, jellyfinError: '$error'));
      return;
    }
    if (!mounted) return;

    await Future.wait([
      if (useJellyfin) _searchJellyfin(language, lookup),
      if (bazarr != null) _searchBazarr(language, lookup, bazarr),
    ]);
  }

  Future<void> _searchJellyfin(String language, SubtitleLookup lookup) async {
    try {
      final response = await ref.read(jellyApiProvider).api.itemsItemIdRemoteSearchSubtitlesLanguageGet(
            itemId: itemId,
            language: language,
          );
      if (!mounted) return;
      if (!response.isSuccessful) {
        _merge(language, jellyfin: SourceStatus.failed, jellyfinError: '${response.statusCode}');
        return;
      }
      final candidates = [
        for (final info in response.body ?? const <dto.RemoteSubtitleInfo>[])
          if (info.id?.isNotEmpty == true) _fromJellyfin(info, language),
      ];
      _merge(language, jellyfin: SourceStatus.done, from: SubtitleSourceKind.jellyfin, add: candidates, lookup: lookup);
    } catch (error) {
      if (!mounted) return;
      _log.warning('Server subtitle search failed: $error');
      _merge(language, jellyfin: SourceStatus.failed, jellyfinError: 'unreachable');
    }
  }

  Future<void> _searchBazarr(String language, SubtitleLookup lookup, BazarrClient bazarr) async {
    final target = lookup.bazarr;
    if (target == null) {
      _merge(language,
          bazarr: SourceStatus.failed,
          bazarrError: lookup.bazarrError != null ? bazarrErrorCode(lookup.bazarrError!) : 'not-in-bazarr');
      return;
    }
    try {
      _bazarrSearch ??= switch (target) {
        BazarrMovie(:final radarrId) => bazarr.searchMovie(radarrId),
        BazarrEpisode(:final episodeId) => bazarr.searchEpisode(episodeId),
      };
      final all = await _bazarrSearch!;
      if (!mounted) return;
      final wanted = _twoLetter(language);
      final candidates = [
        for (final result in all)
          if (_languageMatches(result.language, language, wanted) && result.token.isNotEmpty)
            _fromBazarr(result, language),
      ];
      _merge(language, bazarr: SourceStatus.done, from: SubtitleSourceKind.bazarr, add: candidates, lookup: lookup);
    } catch (error) {
      _bazarrSearch = null;
      if (!mounted) return;
      _log.warning('Bazarr search failed: $error');
      _merge(language, bazarr: SourceStatus.failed, bazarrError: bazarrErrorCode(error));
    }
  }

  String? _twoLetter(String threeLetter) {
    final culture = ref.read(culturesProvider).firstWhereOrNull((c) =>
        c.threeLetterISOLanguageName?.toLowerCase() == threeLetter ||
        (c.threeLetterISOLanguageNames?.any((v) => v.toLowerCase() == threeLetter) ?? false));
    return culture?.twoLetterISOLanguageName?.toLowerCase();
  }

  static bool _languageMatches(String bazarrCode, String threeLetter, String? twoLetter) {
    final code = bazarrCode.toLowerCase().split(RegExp('[-_:]')).first;
    return code == threeLetter || (twoLetter != null && code == twoLetter);
  }

  SubtitleCandidate _fromJellyfin(dto.RemoteSubtitleInfo info, String language) {
    final comment = info.comment?.trim();
    return SubtitleCandidate(
      key: 'jf:${info.id}',
      source: SubtitleSourceKind.jellyfin,
      provider: info.providerName ?? '',
      language: info.threeLetterISOLanguageName ?? language,
      releaseName: info.name,
      // Uploaders list the other releases a file fits in the comment, one
      // per line or comma-separated; only the ones shaped like release names
      // are worth scoring.
      otherReleases: [
        if (comment != null)
          for (final part in comment.split(RegExp(r'[\n,;|]')))
            if (RegExp(r'^\S+[.\-_]\S+[.\-_]\S+$').hasMatch(part.trim()) && part.trim().length > 8) part.trim(),
      ],
      format: info.format,
      uploader: info.author,
      comment: comment,
      frameRate: info.frameRate,
      downloads: info.downloadCount,
      rating: info.communityRating,
      uploaded: info.dateCreated,
      hashMatch: info.isHashMatch == true,
      hearingImpaired: info.hearingImpaired == true,
      forced: info.forced == true,
      machineTranslated: info.machineTranslated == true,
      aiTranslated: info.aiTranslated == true,
      payload: info,
    );
  }

  SubtitleCandidate _fromBazarr(BazarrResult result, String language) {
    final release = result.releases.firstOrNull;
    return SubtitleCandidate(
      // Bazarr hands out a new token every search, so the key is what the
      // file is, not how to fetch it.
      key: 'bz:${result.provider}:${release ?? result.url ?? result.token}:${result.hearingImpaired}',
      source: SubtitleSourceKind.bazarr,
      provider: _providerLabel(result.provider),
      language: language,
      releaseName: release,
      otherReleases: result.releases.skip(1).toList(),
      uploader: result.uploader,
      hearingImpaired: result.hearingImpaired,
      forced: result.forced,
      hashMatch: result.matches.contains('hash'),
      sourceScore: result.score,
      sourceMatches: BazarrResult.fields(result.matches),
      sourceMismatches: BazarrResult.fields(result.dontMatches),
      payload: result,
    );
  }

  static String _providerLabel(String provider) => switch (provider.toLowerCase()) {
        'opensubtitlescom' => 'OpenSubtitles.com',
        'opensubtitles' => 'OpenSubtitles.org',
        'podnapisi' => 'Podnapisi',
        'addic7ed' => 'Addic7ed',
        'subdl' => 'Subdl',
        'subf2m' => 'Subf2m',
        'yifysubtitles' => 'YIFY',
        'embeddedsubtitles' => 'Embedded',
        'gestdown' => 'Gestdown',
        'supersubtitles' => 'SuperSubtitles',
        'tvsubtitles' => 'TVsubtitles',
        'animetosho' => 'AnimeTosho',
        'jimaku' => 'Jimaku',
        'whisperai' => 'Whisper (AI)',
        _ => provider,
      };

  final Map<String, List<SubtitleCandidate>> _candidates = {};
  SubtitleTarget? _target;

  void _merge(
    String language, {
    SourceStatus? jellyfin,
    SourceStatus? bazarr,
    String? jellyfinError,
    String? bazarrError,
    SubtitleSourceKind? from,
    List<SubtitleCandidate> add = const [],
    SubtitleLookup? lookup,
  }) {
    if (lookup != null) _target = lookup.item.target;
    final list = _candidates.putIfAbsent(language, () => []);
    // A source's answer replaces its last one, empty or not.
    if (from != null) {
      list
        ..removeWhere((c) => c.source == from)
        ..addAll(add);
    }
    final existing = state.results[language] ?? const LanguageResults();
    _put(
      language,
      existing.copyWith(
        matches: _score(list),
        jellyfin: jellyfin,
        bazarr: bazarr,
        jellyfinError: jellyfinError,
        bazarrError: bazarrError,
      ),
    );
  }

  List<SubtitleMatch> _score(List<SubtitleCandidate> candidates) {
    final target = _target;
    if (target == null) return const [];
    final matches = [
      for (final candidate in candidates)
        scoreSubtitle(candidate, target, preferHearingImpaired: state.preferHearingImpaired),
    ];
    // The same file found by both: Bazarr's copy carries its own score
    // against the release name from before the rename, so it stays.
    String? sameFile(SubtitleCandidate c) {
      final release = c.releaseName?.trim().toLowerCase();
      if (release == null || release.isEmpty) return null;
      final site = c.provider.toLowerCase().replaceAll(' ', '').split('.').first;
      return '$site|$release|${c.hearingImpaired}';
    }

    final fromBazarr = {
      for (final m in matches)
        if (m.candidate.source == SubtitleSourceKind.bazarr && sameFile(m.candidate) != null) sameFile(m.candidate)!,
    };
    matches.removeWhere(
        (m) => m.candidate.source == SubtitleSourceKind.jellyfin && fromBazarr.contains(sameFile(m.candidate)));
    return matches..sort(compareMatches);
  }

  void _rescore() {
    final updated = {
      for (final entry in state.results.entries)
        entry.key: entry.value.copyWith(matches: _score(_candidates[entry.key] ?? const [])),
    };
    state = state.copyWith(results: updated);
  }

  void _put(String language, LanguageResults results) {
    if (!mounted) return;
    state = state.copyWith(results: {...state.results, language: results});
  }

  /// Downloads [match] and waits until the server lists the new file, so
  /// the caller can switch it on. Throws [SubtitleDownloadException] with a
  /// sentence for the viewer when it goes wrong.
  Future<SubtitleDownload> download(SubtitleMatch match) async {
    final candidate = match.candidate;
    state = state.copyWith(downloadingKey: () => candidate.key, phase: () => DownloadPhase.fetching);
    try {
      final lookup = await _lookup;
      final before = await _currentSubtitlePaths(lookup.item) ?? lookup.item.externalSubtitlePaths;
      SubtitleDownload result;
      switch (candidate.payload) {
        case dto.RemoteSubtitleInfo info:
          result = await _downloadThroughJellyfin(match, info, before);
        case BazarrResult bazarrResult:
          result = await _downloadThroughBazarr(match, bazarrResult, lookup, before);
        default:
          throw const SubtitleDownloadException('Unknown source');
      }
      final tried = ref.read(triedSubtitlesProvider);
      ref.read(triedSubtitlesProvider.notifier).state = {
        ...tried,
        itemId: {...?tried[itemId], candidate.key: result.stream?.path ?? result.savedPath},
      };
      return result;
    } finally {
      if (mounted) state = state.copyWith(downloadingKey: () => null, phase: () => null);
    }
  }

  Future<SubtitleDownload> _downloadThroughJellyfin(
    SubtitleMatch match,
    dto.RemoteSubtitleInfo info,
    Set<String> before,
  ) async {
    final response = await ref.read(jellyApiProvider).api.itemsItemIdRemoteSearchSubtitlesSubtitleIdPost(
          itemId: itemId,
          subtitleId: info.id,
        );
    if (!response.isSuccessful) {
      throw SubtitleDownloadException(_describe(response.statusCode, response.error));
    }
    if (mounted) state = state.copyWith(phase: () => DownloadPhase.adding);
    // The server saves the file, then queues its own refresh of the item.
    final stream = await _awaitNewStream(before, attempts: 12);
    return SubtitleDownload(match: match, stream: stream);
  }

  Future<SubtitleDownload> _downloadThroughBazarr(
    SubtitleMatch match,
    BazarrResult result,
    SubtitleLookup lookup,
    Set<String> before,
  ) async {
    final bazarr = ref.read(bazarrClientProvider);
    final target = lookup.bazarr;
    if (bazarr == null || target == null) throw const SubtitleDownloadException('Bazarr is not connected');
    final savedPath = await _bazarrSaves(bazarr, target, () => bazarr.download(target, result));

    if (mounted) state = state.copyWith(phase: () => DownloadPhase.adding);
    // Jellyfin finds a file someone else put there at its next scan; an
    // admin can ask for that scan now.
    await _refreshServerItem();
    // Written over a file the server already lists: that stream is the new
    // subtitle now, under its old name.
    final savedName = _baseName(savedPath);
    final overwritten = before.firstWhereOrNull((p) => _baseName(p) == savedName);
    final stream = await _awaitNewStream(
      overwritten == null ? before : before.difference({overwritten}),
      attempts: 10,
    );
    return SubtitleDownload(match: match, stream: stream, savedPath: savedPath);
  }

  /// Runs [start] on Bazarr and waits until it has written a subtitle file.
  /// Bazarr names its file after the video and the language, and writes over
  /// one of the same name - so a new path is not the only sign it worked.
  /// Its history gets an entry for every download, and that is.
  Future<String> _bazarrSaves(BazarrClient bazarr, BazarrTarget target, Future<void> Function() start) async {
    final known = target.subtitles.map((file) => file.path).nonNulls.toSet();
    Set<String> seen;
    try {
      seen = (await bazarr.history(target)).map((e) => e.identity).toSet();
    } catch (_) {
      seen = const {};
    }

    try {
      await start();
    } on BazarrException catch (error) {
      throw SubtitleDownloadException(error.message ?? error.error.name);
    }
    if (mounted) state = state.copyWith(phase: () => DownloadPhase.saving);

    String? savedPath;
    for (var attempt = 0; attempt < 45 && savedPath == null; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final fresh = await bazarr.reload(target);
        savedPath = fresh?.subtitles.map((s) => s.path).nonNulls.firstWhereOrNull((p) => !known.contains(p));
        if (savedPath == null && attempt.isEven) {
          final entry = (await bazarr.history(target))
              .firstWhereOrNull((e) => !seen.contains(e.identity) && e.path != null && e.action != 0);
          savedPath = entry?.path;
        }
      } catch (error) {
        _log.fine('Waiting on Bazarr failed: $error');
      }
    }
    if (savedPath == null) {
      throw const SubtitleDownloadException('Bazarr did not save a subtitle. The provider may be throttled, '
          'or nothing met its minimum score - search again, or pick one from the list.');
    }
    return savedPath;
  }

  /// Has Bazarr pick and download the best subtitle in the language being
  /// looked at, by its own scoring and profile - the one-tap way.
  Future<SubtitleDownload> letBazarrChoose() async {
    final language = state.language;
    final bazarr = ref.read(bazarrClientProvider);
    final lookup = await _lookup;
    final target = lookup.bazarr;
    final two = language == null ? null : _twoLetter(language);
    if (bazarr == null || target == null || two == null) {
      throw const SubtitleDownloadException('Bazarr is not connected');
    }
    state = state.copyWith(downloadingKey: () => bazarrChoiceKey, phase: () => DownloadPhase.fetching);
    try {
      final before = await _currentSubtitlePaths(lookup.item) ?? lookup.item.externalSubtitlePaths;
      final savedPath = await _bazarrSaves(
          bazarr, target, () => bazarr.searchAutomatically(target, two, hi: state.preferHearingImpaired == true));
      if (mounted) state = state.copyWith(phase: () => DownloadPhase.adding);
      await _refreshServerItem();
      final savedName = _baseName(savedPath);
      final overwritten = before.firstWhereOrNull((p) => _baseName(p) == savedName);
      final stream = await _awaitNewStream(overwritten == null ? before : before.difference({overwritten}), attempts: 10);
      return SubtitleDownload(stream: stream, savedPath: savedPath);
    } finally {
      if (mounted) state = state.copyWith(downloadingKey: () => null, phase: () => null);
    }
  }

  static const bazarrChoiceKey = 'bazarr-choice';

  Future<void> _refreshServerItem() async {
    if (ref.read(userProvider)?.policy?.isAdministrator != true) return;
    await ref.read(jellyApiProvider).api.itemsItemIdRefreshPost(
          itemId: itemId,
          metadataRefreshMode: dto.ItemsItemIdRefreshPostMetadataRefreshMode.$default,
          imageRefreshMode: dto.ItemsItemIdRefreshPostImageRefreshMode.$default,
        );
  }

  /// The external subtitle files the server lists for the item right now.
  Future<Set<String>?> _currentSubtitlePaths(SubtitleItem item) async {
    final streams = await _subtitleStreams();
    if (streams == null) return null;
    return {
      for (final s in streams)
        if (s.isExternal == true && s.path != null) s.path!,
    };
  }

  Future<List<dto.MediaStream>?> _subtitleStreams() async {
    try {
      final response = await ref.read(jellyApiProvider).api.itemsItemIdGet(
            itemId: itemId,
            userId: ref.read(userProvider)?.id,
          );
      final sources = response.body?.mediaSources ?? const [];
      final source = sources.firstWhereOrNull((s) => s.id == mediaSourceId) ?? sources.firstOrNull;
      return (source?.mediaStreams ?? response.body?.mediaStreams ?? const [])
          .where((s) => s.type == dto.MediaStreamType.subtitle)
          .toList();
    } catch (error) {
      _log.fine('Listing subtitles failed: $error');
      return null;
    }
  }

  Future<dto.MediaStream?> _awaitNewStream(Set<String> before, {required int attempts}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      await Future<void>.delayed(Duration(milliseconds: attempt == 0 ? 800 : 1500));
      final streams = await _subtitleStreams();
      final added = streams?.firstWhereOrNull((s) => s.isExternal == true && s.path != null && !before.contains(s.path));
      if (added != null) return added;
    }
    return null;
  }

  static String _describe(int status, Object? error) => switch (status) {
        401 || 403 => 'The server does not allow this account to download subtitles.',
        404 => 'The subtitle is no longer available from its provider.',
        _ => 'The server could not download it ($status${error == null ? '' : ': $error'}).',
      };
}

extension BazarrCredentialsLabel on BazarrCredentialsModel {
  String get host {
    final uri = Uri.tryParse(serverUrl.contains('://') ? serverUrl : 'http://$serverUrl');
    return uri?.host.isNotEmpty == true ? uri!.host : serverUrl;
  }
}

String _baseName(String path) {
  final separator = path.lastIndexOf(RegExp(r'[\\/]'));
  return separator == -1 ? path : path.substring(separator + 1);
}

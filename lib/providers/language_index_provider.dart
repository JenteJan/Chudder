import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

final _log = Logger('LanguageIndex');

/// The languages of one film, episode or show: the one it was made in (its
/// first audio track, as the language preferences read it), and every audio
/// and subtitle language it has.
class LanguageEntry {
  const LanguageEntry({this.original = '', this.audio = const {}, this.subtitles = const {}});

  final String original;
  final Set<String> audio;
  final Set<String> subtitles;

  List<Object> toJson() => [original, audio.toList(), subtitles.toList()];

  static LanguageEntry fromJson(Object? json) {
    if (json is! List || json.length < 3) return const LanguageEntry();
    Set<String> codes(Object? list) => list is List ? list.map((code) => '$code').toSet() : const {};
    return LanguageEntry(original: '${json[0]}', audio: codes(json[1]), subtitles: codes(json[2]));
  }

  static LanguageEntry fromStreams(List<MediaStream> streams) {
    String code(String? language) {
      final normalized = normalizeLanguage(language ?? '');
      return normalized == 'und' || normalized == 'mul' ? '' : normalized;
    }

    final audio = streams.where((stream) => stream.type == MediaStreamType.audio).toList();
    final subtitles = streams.where((stream) => stream.type == MediaStreamType.subtitle);
    final first = audio.firstWhereOrNull((stream) => stream.isExternal != true) ?? audio.firstOrNull;
    return LanguageEntry(
      original: code(first?.language),
      audio: audio.map((stream) => code(stream.language)).where((code) => code.isNotEmpty).toSet(),
      subtitles: subtitles.map((stream) => code(stream.language)).where((code) => code.isNotEmpty).toSet(),
    );
  }
}

/// Which languages to keep: each a set of codes, any of which will do; an
/// empty set asks nothing. All three must hold.
class LanguageQuery {
  const LanguageQuery({this.original = const {}, this.audio = const {}, this.subtitles = const {}});

  final Set<String> original;
  final Set<String> audio;
  final Set<String> subtitles;

  bool get isEmpty => original.isEmpty && audio.isEmpty && subtitles.isEmpty;

  bool matches(LanguageEntry? entry) {
    if (isEmpty) return true;
    if (entry == null) return false;
    if (original.isNotEmpty && !original.contains(entry.original)) return false;
    if (audio.isNotEmpty && !audio.any(entry.audio.contains)) return false;
    if (subtitles.isNotEmpty && !subtitles.any(entry.subtitles.contains)) return false;
    return true;
  }
}

/// A title the filters need languages for: a show's are sampled from an
/// episode, anything else is read itself.
typedef LanguageWanted = ({String id, bool series});

/// The languages of what the library's language filters have needed so far:
/// the server has no way to ask for them, so they are read once and kept.
///
/// Only what a library on screen asks for is read, never the whole server:
/// films by id, a hundred to a request, and a show from one of its episodes
/// (the first), read as it was made. Episodes the server says changed later
/// add their languages to their show, so a show grows more complete as its
/// episodes come and go.
class LanguageIndex {
  LanguageIndex({this.items = const {}, this.episodes = const {}, this.series = const {}, this.builtAt});

  /// Films, videos and episodes, by id. A title without languages has an
  /// empty entry, so it is not asked for again.
  final Map<String, LanguageEntry> items;

  /// Each episode's show, to put a show together from its episodes.
  final Map<String, String> episodes;

  /// The shows looked at, including any without an episode to read.
  final Set<String> series;

  /// From when changes are asked for; null until anything was read.
  final DateTime? builtAt;

  static final empty = LanguageIndex();

  bool knows(LanguageWanted wanted) => wanted.series ? series.contains(wanted.id) : items.containsKey(wanted.id);

  /// What is known of [id]; null when it was never read.
  LanguageEntry? entryFor(String id) =>
      items[id] ?? _series[id] ?? (series.contains(id) ? const LanguageEntry() : null);

  late final Map<String, LanguageEntry> _series = () {
    final byShow = <String, List<LanguageEntry>>{};
    episodes.forEach((episodeId, seriesId) {
      final entry = items[episodeId];
      if (entry != null) (byShow[seriesId] ??= []).add(entry);
    });
    return byShow.map((seriesId, list) {
      final originals = <String, int>{};
      for (final entry in list) {
        if (entry.original.isNotEmpty) originals[entry.original] = (originals[entry.original] ?? 0) + 1;
      }
      final original = originals.entries.sorted((a, b) => b.value.compareTo(a.value)).firstOrNull?.key ?? '';
      return MapEntry(
        seriesId,
        LanguageEntry(
          original: original,
          audio: {for (final entry in list) ...entry.audio},
          subtitles: {for (final entry in list) ...entry.subtitles},
        ),
      );
    });
  }();

  /// How many of [ids] - films and shows, the titles a library lists - have
  /// each language, for the filters' lists.
  ({Map<String, int> original, Map<String, int> audio, Map<String, int> subtitles}) countsFor(Iterable<String> ids) {
    final original = <String, int>{}, audio = <String, int>{}, subtitles = <String, int>{};
    for (final id in ids) {
      final entry = entryFor(id);
      if (entry == null) continue;
      if (entry.original.isNotEmpty) original[entry.original] = (original[entry.original] ?? 0) + 1;
      for (final code in entry.audio) {
        audio[code] = (audio[code] ?? 0) + 1;
      }
      for (final code in entry.subtitles) {
        subtitles[code] = (subtitles[code] ?? 0) + 1;
      }
    }
    return (original: original, audio: audio, subtitles: subtitles);
  }

  LanguageIndex copyWith({
    Map<String, LanguageEntry>? items,
    Map<String, String>? episodes,
    Set<String>? series,
    DateTime? builtAt,
  }) =>
      LanguageIndex(
        items: items ?? this.items,
        episodes: episodes ?? this.episodes,
        series: series ?? this.series,
        builtAt: builtAt ?? this.builtAt,
      );

  String encode() => jsonEncode({
        'v': 2,
        'builtAt': builtAt?.toIso8601String(),
        'items': {for (final entry in items.entries) entry.key: entry.value.toJson()},
        'episodes': episodes,
        'series': series.toList(),
      });

  static LanguageIndex decode(String source) {
    try {
      final map = jsonDecode(source) as Map;
      if (map['v'] != 2) return empty;
      return LanguageIndex(
        builtAt: DateTime.tryParse('${map['builtAt']}'),
        items: {
          for (final entry in (map['items'] as Map).entries) '${entry.key}': LanguageEntry.fromJson(entry.value),
        },
        episodes: {for (final entry in (map['episodes'] as Map).entries) '${entry.key}': '${entry.value}'},
        series: {for (final id in map['series'] as List) '$id'},
      );
    } catch (_) {
      return empty;
    }
  }
}

final languageIndexProvider = StateNotifierProvider<LanguageIndexNotifier, LanguageIndex>((ref) {
  return LanguageIndexNotifier(ref);
});

/// Runs [work] over [items], at most [width] at a time.
Future<void> _pooled<T>(List<T> items, int width, Future<void> Function(T item) work) async {
  var next = 0;
  Future<void> lane() async {
    while (next < items.length) {
      await work(items[next++]);
    }
  }

  await Future.wait([for (var i = 0; i < width && i < items.length; i++) lane()]);
}

class LanguageIndexNotifier extends StateNotifier<LanguageIndex> {
  LanguageIndexNotifier(this.ref) : super(LanguageIndex.empty);

  final Ref ref;

  /// Films per request, asked for by id: a film's streams run to a few
  /// kilobytes, more with many subtitles.
  static const batchSize = 100;

  /// Requests in flight at once. Enough to hide the round trips, few enough
  /// that a small server (a Raspberry Pi, a NAS) keeps serving playback.
  static const width = 4;

  /// Changes are not asked for more often than this.
  static const minInterval = Duration(minutes: 5);

  /// Changed films and episodes per request.
  static const changesPageSize = 200;

  Future<void>? _loading;
  Future<void>? _changes;
  Future<void> _reads = Future.value();
  String? _loadedFor;
  DateTime? _askedChanges;

  Future<File?> _file(String userId) async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}language_index_$userId.json');
  }

  /// What this device kept from before, read once per account.
  Future<String?> _load() async {
    final userId = ref.read(userProvider)?.id;
    if (userId == null) return null;
    if (_loadedFor != userId) {
      await (_loading ??= () async {
        final file = await _file(userId);
        final stored = file != null && await file.exists() ? LanguageIndex.decode(await file.readAsString()) : null;
        if (mounted) state = stored ?? LanguageIndex.empty;
        _loadedFor = userId;
      }()
          .whenComplete(() => _loading = null));
    }
    return userId;
  }

  Future<void> _keep(String userId) async {
    try {
      await (await _file(userId))?.writeAsString(state.encode());
    } catch (error) {
      _log.info('language index: not kept: $error');
    }
  }

  /// Reads the languages of whatever of [wanted] is not known yet, then
  /// what changed on the server since the last look. Reads queue behind one
  /// another, so asking twice for the same library reads it once.
  Future<void> ensure(Iterable<LanguageWanted> wanted) {
    final list = wanted.toList();
    return _reads = _reads.then((_) => _ensure(list)).catchError((Object error) {
      _log.info('language index: read stopped: $error');
    });
  }

  Future<void> _ensure(List<LanguageWanted> wanted) async {
    final userId = await _load();
    if (userId == null || !mounted) return;
    final startedAt = DateTime.now().toUtc();
    final missing = wanted.where((item) => !state.knows(item)).toList();
    if (missing.isNotEmpty) {
      final watch = Stopwatch()..start();
      final films = missing.where((item) => !item.series).map((item) => item.id).toList();
      final shows = missing.where((item) => item.series).map((item) => item.id).toList();
      final batches = [for (var i = 0; i < films.length; i += batchSize) films.skip(i).take(batchSize).toList()];
      // Every batch and show is a lane's next job: films and shows share the
      // four lanes, and the filters fill as each one lands.
      final jobs = <Future<void> Function()>[
        for (final batch in batches) () => _readFilms(batch),
        for (final show in shows) () => _readShow(show),
      ];
      await _pooled(jobs, width, (job) => job());
      if (!mounted) return;
      if (state.builtAt == null) state = state.copyWith(builtAt: startedAt);
      _log.info('language index: read ${films.length} titles and ${shows.length} shows '
          'in ${watch.elapsedMilliseconds}ms');
      await _keep(userId);
    }
    await refresh();
  }

  Future<void> _readFilms(List<String> ids) async {
    final response = await ref.read(jellyApiProvider).api.usersUserIdItemsGet(
          userId: ref.read(userProvider)?.id,
          ids: ids,
          fields: const [ItemFields.mediastreams],
          enableImages: false,
          enableUserData: false,
          enableTotalRecordCount: false,
        );
    if (!response.isSuccessful || !mounted) return;
    final items = Map<String, LanguageEntry>.of(state.items);
    // Asked for and not returned (a folder, gone since): known to have none.
    for (final id in ids) {
      items[id] = const LanguageEntry();
    }
    for (final item in response.body?.items ?? const <BaseItemDto>[]) {
      final id = item.id;
      if (id != null) items[id] = LanguageEntry.fromStreams(item.mediaStreams ?? const []);
    }
    state = state.copyWith(items: items);
  }

  /// A show from its first episode with a file.
  Future<void> _readShow(String seriesId) async {
    final response = await ref.read(jellyApiProvider).api.usersUserIdItemsGet(
          userId: ref.read(userProvider)?.id,
          parentId: seriesId,
          recursive: true,
          includeItemTypes: const [BaseItemKind.episode],
          isMissing: false,
          sortBy: const [ItemSortBy.parentindexnumber, ItemSortBy.indexnumber],
          limit: 1,
          fields: const [ItemFields.mediastreams],
          enableImages: false,
          enableUserData: false,
          enableTotalRecordCount: false,
        );
    if (!response.isSuccessful || !mounted) return;
    final episode = response.body?.items?.firstOrNull;
    final id = episode?.id;
    state = state.copyWith(
      series: {...state.series, seriesId},
      items: id == null ? null : {...state.items, id: LanguageEntry.fromStreams(episode?.mediaStreams ?? const [])},
      episodes: id == null ? null : {...state.episodes, id: seriesId},
    );
  }

  /// Takes in what changed on the server since the last look - only for
  /// titles already read and shows already looked at; anything else is read
  /// when a library asks for it. Not more often than [minInterval].
  Future<void> refresh({bool force = false}) => _changes ??= _refresh(force: force).whenComplete(() => _changes = null);

  Future<void> _refresh({required bool force}) async {
    final userId = await _load();
    final since = state.builtAt;
    if (userId == null || since == null || !mounted) return;
    final asked = _askedChanges;
    if (!force && asked != null && DateTime.now().difference(asked) < minInterval) return;
    _askedChanges = DateTime.now();
    final startedAt = DateTime.now().toUtc();
    var changed = 0;
    try {
      for (var start = 0;; start += changesPageSize) {
        final response = await ref.read(jellyApiProvider).api.usersUserIdItemsGet(
              userId: userId,
              recursive: true,
              includeItemTypes: const [
                BaseItemKind.movie,
                BaseItemKind.episode,
                BaseItemKind.video,
                BaseItemKind.musicvideo,
              ],
              fields: const [ItemFields.mediastreams],
              minDateLastSaved: since,
              enableImages: false,
              enableUserData: false,
              enableTotalRecordCount: false,
              startIndex: start,
              limit: changesPageSize,
            );
        if (!response.isSuccessful || !mounted) return;
        final page = response.body?.items ?? const <BaseItemDto>[];
        final items = Map<String, LanguageEntry>.of(state.items);
        final episodes = Map<String, String>.of(state.episodes);
        for (final item in page) {
          final id = item.id;
          final seriesId = item.seriesId;
          if (id == null) continue;
          final ofKnownShow = item.type == BaseItemKind.episode && seriesId != null && state.series.contains(seriesId);
          if (!ofKnownShow && !items.containsKey(id)) continue;
          items[id] = LanguageEntry.fromStreams(item.mediaStreams ?? const []);
          if (ofKnownShow) episodes[id] = seriesId;
          changed++;
        }
        state = state.copyWith(items: items, episodes: episodes);
        if (page.length < changesPageSize) break;
      }
    } catch (error) {
      _log.info('language index: changes not read: $error');
      return;
    }
    if (!mounted) return;
    state = state.copyWith(builtAt: startedAt);
    if (changed > 0) _log.info('language index: $changed changed since $since');
    await _keep(userId);
  }
}

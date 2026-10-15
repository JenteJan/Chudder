import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// The languages of everything in the library, for the library's language
/// filters: the server has no way to ask for them.
///
/// Films and episodes are read with their streams; a show is what its
/// episodes have together, made in the language most of its episodes were.
class LanguageIndex {
  LanguageIndex({this.items = const {}, this.episodes = const {}, this.builtAt, this.complete = false});

  /// Films, videos and episodes, by id.
  final Map<String, LanguageEntry> items;

  /// Each episode's show, to put a show together again when one changes.
  final Map<String, String> episodes;

  /// When the server was last asked; the next refresh asks what changed since.
  final DateTime? builtAt;

  /// Whether a full read has finished, so a missing entry means "none".
  final bool complete;

  static final empty = LanguageIndex();

  /// A show's entry from its episodes'.
  LanguageEntry seriesEntry(String seriesId) => _series[seriesId] ?? const LanguageEntry();

  LanguageEntry? entryFor(String id) => items[id] ?? _series[id];

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

  /// How many films and shows have each language, for the filters' lists.
  /// Worked out once per index.
  late final ({Map<String, int> original, Map<String, int> audio, Map<String, int> subtitles}) counts = _count();

  ({Map<String, int> original, Map<String, int> audio, Map<String, int> subtitles}) _count() {
    final original = <String, int>{}, audio = <String, int>{}, subtitles = <String, int>{};
    void count(LanguageEntry entry) {
      if (entry.original.isNotEmpty) original[entry.original] = (original[entry.original] ?? 0) + 1;
      for (final code in entry.audio) {
        audio[code] = (audio[code] ?? 0) + 1;
      }
      for (final code in entry.subtitles) {
        subtitles[code] = (subtitles[code] ?? 0) + 1;
      }
    }

    items.forEach((id, entry) {
      if (!episodes.containsKey(id)) count(entry);
    });
    _series.values.forEach(count);
    return (original: original, audio: audio, subtitles: subtitles);
  }

  String encode() => jsonEncode({
        'v': 1,
        'builtAt': builtAt?.toIso8601String(),
        'complete': complete,
        'items': {for (final entry in items.entries) entry.key: entry.value.toJson()},
        'episodes': episodes,
      });

  static LanguageIndex decode(String source) {
    try {
      final map = jsonDecode(source) as Map;
      if (map['v'] != 1) return empty;
      return LanguageIndex(
        builtAt: DateTime.tryParse('${map['builtAt']}'),
        complete: map['complete'] == true,
        items: {
          for (final entry in (map['items'] as Map).entries) '${entry.key}': LanguageEntry.fromJson(entry.value),
        },
        episodes: {for (final entry in (map['episodes'] as Map).entries) '${entry.key}': '${entry.value}'},
      );
    } catch (_) {
      return empty;
    }
  }
}

final languageIndexProvider = StateNotifierProvider<LanguageIndexNotifier, LanguageIndex>((ref) {
  return LanguageIndexNotifier(ref);
});

class LanguageIndexNotifier extends StateNotifier<LanguageIndex> {
  LanguageIndexNotifier(this.ref) : super(LanguageIndex.empty);

  final Ref ref;

  /// Items per request: a page with streams runs to a few hundred kilobytes.
  static const pageSize = 300;

  /// A refresh is not asked for more often than this.
  static const minInterval = Duration(minutes: 5);

  Future<void>? _running;
  String? _loadedFor;

  /// Whether a read from the server is under way.
  bool get refreshing => _running != null;

  Future<File?> _file(String userId) async {
    if (kIsWeb) return null;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}language_index_$userId.json');
  }

  /// Reads what this device knew, then asks the server what changed since.
  /// Safe to call often: one read at a time, and not again within a while.
  Future<void> refresh({bool force = false}) {
    return _running ??= _refresh(force: force).whenComplete(() => _running = null);
  }

  Future<void> _refresh({required bool force}) async {
    final userId = ref.read(userProvider)?.id;
    if (userId == null) return;
    final file = await _file(userId);
    if (_loadedFor != userId) {
      _loadedFor = userId;
      final stored = file != null && await file.exists() ? LanguageIndex.decode(await file.readAsString()) : null;
      if (mounted) state = stored ?? LanguageIndex.empty;
    }
    final since = state.complete ? state.builtAt : null;
    if (!force && since != null && DateTime.now().difference(since) < minInterval) return;

    final startedAt = DateTime.now().toUtc();
    final items = Map<String, LanguageEntry>.of(state.items);
    final episodes = Map<String, String>.of(state.episodes);
    final watch = Stopwatch()..start();
    var read = 0;
    try {
      for (var start = 0;; start += pageSize) {
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
              limit: pageSize,
            );
        final page = response.body?.items ?? const <BaseItemDto>[];
        for (final item in page) {
          final id = item.id;
          if (id == null) continue;
          items[id] = LanguageEntry.fromStreams(item.mediaStreams ?? const []);
          final seriesId = item.seriesId;
          if (item.type == BaseItemKind.episode && seriesId != null) episodes[id] = seriesId;
        }
        read += page.length;
        if (!mounted) return;
        // Shown as it comes in: the filters fill while the rest is read.
        state = LanguageIndex(items: items, episodes: episodes, builtAt: state.builtAt, complete: state.complete);
        if (page.length < pageSize) break;
      }
    } catch (error) {
      _log.info('language index: stopped after $read items: $error');
      // What was read stays; the rest is asked for on the next refresh.
      return;
    }
    if (!mounted) return;
    state = LanguageIndex(items: items, episodes: episodes, builtAt: startedAt, complete: true);
    _log.info('language index: ${since == null ? 'built' : 'refreshed'} with $read items '
        'in ${watch.elapsedMilliseconds}ms (${items.length} known)');
    try {
      await file?.writeAsString(state.encode());
    } catch (error) {
      _log.info('language index: not kept: $error');
    }
  }
}

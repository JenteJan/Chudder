import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/util/fuzzy_match.dart';

/// Every title in the library, by name, so a search can survive a typo.
///
/// The server's search is a substring filter — "inglorious" matches nothing at
/// all, so there is nothing to come back and re-rank. The only way to catch
/// that is to hold the names here and compare against them.
///
/// Names only: the id is enough to fetch the real item once there is something
/// worth showing, so an index of a few thousand titles costs a list of short
/// strings rather than a library's worth of models.
class LibraryIndex {
  const LibraryIndex(this.entries);

  final List<LibraryIndexEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// The ids of the closest titles, best first. Empty when nothing is close —
  /// which is the common answer, and the right one: results from the library
  /// sit above results from anywhere else, so a bad guess here outranks a good
  /// match from Jellyseerr.
  List<String> bestMatches(String query, {int limit = 10}) {
    final scored = <({String id, double score})>[];
    for (final entry in entries) {
      final score = fuzzyScore(entry.name, query);
      if (score > 0) scored.add((id: entry.id, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((hit) => hit.id).toList(growable: false);
  }
}

class LibraryIndexEntry {
  const LibraryIndexEntry({required this.id, required this.name});

  final String id;
  final String name;
}

/// Built the first time a search comes back empty, not at startup: most
/// searches never need it, and it is one large request.
///
/// Kept for the session. A title added while the app is open will not be found
/// by a misspelling until the next launch, which is a fair trade for not
/// re-reading the library on every miss.
final libraryIndexProvider = FutureProvider<LibraryIndex>((ref) async {
  ref.keepAlive();

  final api = ref.read(jellyApiProvider);
  final response = await api.itemsGet(
    recursive: true,
    // The things you look up by title. People and studios are found by the
    // server well enough, and episodes would swamp the rest.
    includeItemTypes: const [
      BaseItemKind.movie,
      BaseItemKind.series,
      BaseItemKind.boxset,
      BaseItemKind.book,
    ],
    // Enough for a large library, small enough that a runaway one cannot pull
    // the whole server into memory.
    limit: 10000,
    fields: const [],
    enableImages: false,
    enableUserData: false,
    enableTotalRecordCount: false,
    sortBy: const [ItemSortBy.sortname],
  );

  final entries = <LibraryIndexEntry>[];
  for (final item in response.body?.items ?? const []) {
    if (item.name.trim().isEmpty) continue;
    entries.add(LibraryIndexEntry(id: item.id, name: item.name));
  }
  return LibraryIndex(entries);
});

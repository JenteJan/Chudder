import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/recommended_model.dart';

/// The one row of things to carry on with, newest first: what you are in the
/// middle of and what you would start next, whether or not you finished the
/// last of it.
///
/// The server does the harder half. Asked with `enableResumable`, Next Up
/// answers with one episode per show - the one you are part-way through, or
/// the one after the last you finished - so a show is answered for once and
/// only once. What is left is everything Next Up knows nothing about, films
/// above all, which Resume carries.
List<ItemBaseModel> combineContinueRow(List<ItemBaseModel> nextUp, List<ItemBaseModel> resume) {
  final shows = nextUp.whereType<EpisodeModel>().map((episode) => episode.parentId).nonNulls.toSet();
  final taken = nextUp.map((item) => item.id).toSet();

  final rest = resume
      .where((item) => !taken.contains(item.id) && !(item is EpisodeModel && shows.contains(item.parentId)))
      .toList();

  final played = {..._playedAt(nextUp), ..._playedAt(rest)};
  return [...nextUp, ...rest]..sort((a, b) => (played[b.id] ?? DateTime(0)).compareTo(played[a.id] ?? DateTime(0)));
}

/// When each item of one server-ordered list was last played, filled in for
/// the ones the server leaves blank.
///
/// Both lists arrive newest first, but a date only comes with an item that has
/// actually been played: the episode after the one you finished has none at
/// all. Each of those takes the date of the first dated item below it and a
/// moment more, which leaves it exactly where the server put it and still lets
/// the other list slot in around it. A list with no dates anywhere keeps its
/// own order and sits under everything that has one.
Map<String, DateTime> _playedAt(List<ItemBaseModel> items) {
  final dates = <String, DateTime>{};
  var below = DateTime.fromMillisecondsSinceEpoch(0);
  for (var index = items.length - 1; index >= 0; index--) {
    final item = items[index];
    below = item.userData.lastPlayed ?? below.add(const Duration(microseconds: 1));
    dates[item.id] = below;
  }
  return dates;
}

/// Next up as its own row, beside a Continue watching row.
///
/// Next up is asked for with `enableResumable` so the combined row can be built
/// out of it, which also puts the episodes you are part-way through in it. Next
/// to their own row those are there twice.
List<ItemBaseModel> nextUpBesideResume(List<ItemBaseModel> nextUp, List<ItemBaseModel> resume) {
  final resumed = resume.map((item) => item.id).toSet();
  return nextUp.where((item) => !resumed.contains(item.id)).toList();
}

/// A library's recommendation rows with its Continue and Next up rows as the
/// settings ask: one row in place of the first of them when [combine], or Next
/// up without what Continue already has.
List<RecommendedModel> libraryContinueRows(List<RecommendedModel> rows, {required bool combine}) {
  final resume = rows.where((row) => row.name is Continue).expand((row) => row.posters).toList();
  final nextUp = rows.where((row) => row.name is NextUp).expand((row) => row.posters).toList();
  final result = <RecommendedModel>[];
  var placed = false;
  for (final row in rows) {
    final isContinue = row.name is Continue || row.name is NextUp;
    if (!isContinue) {
      result.add(row);
    } else if (!combine) {
      result.add(row.name is NextUp ? row.copyWith(posters: nextUpBesideResume(row.posters, resume)) : row);
    } else if (!placed) {
      placed = true;
      result.add(RecommendedModel(name: const Continue(), posters: combineContinueRow(nextUp, resume)));
    }
  }
  return result..removeWhere((row) => row.posters.isEmpty);
}

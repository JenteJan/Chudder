import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/util/subtitle_track_selection.dart';

/// Where [WatchedLanguages] keeps its tally. Device only.
const watchedLanguagesKey = 'watchedLanguages';

/// The languages of what has been played here, tallied, so a language
/// picker with hundreds of choices can put the few that matter at the top.
///
/// Cheap on purpose: one small map in the preferences, touched once per item
/// played, read from memory after the first time.
class WatchedLanguages {
  WatchedLanguages(this.ref);

  final Ref ref;

  /// Languages kept at most; the least likely go first.
  static const maxLanguages = 40;

  /// A play counts half as much after this long.
  static const halfLife = Duration(days: 60);

  Map<String, ({double score, int day})>? _tally;
  final Set<String> _counted = {};

  /// Read again after the stored copy was replaced, by an import.
  void reload() => _tally = null;

  static int _today() => DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  Map<String, ({double score, int day})> get _read {
    final tally = _tally;
    if (tally != null) return tally;
    final loaded = <String, ({double score, int day})>{};
    try {
      final stored = ref.read(sharedPreferencesProvider).getString(watchedLanguagesKey);
      if (stored != null) {
        (jsonDecode(stored) as Map).forEach((code, value) {
          if (value is List && value.length == 2 && value[0] is num && value[1] is num) {
            loaded['$code'] = (score: (value[0] as num).toDouble(), day: (value[1] as num).toInt());
          }
        });
      }
    } catch (_) {}
    return _tally = loaded;
  }

  /// [score] as it stands today, faded by how long ago it was last added to.
  static double _now(({double score, int day}) entry, int today) =>
      entry.score * math.pow(0.5, (today - entry.day) / halfLife.inDays);

  /// Adds what [itemId] plays in: the audio playing counts most, the other
  /// dubs it has a little, the subtitles shown a fair bit. Once per item
  /// while the app is open, so watching one film in parts counts once.
  void noteItem(String itemId, MediaStreamsModel streams) {
    if (!_counted.add(itemId)) return;
    final weights = <String, double>{};
    void add(String? language, double weight) {
      final code = normalizeLanguage(language ?? '');
      if (code.isEmpty || code == 'und' || code == 'mul') return;
      weights[code] = math.max(weights[code] ?? 0, weight);
    }

    for (final audio in streams.audioStreams) {
      add(audio.language, 1);
    }
    final audio = streams.currentAudioStream;
    if (audio != null && audio.index != -1) add(audio.language, 3);
    final sub = streams.currentSubStream;
    if (sub != null && sub.index != -1) add(sub.language, 2);
    note(weights);
  }

  /// Adds [weights] to the tally and keeps it.
  void note(Map<String, double> weights) {
    if (weights.isEmpty) return;
    final today = _today();
    final tally = Map.of(_read);
    weights.forEach((code, weight) {
      final before = tally[code];
      tally[code] = (score: (before == null ? 0 : _now(before, today)) + weight, day: today);
    });
    if (tally.length > maxLanguages) {
      final keep = (tally.entries.toList()..sort((a, b) => _now(b.value, today).compareTo(_now(a.value, today))))
          .take(maxLanguages);
      tally
        ..clear()
        ..addEntries(keep);
    }
    _tally = tally;
    try {
      ref.read(sharedPreferencesProvider).setString(
            watchedLanguagesKey,
            jsonEncode({
              for (final entry in tally.entries)
                entry.key: [double.parse(entry.value.score.toStringAsFixed(2)), entry.value.day],
            }),
          );
    } catch (_) {}
  }

  /// The languages most likely to be wanted, most likely first, as
  /// normalized codes.
  List<String> likely({int max = 6}) {
    final today = _today();
    final entries = _read.entries.toList()..sort((a, b) => _now(b.value, today).compareTo(_now(a.value, today)));
    return entries.take(max).map((entry) => entry.key).toList();
  }
}

final watchedLanguagesProvider = Provider<WatchedLanguages>((ref) {
  final languages = WatchedLanguages(ref);
  // Every item that starts playing, whichever way it was started.
  ref.listen(playBackModel, (_, model) {
    final streams = model?.mediaStreams;
    if (model != null && streams != null) languages.noteItem(model.item.id, streams);
  }, fireImmediately: true);
  return languages;
});

import 'package:chudder/models/items/media_streams_model.dart';

/// Maps a subtitle stream the server listed onto something the player can
/// switch to.
///
/// The server lists two kinds of subtitle in one list: tracks muxed into the
/// media file, and subtitle files sitting next to it. A player only counts the
/// first kind, so a position taken in the whole list lands on the wrong track
/// as soon as a file precedes it — and a file that was already loaded is
/// appended to the player's own list, where a stale position finds it again.
/// Here the two kinds are told apart before anything is counted.
class SubtitlePick {
  /// The track to select, counted among the container's own subtitle tracks,
  /// or null when there is none to select.
  final int? trackIndex;

  /// Whether the subtitle file should be loaded from the server instead.
  final bool loadFile;

  const SubtitlePick.track(int this.trackIndex) : loadFile = false;
  const SubtitlePick.file()
      : trackIndex = null,
        loadFile = true;
  const SubtitlePick.none()
      : trackIndex = null,
        loadFile = false;

  @override
  bool operator ==(Object other) =>
      other is SubtitlePick && other.trackIndex == trackIndex && other.loadFile == loadFile;

  @override
  int get hashCode => Object.hash(trackIndex, loadFile);

  @override
  String toString() => loadFile
      ? 'SubtitlePick.file()'
      : trackIndex == null
          ? 'SubtitlePick.none()'
          : 'SubtitlePick.track($trackIndex)';
}

/// The streams that live inside the media file, in the order the player sees
/// them. The 'Off' entry and the server's subtitle files are not tracks.
List<SubStreamModel> containerSubtitleStreams(Iterable<SubStreamModel>? streams) =>
    streams?.where((stream) => stream.index != SubStreamModel.no().index && !stream.isExternal).toList() ??
    const <SubStreamModel>[];

/// Where [wanted] sits among the container's own tracks, or -1 when it is not
/// one of them. Streams are matched on the server's stream index, which is
/// what the rest of the app identifies them by and what survives the item
/// being listed again.
int containerIndexOf(List<SubStreamModel> container, SubStreamModel wanted) =>
    wanted.isExternal ? -1 : container.indexWhere((stream) => stream.index == wanted.index);

/// What to switch to for [wanted], given how many subtitle tracks the player
/// found in the stream it opened.
///
/// [playerTrackCount] disagreeing with the container's own count means this is
/// not the file the server described — a transcode drops subtitle tracks — so
/// counting positions in it would land on the wrong one, and the subtitle is
/// fetched from the server instead. That is what the web client does, and it
/// is the only thing that works when the track is not in the stream at all.
SubtitlePick resolveSubtitlePick({
  required Iterable<SubStreamModel>? streams,
  required SubStreamModel wanted,
  required int playerTrackCount,
}) {
  final container = containerSubtitleStreams(streams);
  final containerIndex = containerIndexOf(container, wanted);
  if (containerIndex >= 0 && playerTrackCount == container.length) {
    return SubtitlePick.track(containerIndex);
  }
  final url = wanted.url;
  if (url != null && url.isNotEmpty) return const SubtitlePick.file();
  // Nothing to go on but the position: better a guess than a picture that
  // never changes.
  if (containerIndex >= 0 && containerIndex < playerTrackCount) {
    return SubtitlePick.track(containerIndex);
  }
  return const SubtitlePick.none();
}

/// What a player knows about one of the subtitle tracks it found.
class PlayerSubtitleTrack {
  final String language;
  final String title;

  const PlayerSubtitleTrack({this.language = '', this.title = ''});
}

/// The server and the player name the same language differently — the server
/// says `eng`, `swe`, `spa`, the player says `en-US`, `sv`, `es-419` — so both
/// are brought down to a two-letter code before they are compared. The
/// three-letter names are the ones a subtitle track is likely to carry;
/// anything unlisted is left as it is, where it still matches its own kind.
const _twoLetterLanguage = {
  'ara': 'ar',
  'ben': 'bn',
  'bul': 'bg',
  'cat': 'ca',
  'ces': 'cs',
  'cze': 'cs',
  'dan': 'da',
  'deu': 'de',
  'dut': 'nl',
  'ell': 'el',
  'eng': 'en',
  'est': 'et',
  'eus': 'eu',
  'baq': 'eu',
  'fas': 'fa',
  'per': 'fa',
  'fin': 'fi',
  'fra': 'fr',
  'fre': 'fr',
  'ger': 'de',
  'glg': 'gl',
  'gre': 'el',
  'heb': 'he',
  'hin': 'hi',
  'hrv': 'hr',
  'hun': 'hu',
  'ice': 'is',
  'ind': 'id',
  'isl': 'is',
  'ita': 'it',
  'jpn': 'ja',
  'kan': 'kn',
  'kor': 'ko',
  'lav': 'lv',
  'lit': 'lt',
  'mal': 'ml',
  'mar': 'mr',
  'may': 'ms',
  'msa': 'ms',
  'nld': 'nl',
  'nno': 'nn',
  'nob': 'nb',
  'nor': 'no',
  'pol': 'pl',
  'por': 'pt',
  'ron': 'ro',
  'rum': 'ro',
  'rus': 'ru',
  'slk': 'sk',
  'slo': 'sk',
  'slv': 'sl',
  'spa': 'es',
  'srp': 'sr',
  'swe': 'sv',
  'tam': 'ta',
  'tel': 'te',
  'tha': 'th',
  'tur': 'tr',
  'ukr': 'uk',
  'urd': 'ur',
  'vie': 'vi',
  'zho': 'zh',
  'chi': 'zh',
};

String _language(String value) {
  // 'en-US' and 'es-419' are the same languages as 'en' and 'es'; the region
  // is not something the server's list carries.
  final tag = _tag(value).split(RegExp('[-_]')).first;
  return _twoLetterLanguage[tag] ?? tag;
}

String _tag(String value) {
  final tag = value.trim().toLowerCase();
  return (tag == 'und' || tag == 'unknown' || tag == 'undefined') ? '' : tag;
}

String _key(String language, String title) => '${_language(language)}|${_tag(title)}';

/// Lines a stream up with the player's own track list on what both sides know
/// about a track — its language and its title — rather than trusting the two
/// lists to be in the same order.
///
/// Returns the track's position, or null when the metadata gives nothing to go
/// on and the caller should fall back to counting. Tracks sharing a language
/// and title are told apart by their order among their equals, which is the
/// answer counting gives when the two lists do agree.
int? matchSubtitleTrack({
  required List<SubStreamModel> container,
  required SubStreamModel wanted,
  required List<PlayerSubtitleTrack> tracks,
}) {
  final key = _key(wanted.language, wanted.title);
  if (key == _key('', '')) return null;

  final candidates = <int>[];
  for (var i = 0; i < tracks.length; i++) {
    if (_key(tracks[i].language, tracks[i].title) == key) candidates.add(i);
  }
  if (candidates.isEmpty) return null;
  if (candidates.length == 1) return candidates.first;

  var ordinal = 0;
  for (final stream in container) {
    if (stream.index == wanted.index) break;
    if (_key(stream.language, stream.title) == key) ordinal += 1;
  }
  return ordinal < candidates.length ? candidates[ordinal] : candidates.first;
}

/// The title a subtitle file gets when the app loads it into a player.
///
/// A loaded file is not one of the media file's own tracks, and it does not
/// reliably land after them: the one the server marks as default is loaded
/// while the player is still opening the stream, so it can take the first
/// place in the list and push the file's own tracks along. The tag is how
/// they are told apart afterwards.
const loadedSubtitlePrefix = 'chudder-sub-';

/// The tag names the file as well as its number: a removal renumbers the
/// files that are left, and a file found by number alone would then be
/// another file's lines. [generation] tells a file rewritten under its own
/// name from the copy the player read before.
String loadedSubtitleTag(SubStreamModel stream, {int generation = 0}) {
  final file = stream.path ?? stream.url ?? '';
  return '$loadedSubtitlePrefix${stream.index}-${file.hashCode.toRadixString(36)}-$generation';
}

/// A player's track list without the subtitle files the app loaded into it.
List<T> withoutLoadedSubtitles<T>(Iterable<T> tracks, String? Function(T track) titleOf) =>
    tracks.where((track) => !(titleOf(track)?.startsWith(loadedSubtitlePrefix) ?? false)).toList();

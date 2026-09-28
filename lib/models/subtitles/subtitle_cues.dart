/// One line (or block of lines) of a text subtitle and when it shows.
class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;
}

/// A subtitle file's cues in time order, for drawing them in the app
/// instead of the player - which is how subtitles can be moved in time on a
/// player that cannot move them itself.
class SubtitleCueList {
  SubtitleCueList(List<SubtitleCue> cues) : cues = List.unmodifiable([...cues]..sort((a, b) => a.start.compareTo(b.start)));

  final List<SubtitleCue> cues;

  /// The text on screen at [time]: every cue that covers it, in file order.
  String textAt(Duration time) {
    // Cues are sorted by start; find the last one that has started and walk
    // back over the ones that may still be running.
    var low = 0;
    var high = cues.length - 1;
    var last = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (cues[mid].start <= time) {
        last = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (last == -1) return '';
    final showing = <String>[];
    // Overlapping cues are rare and short; a small window back is enough.
    for (var i = last; i >= 0 && i > last - 8; i--) {
      final cue = cues[i];
      if (cue.end > time) showing.insert(0, cue.text);
    }
    return showing.join('\n');
  }

  /// Reads SubRip, WebVTT or ASS/SSA. Formatting tags are dropped: the app
  /// draws the text in the viewer's own subtitle style.
  factory SubtitleCueList.parse(String text) {
    if (RegExp(r'^\[Events\]', multiLine: true).hasMatch(text)) return SubtitleCueList._parseAss(text);
    final cues = <SubtitleCue>[];
    final blocks = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n\s*\n'));
    final timing = RegExp(r'((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[,.]\d{1,3})');
    for (final block in blocks) {
      final lines = block.split('\n');
      final at = lines.indexWhere((l) => timing.hasMatch(l));
      if (at == -1) continue;
      final m = timing.firstMatch(lines[at])!;
      final body = lines
          .skip(at + 1)
          .map((l) => l.replaceAll(RegExp(r'<[^>]*>|\{\\[^}]*\}'), '').trim())
          .where((l) => l.isNotEmpty)
          .join('\n');
      if (body.isEmpty) continue;
      cues.add(SubtitleCue(_parse(m[1]!), _parse(m[2]!), body));
    }
    return SubtitleCueList(cues);
  }

  /// The dialogue of an ASS/SSA file - what a download keeps of an ASS
  /// track, where the server would have handed out SubRip.
  factory SubtitleCueList._parseAss(String text) {
    final cues = <SubtitleCue>[];
    var start = 1, end = 2, body = 9;
    for (final raw in text.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimLeft();
      if (line.startsWith('Format:')) {
        final fields = line.substring(7).split(',').map((f) => f.trim().toLowerCase()).toList();
        if (fields.contains('start') && fields.contains('end') && fields.contains('text')) {
          start = fields.indexOf('start');
          end = fields.indexOf('end');
          body = fields.indexOf('text');
        }
        continue;
      }
      if (!line.startsWith('Dialogue:')) continue;
      final fields = line.substring(9).split(',');
      if (fields.length <= body) continue;
      final words = fields
          .skip(body)
          .join(',')
          .replaceAll(RegExp(r'\{[^}]*\}'), '')
          .replaceAll(RegExp(r'\\[Nn]'), '\n')
          .replaceAll(r'\h', ' ')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .join('\n');
      if (words.isEmpty) continue;
      try {
        cues.add(SubtitleCue(_parse(fields[start].trim()), _parse(fields[end].trim()), words));
      } on FormatException {
        continue;
      }
    }
    return SubtitleCueList(cues);
  }

  static Duration _parse(String value) {
    final parts = value.replaceAll(',', '.').split(':');
    final seconds = parts.removeLast().split('.');
    final minutes = int.parse(parts.removeLast());
    final hours = parts.isEmpty ? 0 : int.parse(parts.last);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: int.parse(seconds[0]),
      milliseconds: int.parse((seconds.length > 1 ? seconds[1] : '0').padRight(3, '0').substring(0, 3)),
    );
  }
}

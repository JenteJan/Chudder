/// Edits to a text subtitle file, done in the app so they work without
/// Bazarr: move every line in time, rescale it from one frame rate to
/// another, or strip the text written for the hard of hearing.
///
/// SubRip, WebVTT and ASS/SSA are understood; anything else is returned
/// unchanged. Only times and dialogue text are touched - styles, headers and
/// cue settings stay exactly as they were.
enum SubtitleTextFormat { srt, vtt, ass }

SubtitleTextFormat? subtitleTextFormatOf(String? codecOrExtension) =>
    switch (codecOrExtension?.toLowerCase().replaceFirst('.', '')) {
      'srt' || 'subrip' => SubtitleTextFormat.srt,
      'vtt' || 'webvtt' => SubtitleTextFormat.vtt,
      'ass' || 'ssa' => SubtitleTextFormat.ass,
      _ => null,
    };

/// Moves every cue by [offset]; positive shows them later. A cue pushed
/// before the start is clamped to zero rather than dropped.
String shiftSubtitle(String text, SubtitleTextFormat format, Duration offset) =>
    _mapTimes(text, format, (time) => time + offset);

/// Retimes a file made for [from] frames per second to play at [to]: a
/// 25 fps subtitle on a 23.976 film runs about 4% fast and drifts minutes out
/// by the end; this stretches it back.
String changeSubtitleFrameRate(String text, SubtitleTextFormat format, double from, double to) {
  if (from <= 0 || to <= 0) return text;
  final ratio = from / to;
  return _mapTimes(text, format, (time) => Duration(microseconds: (time.inMicroseconds * ratio).round()));
}

final _srtTime = RegExp(r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');
final _vttTime = RegExp(r'(?:(\d{1,2}):)?(\d{2}):(\d{2})\.(\d{3})');
final _assTime = RegExp(r'(\d):(\d{2}):(\d{2})\.(\d{2})');

String _mapTimes(String text, SubtitleTextFormat format, Duration Function(Duration) map) {
  Duration clamp(Duration d) => d.isNegative ? Duration.zero : d;
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    switch (format) {
      case SubtitleTextFormat.srt:
        if (!line.contains('-->')) continue;
        lines[i] = line.replaceAllMapped(_srtTime, (m) {
          final time = clamp(map(_time(m[1], m[2], m[3], m[4]!)));
          final separator = m[0]!.contains(',') ? ',' : '.';
          return '${_two(time.inHours)}:${_two(time.inMinutes % 60)}:${_two(time.inSeconds % 60)}'
              '$separator${(time.inMilliseconds % 1000).toString().padLeft(3, '0')}';
        });
      case SubtitleTextFormat.vtt:
        if (!line.contains('-->')) continue;
        // Only the two times before the cue settings ("align:start" - a
        // setting begins with a letter, a time with a digit).
        final arrow = line.indexOf('-->');
        final settingsStart = line.indexOf(RegExp(r'\s[A-Za-z][\w-]*:\S'), arrow + 3);
        final head = settingsStart == -1 ? line : line.substring(0, settingsStart);
        final tail = settingsStart == -1 ? '' : line.substring(settingsStart);
        lines[i] = head.replaceAllMapped(_vttTime, (m) {
          final time = clamp(map(_time(m[1] ?? '0', m[2], m[3], m[4]!)));
          return '${_two(time.inHours)}:${_two(time.inMinutes % 60)}:${_two(time.inSeconds % 60)}'
              '.${(time.inMilliseconds % 1000).toString().padLeft(3, '0')}';
        }) + tail;
      case SubtitleTextFormat.ass:
        // Dialogue: Layer,Start,End,Style,...
        if (!line.startsWith('Dialogue:') && !line.startsWith('Comment:')) continue;
        final colon = line.indexOf(':');
        final fields = line.substring(colon + 1).split(',');
        if (fields.length < 3) continue;
        for (final f in [1, 2]) {
          final m = _assTime.firstMatch(fields[f].trim());
          if (m == null) continue;
          final time = clamp(map(_time(m[1], m[2], m[3], '${m[4]}0')));
          final cs = (time.inMilliseconds % 1000) ~/ 10;
          fields[f] = '${time.inHours}:${_two(time.inMinutes % 60)}:${_two(time.inSeconds % 60)}.${_two(cs)}';
        }
        lines[i] = '${line.substring(0, colon + 1)}${fields.join(',')}';
    }
  }
  return lines.join('\n');
}

Duration _time(String? h, String? m, String? s, String fraction) {
  final ms = int.parse(fraction.padRight(3, '0').substring(0, 3));
  return Duration(hours: int.parse(h ?? '0'), minutes: int.parse(m!), seconds: int.parse(s!), milliseconds: ms);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// Strips what is written for the hard of hearing: [door slams],
/// (laughing), ♪ music ♪, and "JOHN:" speaker names. A cue left with no
/// words is dropped; SubRip cues are numbered again.
String removeHearingImpaired(String text, SubtitleTextFormat format) {
  switch (format) {
    case SubtitleTextFormat.ass:
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('Dialogue:')) continue;
        final parts = lines[i].split(',');
        if (parts.length < 10) continue;
        final head = parts.take(9).join(',');
        final body = parts.skip(9).join(',');
        final cleaned = body.split(r'\N').map(_cleanLine).where((l) => l.isNotEmpty).join(r'\N');
        lines[i] = '$head,$cleaned';
      }
      return lines.join('\n');
    case SubtitleTextFormat.srt:
    case SubtitleTextFormat.vtt:
      final newline = text.contains('\r\n') ? '\r\n' : '\n';
      final blocks = text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
      final kept = <String>[];
      for (final block in blocks) {
        final lines = block.split('\n');
        final timing = lines.indexWhere((l) => l.contains('-->'));
        if (timing == -1) {
          if (block.trim().isNotEmpty) kept.add(block);
          continue;
        }
        final words = lines.skip(timing + 1).map(_cleanLine).where((l) => l.isNotEmpty).toList();
        if (words.isEmpty) continue;
        final head = lines.take(timing + 1).toList();
        kept.add([...head, ...words].join('\n'));
      }
      if (format == SubtitleTextFormat.srt) {
        var number = 0;
        for (var i = 0; i < kept.length; i++) {
          final lines = kept[i].split('\n');
          final timing = lines.indexWhere((l) => l.contains('-->'));
          if (timing == -1) continue;
          number++;
          kept[i] = ['$number', ...lines.skip(timing)].join('\n');
        }
      }
      return '${kept.join('\n\n')}\n'.replaceAll('\n', newline);
  }
}

final _bracketed = RegExp(r'\[[^\]]*\]|\([^)]*\)|♪[^♪]*♪?|#[^#]*#');
final _speaker = RegExp(r'^(-\s*)?[A-Z][A-Z0-9 .\x27-]{1,30}:\s*');

String _cleanLine(String line) {
  var result = line.replaceAll(_bracketed, '');
  // Only an all-capitals name counts as a speaker label, so "Note: ..." stays.
  result = result.replaceFirstMapped(_speaker, (m) => m[1] ?? '');
  result = result.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  // A dash left with nothing after it.
  if (RegExp(r'^-\s*$').hasMatch(result)) return '';
  // Tags left around nothing: "<i></i>".
  if (result.replaceAll(RegExp(r'<[^>]*>'), '').trim().isEmpty) return '';
  return result;
}

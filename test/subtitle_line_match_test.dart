import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/subtitle_cues.dart';
import 'package:chudder/models/subtitles/subtitle_line_match.dart';
import 'package:chudder/providers/subtitles/subtitle_timing_provider.dart';

Duration s(num seconds) => Duration(milliseconds: (seconds * 1000).round());

SubtitleCueList cues(List<(num, num, String)> lines) =>
    SubtitleCueList([for (final (start, end, text) in lines) SubtitleCue(s(start), s(end), text)]);

void main() {
  final film = cues([
    (10, 12, 'Where were you last night?'),
    (13, 15, "I was at Sarah's."),
    (16, 18, '[door slams]\nJOHN: Get out of my house!'),
    (20, 21, 'What?'),
    (25, 28, 'You heard me. Get out.'),
    (700, 701, 'What?'),
    (900, 903, "Qu'est-ce que tu fais là?"),
  ]);

  group('normaliseSubtitleText', () {
    test('drops notes, speakers, punctuation and accents', () {
      expect(normaliseSubtitleText('[door slams]\nJOHN: Get out of my house!'), 'get out of my house');
      expect(normaliseSubtitleText("Qu'est-ce que tu fais là?"), 'quest ce que tu fais la');
      expect(normaliseSubtitleText("I don't KNOW..."), 'i dont know');
      expect(normaliseSubtitleText("Here's the thing: no."), 'heres the thing no');
    });
  });

  group('searchSubtitleLines', () {
    test('finds the line from a few typed words', () {
      final result = searchSubtitleLines(film, 'out of my', heardAt: s(19));
      expect(result.matches.first.cue.text, contains('Get out of my house'));
      expect(result.matches.first.matched, containsAll(['out', 'of', 'my']));
    });

    test('a half typed last word and a misspelling still find it', () {
      expect(searchSubtitleLines(film, 'where were you la', heardAt: s(13)).matches.first.cue.start, s(10));
      expect(searchSubtitleLines(film, 'where wree you', heardAt: s(13)).matches.first.cue.start, s(10));
    });

    test('a line said twice is found near the moment first', () {
      final early = searchSubtitleLines(film, 'what', heardAt: s(22));
      expect(early.matches.first.cue.start, s(20));
      final late = searchSubtitleLines(film, 'what', heardAt: s(702));
      expect(late.matches.first.cue.start, s(700));
    });

    test('the moment is looked for where the moved subtitles put it', () {
      // Subtitles already 600 s later: at 702 s in the video the file is at 102 s,
      // nearer the first "What?".
      final result = searchSubtitleLines(film, 'what', heardAt: s(702), currentDelay: s(600));
      expect(result.matches.first.cue.start, s(20));
    });

    test('words that are not in the file find nothing, and the nearby lines are there', () {
      final result = searchSubtitleLines(film, 'banana helicopter', heardAt: s(19));
      expect(result.matches, isEmpty);
      expect(result.nearby, isNotEmpty);
      expect(result.nearby[result.nearest].cue.start, s(16));
    });

    test('with nothing typed the lines around the moment are offered in order', () {
      final result = searchSubtitleLines(film, '', heardAt: s(22), nearbyBefore: 3, nearbyAfter: 1);
      expect([for (final c in result.nearby) c.cue.start], [s(13), s(16), s(20), s(25)]);
      expect(result.nearby[result.nearest].cue.start, s(20));
    });

    test('rare words decide between lines that share common ones', () {
      final list = cues([
        (100, 102, 'You told me you would come back.'),
        (200, 202, 'I know you did.'),
        (300, 302, "I told you: don't come back here."),
        (400, 402, 'You never come back for me.'),
        (500, 502, 'Did you come back?'),
      ]);
      final result = searchSubtitleLines(list, 'told you dont come back', heardAt: s(110));
      expect(result.matches.first.cue.start, s(300));
    });

    test('of two lines with every typed word, the one in that order wins', () {
      final list = cues([
        (100, 102, 'What? You know I hate that.'),
        (300, 302, 'You know what I mean.'),
      ]);
      final result = searchSubtitleLines(list, 'you know what', heardAt: s(103));
      expect(result.matches.first.cue.start, s(300));
    });

    test('Enter takes the first match only when it is well ahead', () {
      expect(searchSubtitleLines(film, 'out of my house', heardAt: s(19)).clearBest, isTrue);
      final twice = cues([(100, 101, 'Come here.'), (200, 201, 'Come here.')]);
      expect(searchSubtitleLines(twice, 'come here', heardAt: s(150)).clearBest, isFalse);
    });

    test('lines after the moment are offered too, for late subtitles', () {
      final list = cues([for (var i = 0; i < 30; i++) (i * 10, i * 10 + 2, 'Line $i')]);
      final result = searchSubtitleLines(list, '', heardAt: s(103));
      expect(result.nearby.last.cue.start, greaterThanOrEqualTo(s(160)));
    });

    test('before the first line the first one is nearest', () {
      final result = searchSubtitleLines(film, '', heardAt: s(2));
      expect(result.nearby[result.nearest].cue.start, s(10));
    });
  });

  group('lineMatchDelay', () {
    test('a line heard late moves the subtitles later', () {
      // Short line: counted as said by 0.6 s after its start.
      final delay = lineMatchDelay(s(24), SubtitleCue(s(20), s(21), 'What?'));
      expect(delay, s(24) - lineMatchReaction - s(20.6));
    });

    test('a long line is not counted as said past its end', () {
      final text = 'x' * 200;
      final delay = lineMatchDelay(s(30), SubtitleCue(s(20), s(22), text));
      expect(delay, s(30) - lineMatchReaction - s(22));
    });

    test('a line heard early moves them earlier', () {
      expect(lineMatchDelay(s(5), SubtitleCue(s(20), s(22), 'Where were you last night?')).isNegative, isTrue);
    });
  });

  group('ASS', () {
    test('reads the dialogue of an ASS file', () {
      const file = '[Script Info]\nTitle: x\n\n[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          r'Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\i1}Hello,\Nthere{\i0}' '\n'
          'Comment: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,not shown\n';
      final list = SubtitleCueList.parse(file);
      expect(list.cues, hasLength(1));
      expect(list.cues.first.start, s(1.5));
      expect(list.cues.first.end, s(3));
      expect(list.cues.first.text, 'Hello,\nthere');
    });
  });

  group('parseSubtitleDelay', () {
    test('reads seconds, signs, commas and minutes', () {
      expect(parseSubtitleDelay('1.5'), s(1.5));
      expect(parseSubtitleDelay('+2'), s(2));
      expect(parseSubtitleDelay('-0,25 s'), s(-0.25));
      expect(parseSubtitleDelay('.5'), s(0.5));
      expect(parseSubtitleDelay('-1:05.5'), s(-65.5));
    });

    test('refuses what is not a timing', () {
      expect(parseSubtitleDelay(''), isNull);
      expect(parseSubtitleDelay('abc'), isNull);
      expect(parseSubtitleDelay('1:75'), isNull);
      expect(parseSubtitleDelay('--1'), isNull);
    });
  });
}

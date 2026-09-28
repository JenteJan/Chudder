import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/subtitle_text_tools.dart';

const _srt = '''1
00:00:01,000 --> 00:00:03,500
[door slams]
Where were you?

2
00:00:04,000 --> 00:00:05,000
(laughing)

3
00:59:59,900 --> 01:00:01,250
JOHN: Out.
''';

void main() {
  group('shiftSubtitle', () {
    test('moves SubRip cues later, across the hour', () {
      final out = shiftSubtitle(_srt, SubtitleTextFormat.srt, const Duration(milliseconds: 250));
      expect(out, contains('00:00:01,250 --> 00:00:03,750'));
      expect(out, contains('01:00:00,150 --> 01:00:01,500'));
      expect(out, contains('Where were you?'), reason: 'text untouched');
    });

    test('clamps at zero instead of going negative', () {
      final out = shiftSubtitle(_srt, SubtitleTextFormat.srt, const Duration(seconds: -2));
      expect(out, contains('00:00:00,000 --> 00:00:01,500'));
    });

    test('WebVTT keeps its cue settings and short times', () {
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:02.500 align:start position:10%\nHi\n';
      final out = shiftSubtitle(vtt, SubtitleTextFormat.vtt, const Duration(seconds: 1));
      expect(out, contains('00:00:02.000 --> 00:00:03.500 align:start position:10%'));
    });

    test('ASS moves Dialogue start and end only', () {
      const ass = '[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
          r'Dialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,{\i1}Hello, there{\i0}';
      final out = shiftSubtitle(ass, SubtitleTextFormat.ass, const Duration(milliseconds: -500));
      expect(out, contains(r'Dialogue: 0,0:00:00.50,0:00:02.00,Default,,0,0,0,,{\i1}Hello, there{\i0}'));
    });
  });

  test('changeSubtitleFrameRate stretches a 25 fps file to 23.976', () {
    const one = '1\n01:00:00,000 --> 01:00:01,000\nx\n';
    final out = changeSubtitleFrameRate(one, SubtitleTextFormat.srt, 25, 23.976);
    // An hour at 25 fps is 1h 2m 33.7s at 23.976.
    expect(out, contains('01:02:33,7'));
  });

  group('removeHearingImpaired', () {
    test('drops sound cues, speaker names and empty cues, and renumbers', () {
      final out = removeHearingImpaired(_srt, SubtitleTextFormat.srt);
      expect(out, isNot(contains('door slams')));
      expect(out, isNot(contains('laughing')));
      expect(out, isNot(contains('JOHN')));
      expect(out, contains('Out.'));
      expect(out, contains('Where were you?'));
      expect(RegExp(r'^2$', multiLine: true).hasMatch(out), isTrue, reason: 'the third cue is now number 2');
      expect(RegExp(r'^3$', multiLine: true).hasMatch(out), isFalse);
    });

    test('keeps a "Note:" line that is not a speaker', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,000\nNote: the door.\n';
      expect(removeHearingImpaired(srt, SubtitleTextFormat.srt), contains('Note: the door.'));
    });

    test('keeps CRLF files CRLF', () {
      final out = removeHearingImpaired(_srt.replaceAll('\n', '\r\n'), SubtitleTextFormat.srt);
      expect(out, contains('\r\n'));
      expect(out.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('ASS keeps override tags', () {
      const ass = r'Dialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,{\i1}[music]\NMARY: Run!{\i0}';
      final out = removeHearingImpaired(ass, SubtitleTextFormat.ass);
      expect(out, contains('Run!'));
      expect(out, isNot(contains('music')));
      expect(out, isNot(contains('MARY')));
    });
  });

  test('formats by codec or extension', () {
    expect(subtitleTextFormatOf('subrip'), SubtitleTextFormat.srt);
    expect(subtitleTextFormatOf('.ass'), SubtitleTextFormat.ass);
    expect(subtitleTextFormatOf('PGSSUB'), isNull);
  });
}

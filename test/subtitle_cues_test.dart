import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/subtitles/subtitle_cues.dart';

void main() {
  const srt = '1\r\n00:00:01,000 --> 00:00:03,000\r\n<i>Hello</i>\r\n\r\n'
      '2\r\n00:00:02,500 --> 00:00:04,000\r\n{\\an8}Top line\r\n\r\n'
      '3\r\n01:00:00,000 --> 01:00:01,500\r\nLate\r\n';

  test('finds what is on screen, overlaps included, tags dropped', () {
    final cues = SubtitleCueList.parse(srt);
    expect(cues.cues, hasLength(3));
    expect(cues.textAt(const Duration(milliseconds: 500)), '');
    expect(cues.textAt(const Duration(seconds: 1)), 'Hello');
    expect(cues.textAt(const Duration(milliseconds: 2700)), 'Hello\nTop line');
    expect(cues.textAt(const Duration(milliseconds: 3500)), 'Top line');
    expect(cues.textAt(const Duration(seconds: 4)), '');
    expect(cues.textAt(const Duration(hours: 1, milliseconds: 200)), 'Late');
  });

  test('reads WebVTT short times and cue settings', () {
    const vtt = 'WEBVTT\n\n00:01.000 --> 00:02.000 align:start\nHi\n';
    expect(SubtitleCueList.parse(vtt).textAt(const Duration(milliseconds: 1500)), 'Hi');
  });
}

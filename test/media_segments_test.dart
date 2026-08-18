import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/models/items/media_segments_model.dart';

void main() {
  MediaSegment intro({int startSeconds = 10, int endSeconds = 70}) => MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration(seconds: startSeconds),
        end: Duration(seconds: endSeconds),
      );

  group('MediaSegment.inRange', () {
    test('includes both ends of the segment', () {
      final segment = intro();
      expect(segment.inRange(const Duration(seconds: 10)), isTrue);
      expect(segment.inRange(const Duration(seconds: 40)), isTrue);
      // Inclusive: a skip lands exactly here, so callers offering a skip have
      // to rule the segment out themselves or they offer it forever.
      expect(segment.inRange(const Duration(seconds: 70)), isTrue);
    });

    test('excludes positions outside the segment', () {
      final segment = intro();
      expect(segment.inRange(const Duration(seconds: 9)), isFalse);
      expect(segment.inRange(const Duration(seconds: 71)), isFalse);
    });
  });

  group('MediaSegmentsModel.atPosition', () {
    test('still returns the segment at the position a skip lands on', () {
      final segment = intro();
      final segments = MediaSegmentsModel(segments: [segment]);
      expect(segments.atPosition(segment.end), segment);
    });

    test('returns null past the segment', () {
      final segments = MediaSegmentsModel(segments: [intro()]);
      expect(segments.atPosition(const Duration(seconds: 80)), isNull);
    });
  });

  group('MediaSegment.skipId', () {
    test('is stable for the same segment', () {
      expect(intro().skipId, intro().skipId);
    });

    test('differs by start', () {
      expect(intro(startSeconds: 10).skipId, isNot(intro(startSeconds: 20).skipId));
    });

    test('differs by type', () {
      final outro = MediaSegment(
        type: MediaSegmentType.outro,
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 70),
      );
      expect(intro().skipId, isNot(outro.skipId));
    });
  });

  group('MediaSegment.visibility', () {
    test('stays visible right after a skip, which is why position alone is not enough', () {
      final segment = intro();
      expect(segment.visibility(segment.end), isNot(SegmentVisibility.hidden));
    });

    test('hides once well past the start of a long segment', () {
      final long = MediaSegment(
        type: MediaSegmentType.intro,
        start: Duration.zero,
        end: const Duration(minutes: 5),
      );
      expect(long.visibility(const Duration(minutes: 2)), SegmentVisibility.hidden);
    });
  });
}

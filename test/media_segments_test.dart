import 'package:flutter_test/flutter_test.dart';

import 'package:chudder/models/items/media_segments_model.dart';

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

  group('MediaSegmentsModel.creditsReached', () {
    const runtime = Duration(minutes: 22);

    MediaSegmentsModel credits({required Duration start, required Duration end}) => MediaSegmentsModel(
          segments: [intro(), MediaSegment(type: MediaSegmentType.outro, start: start, end: end)],
        );

    test('credits that run to the end finish the episode, before 90% of it', () {
      // 19:30 of 22:00 is 88.6%.
      final segments = credits(start: const Duration(minutes: 19, seconds: 30), end: runtime);
      expect(segments.creditsReached(const Duration(minutes: 19, seconds: 29), runtime), isFalse);
      expect(segments.creditsReached(const Duration(minutes: 19, seconds: 30), runtime), isTrue);
      expect(segments.creditsReached(const Duration(minutes: 21), runtime), isTrue);
    });

    test('a scene after the credits leaves it to resume', () {
      final segments = credits(
        start: const Duration(minutes: 19),
        end: const Duration(minutes: 21),
      );
      expect(segments.creditsReached(const Duration(minutes: 20), runtime), isFalse);
    });

    test('an outro in the first half is not believed', () {
      final segments = MediaSegmentsModel(
        segments: [MediaSegment(type: MediaSegmentType.outro, start: const Duration(minutes: 5), end: runtime)],
      );
      expect(segments.creditsReached(const Duration(minutes: 6), runtime), isFalse);
    });

    test('nothing is finished without an outro or a runtime', () {
      final segments = MediaSegmentsModel(segments: [intro()]);
      expect(segments.creditsReached(const Duration(minutes: 21), runtime), isFalse);
      expect(
        credits(start: const Duration(minutes: 19), end: runtime)
            .creditsReached(const Duration(minutes: 21), Duration.zero),
        isFalse,
      );
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

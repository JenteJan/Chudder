import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/extensions/duration.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart' as dto;
import 'package:fladder/util/localization_helper.dart';

part 'media_segments_model.freezed.dart';
part 'media_segments_model.g.dart';

@freezed
abstract class MediaSegmentsModel with _$MediaSegmentsModel {
  const MediaSegmentsModel._();

  factory MediaSegmentsModel({
    @Default([]) List<MediaSegment> segments,
  }) = _MediaSegmentsModel;

  factory MediaSegmentsModel.fromJson(Map<String, dynamic> json) => _$MediaSegmentsModelFromJson(json);

  MediaSegment? atPosition(Duration position) => segments.firstWhereOrNull((element) => element.inRange(position));

  MediaSegment? get intro => segments.firstWhereOrNull((element) => element.type == MediaSegmentType.intro);
  MediaSegment? get outro => segments.firstWhereOrNull((element) => element.type == MediaSegmentType.outro);
}

@freezed
abstract class MediaSegment with _$MediaSegment {
  const MediaSegment._();

  factory MediaSegment({
    required MediaSegmentType type,
    required Duration start,
    required Duration end,
  }) = _MediaSegment;

  factory MediaSegment.fromJson(Map<String, dynamic> json) => _$MediaSegmentFromJson(json);

  bool inRange(Duration position) => (position.compareTo(start) >= 0 && position.compareTo(end) <= 0);

  SegmentVisibility visibility(Duration position, {bool force = false}) {
    if (force) return SegmentVisibility.visible;
    var difference = (position - start);
    if (difference > const Duration(minutes: 1, seconds: 30)) return SegmentVisibility.hidden;
    Duration clamp = ((end - start) * 0.20).clamp(Duration.zero, const Duration(minutes: 1));
    return difference < clamp ? SegmentVisibility.visible : SegmentVisibility.partially;
  }
}

enum SegmentVisibility {
  hidden,
  partially,
  visible;
}

const Map<MediaSegmentType, SegmentSkip> defaultSegmentSkipValues = {
  MediaSegmentType.commercial: SegmentSkip.askToSkip,
  MediaSegmentType.preview: SegmentSkip.askToSkip,
  MediaSegmentType.recap: SegmentSkip.askToSkip,
  MediaSegmentType.outro: SegmentSkip.askToSkip,
  MediaSegmentType.intro: SegmentSkip.askToSkip,
};

enum SegmentSkip {
  none,
  askToSkip,
  skipOnce,
  skip;

  const SegmentSkip();

  String label(BuildContext context) => switch (this) {
        SegmentSkip.none => context.localized.segmentActionNone,
        SegmentSkip.askToSkip => context.localized.segmentActionAskToSkip,
        SegmentSkip.skipOnce => context.localized.segmentActionSkipOnce,
        SegmentSkip.skip => context.localized.segmentActionSkip,
      };
}

enum MediaSegmentType {
  unknown,
  commercial,
  preview,
  recap,
  outro,
  intro;

  String label(BuildContext context) {
    return switch (this) {
      MediaSegmentType.unknown => context.localized.mediaSegmentUnknown,
      MediaSegmentType.commercial => context.localized.mediaSegmentCommercial,
      MediaSegmentType.preview => context.localized.mediaSegmentPreview,
      MediaSegmentType.recap => context.localized.mediaSegmentRecap,
      MediaSegmentType.outro => context.localized.mediaSegmentOutro,
      MediaSegmentType.intro => context.localized.mediaSegmentIntro,
    };
  }

  Color get color => switch (this) {
        MediaSegmentType.unknown => Colors.black,
        MediaSegmentType.commercial => Colors.purpleAccent,
        MediaSegmentType.preview => Colors.deepOrangeAccent,
        MediaSegmentType.recap => Colors.lightBlueAccent,
        MediaSegmentType.outro => Colors.yellowAccent,
        MediaSegmentType.intro => Colors.greenAccent,
      };

  static MediaSegmentType fromDto(dto.MediaSegmentType? value) {
    return switch (value) {
      dto.MediaSegmentType.swaggerGeneratedUnknown => MediaSegmentType.unknown,
      dto.MediaSegmentType.unknown => MediaSegmentType.unknown,
      dto.MediaSegmentType.commercial => MediaSegmentType.commercial,
      dto.MediaSegmentType.preview => MediaSegmentType.preview,
      dto.MediaSegmentType.recap => MediaSegmentType.recap,
      dto.MediaSegmentType.outro => MediaSegmentType.outro,
      dto.MediaSegmentType.intro => MediaSegmentType.intro,
      null => MediaSegmentType.unknown,
    };
  }
}

extension MediaSegmentExtension on dto.MediaSegmentDto {
  MediaSegment get toSegment => MediaSegment(
        type: MediaSegmentType.fromDto(type),
        start: _durationToMilliseconds(startTicks ?? 0),
        end: _durationToMilliseconds(endTicks ?? 0),
      );
}

Duration _durationToMilliseconds(num milliseconds) => Duration(milliseconds: (milliseconds ~/ 10000));

/// Maps for chapter name to MediaSegmentType conversion
const Map<String, MediaSegmentType> _chapterNameToSegmentType = {
  'opening': MediaSegmentType.intro,
  'op': MediaSegmentType.intro,
  'intro': MediaSegmentType.intro,
  'introduction': MediaSegmentType.intro,
  'ending': MediaSegmentType.outro,
  'ed': MediaSegmentType.outro,
  'outro': MediaSegmentType.outro,
  'credits': MediaSegmentType.outro,
};

/// Creates MediaSegments from chapters based on their names.
/// Maps "Opening", "OP", "Intro" → intro, and "Ending", "ED", "Outro", "Credits" → outro.
/// [chapters] - List of chapter objects with `name` and `startPosition`
/// [totalDuration] - Total duration of the media (used for last chapter's end time)
List<MediaSegment> mediaSegmentsFromChapters<T>({
  required List<T> chapters,
  required String Function(T) getName,
  required Duration Function(T) getStartPosition,
  Duration? totalDuration,
}) {
  final segments = <MediaSegment>[];

  for (int i = 0; i < chapters.length; i++) {
    final chapter = chapters[i];
    final name = getName(chapter).toLowerCase().trim();
    final segmentType = _chapterNameToSegmentType[name];

    if (segmentType != null) {
      final start = getStartPosition(chapter);
      // End is either the start of the next chapter, or totalDuration, or start + 5 minutes
      final end = i + 1 < chapters.length
          ? getStartPosition(chapters[i + 1])
          : (totalDuration ?? start + const Duration(minutes: 5));

      segments.add(MediaSegment(
        type: segmentType,
        start: start,
        end: end,
      ));
    }
  }

  return segments;
}

/// Merges chapter-based segments with API segments.
/// API segments take priority (won't add chapter segment if API already has that type).
MediaSegmentsModel mergeWithChapterSegments(
  MediaSegmentsModel? apiSegments,
  List<MediaSegment> chapterSegments,
) {
  final existingTypes = apiSegments?.segments.map((s) => s.type).toSet() ?? {};
  final newSegments = chapterSegments.where((s) => !existingTypes.contains(s.type)).toList();

  return MediaSegmentsModel(
    segments: [...(apiSegments?.segments ?? []), ...newSegments],
  );
}

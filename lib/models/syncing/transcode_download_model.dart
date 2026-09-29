import 'package:flutter/material.dart';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/util/bitrate_helper.dart';
import 'package:chudder/util/localization_helper.dart';

part 'transcode_download_model.freezed.dart';
part 'transcode_download_model.g.dart';

@Freezed(copyWith: true)
abstract class TranscodeDownloadModel with _$TranscodeDownloadModel {
  const TranscodeDownloadModel._();

  factory TranscodeDownloadModel({
    @Default(false) bool enabled,
    required VideoCodec videoCodec,
    required AudioCodec audioCodec,
    required MaxHeight maxHeight,
    required VideoContainer container,
    required Bitrate maxBitrate,
  }) = _TranscodeDownloadModel;

  static TranscodeDownloadModel fromDefaults() {
    return TranscodeDownloadModel(
      enabled: false,
      videoCodec: VideoCodec.h264,
      audioCodec: AudioCodec.aac,
      maxHeight: MaxHeight.p480,
      container: VideoContainer.mp4,
      maxBitrate: Bitrate.b4Mbps,
    );
  }

  factory TranscodeDownloadModel.fromJson(Map<String, dynamic> json) => _$TranscodeDownloadModelFromJson(json);

  Map<String, String> curlHeaders(Duration duration, {ItemBaseModel? item}) => {
        'User-Agent': 'curl/8.0.1',
        'Accept': '*/*',
        'Connection': 'keep-alive',
        "Known-Content-Length": calculatedContentLength(duration, item: item).toString(),
      };

  /// Estimates download file size based on bitrate and duration.
  /// Adds 10% overhead for container and metadata.
  int calculatedContentLength(Duration duration, {ItemBaseModel? item}) {
    final seconds = duration.inSeconds;
    if (seconds <= 0) return 0;
    final bitrateValue = maxBitrate.bitRate ?? item?.streamModel?.videoStreams.firstOrNull?.bitRate ?? 4000000;
    return ((bitrateValue * seconds) / 8 * 1.1).floor();
  }

  /// Device profile for download transcoding.
  /// Uses HTTP protocol instead of HLS so the server returns a complete file URL.
  DeviceProfile get deviceProfile => DeviceProfile(
        maxStreamingBitrate: maxBitrate.bitRate,
        maxStaticBitrate: maxBitrate.bitRate,
        directPlayProfiles: const [
          DirectPlayProfile(type: DlnaProfileType.video),
          DirectPlayProfile(type: DlnaProfileType.audio),
        ],
        transcodingProfiles: [
          TranscodingProfile(
            audioCodec: audioCodec.name.toLowerCase(),
            container: container.name.toLowerCase(),
            maxAudioChannels: '2',
            protocol: MediaStreamProtocol.http,
            type: DlnaProfileType.video,
            videoCodec: videoCodec.name.toLowerCase(),
          ),
        ],
        containerProfiles: const [],
        // The resolution picked in the dialog was only ever written into the
        // saved metadata, never asked of the server, so a "480p" download of
        // a 4K film came down at 4K squeezed into the bitrate. As a codec
        // condition the server both refuses to hand over a larger original
        // and scales the transcode to fit.
        codecProfiles: [
          CodecProfile(
            type: CodecType.video,
            conditions: [
              ProfileCondition(
                condition: ProfileConditionType.lessthanequal,
                property: ProfileConditionValue.height,
                $Value: '${maxHeight.value}',
                isRequired: true,
              ),
            ],
          ),
        ],
        subtitleProfiles: const [
          SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ass', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ssa', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'pgssub', method: SubtitleDeliveryMethod.$external),
        ],
      );

  String label(BuildContext context) {
    if (!enabled) {
      return context.localized.qualityOptionsOriginal;
    }
    return "${context.localized.playbackTypeTranscode}: ${videoCodec.name.toUpperCase()} - ${audioCodec.name.toUpperCase()} | ${maxHeight.label}p | ~${maxBitrate.label(context)}";
  }
}

enum VideoCodec {
  h264,
  h265,
  vp9,
  av1;

  const VideoCodec();
  String get name => switch (this) {
        VideoCodec.h264 => "H264",
        VideoCodec.h265 => "H265",
        VideoCodec.vp9 => "VP9",
        VideoCodec.av1 => "AV1"
      };
}

enum AudioCodec {
  aac,
  mp3,
  opus,
  vorbis;

  const AudioCodec();

  String get name => switch (this) {
        AudioCodec.aac => "AAC",
        AudioCodec.mp3 => "MP3",
        AudioCodec.opus => "Opus",
        AudioCodec.vorbis => "Vorbis"
      };
}

enum MaxHeight {
  p480,
  p720,
  p1080,
  p1440,
  p2160;

  const MaxHeight();

  String get label => switch (this) {
        MaxHeight.p480 => "480",
        MaxHeight.p720 => "720",
        MaxHeight.p1080 => "1080",
        MaxHeight.p1440 => "1440",
        MaxHeight.p2160 => "2160"
      };

  int get value => switch (this) {
        MaxHeight.p480 => 480,
        MaxHeight.p720 => 720,
        MaxHeight.p1080 => 1080,
        MaxHeight.p1440 => 1440,
        MaxHeight.p2160 => 2160
      };
}

enum VideoContainer {
  mp4,
  mkv,
  webm;

  const VideoContainer();

  String get name => switch (this) {
        VideoContainer.mp4 => "mp4",
        VideoContainer.mkv => "mkv",
        VideoContainer.webm => "webm",
      };

  String get extension => switch (this) {
        VideoContainer.mp4 => ".mp4",
        VideoContainer.mkv => ".mkv",
        VideoContainer.webm => ".webm",
      };
}

/// The handful of download qualities worth choosing between, each with what
/// it costs in space. The full set of knobs stays behind [custom].
enum DownloadQualityPreset {
  original,
  high,
  balanced,
  small,
  custom;

  /// The settings a preset stands for, or null for [original] and [custom].
  TranscodeDownloadModel? get model => switch (this) {
        DownloadQualityPreset.high => TranscodeDownloadModel(
            enabled: true,
            videoCodec: VideoCodec.h264,
            audioCodec: AudioCodec.aac,
            maxHeight: MaxHeight.p1080,
            container: VideoContainer.mp4,
            maxBitrate: Bitrate.b8Mbps,
          ),
        DownloadQualityPreset.balanced => TranscodeDownloadModel(
            enabled: true,
            videoCodec: VideoCodec.h264,
            audioCodec: AudioCodec.aac,
            maxHeight: MaxHeight.p720,
            container: VideoContainer.mp4,
            maxBitrate: Bitrate.b4Mbps,
          ),
        DownloadQualityPreset.small => TranscodeDownloadModel(
            enabled: true,
            videoCodec: VideoCodec.h264,
            audioCodec: AudioCodec.aac,
            maxHeight: MaxHeight.p480,
            container: VideoContainer.mp4,
            maxBitrate: Bitrate.b1_5Mbps,
          ),
        _ => null,
      };

  /// Which preset [model] is, if it is one.
  static DownloadQualityPreset of(TranscodeDownloadModel model) {
    if (!model.enabled) return DownloadQualityPreset.original;
    for (final preset in [DownloadQualityPreset.high, DownloadQualityPreset.balanced, DownloadQualityPreset.small]) {
      final candidate = preset.model!;
      if (candidate.maxHeight == model.maxHeight &&
          candidate.maxBitrate == model.maxBitrate &&
          candidate.videoCodec == model.videoCodec &&
          candidate.audioCodec == model.audioCodec &&
          candidate.container == model.container) {
        return preset;
      }
    }
    return DownloadQualityPreset.custom;
  }

  /// The one to suggest: a phone's storage and screen are both well served
  /// by 720p, and a computer has the room for the original.
  static DownloadQualityPreset recommended({required bool phone}) =>
      phone ? DownloadQualityPreset.balanced : DownloadQualityPreset.original;

  String label(BuildContext context) => switch (this) {
        DownloadQualityPreset.original => context.localized.qualityOptionsOriginal,
        DownloadQualityPreset.high => context.localized.downloadQualityHigh,
        DownloadQualityPreset.balanced => context.localized.downloadQualityBalanced,
        DownloadQualityPreset.small => context.localized.downloadQualitySmall,
        DownloadQualityPreset.custom => context.localized.downloadQualityCustom,
      };

  String description(BuildContext context) => switch (this) {
        DownloadQualityPreset.original => context.localized.downloadQualityOriginalDesc,
        DownloadQualityPreset.high => context.localized.downloadQualityHighDesc,
        DownloadQualityPreset.balanced => context.localized.downloadQualityBalancedDesc,
        DownloadQualityPreset.small => context.localized.downloadQualitySmallDesc,
        DownloadQualityPreset.custom => context.localized.downloadQualityCustomDesc,
      };
}

/// Roughly how many bytes [runtime] of video comes to at [bitsPerSecond],
/// with a tenth on top for audio and the container.
int estimateDownloadBytes(Duration runtime, int bitsPerSecond) =>
    (runtime.inSeconds * bitsPerSecond / 8 * 1.1).round();

/// What one download request covers: every file it will fetch.
class DownloadScope {
  const DownloadScope({required this.runtime, required this.count, this.originalBytes});

  final Duration runtime;
  final int count;
  final int? originalBytes;
}

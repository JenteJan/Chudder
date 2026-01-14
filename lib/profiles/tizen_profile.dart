import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Device profile for Samsung Tizen TVs
/// Supports common TV codecs: H.264, HEVC, VP9, AAC, MP3
/// Forces transcoding for unsupported formats
const DeviceProfile tizenProfile = DeviceProfile(
  maxStreamingBitrate: 40000000, // 40 Mbps - safe for most TVs
  maxStaticBitrate: 40000000,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    // Video formats supported by most Samsung TVs
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'mp4,mkv,webm,ts',
      videoCodec: 'h264,hevc,vp9',
      audioCodec: 'aac,ac3,eac3,mp3,opus',
    ),
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'hls',
      videoCodec: 'h264,hevc',
      audioCodec: 'aac,ac3,eac3,mp3',
    ),
    // Audio formats
    DirectPlayProfile(
      type: DlnaProfileType.audio,
      container: 'mp3,aac,flac,wav,ogg',
      audioCodec: 'mp3,aac,flac,pcm,opus',
    ),
  ],
  transcodingProfiles: [
    // Transcode to HLS with H.264 for maximum compatibility
    TranscodingProfile(
      audioCodec: 'aac,mp3',
      container: 'ts',
      maxAudioChannels: '6',
      protocol: MediaStreamProtocol.hls,
      type: DlnaProfileType.video,
      videoCodec: 'h264',
      context: EncodingContext.streaming,
      breakOnNonKeyFrames: true,
    ),
    // Audio transcoding
    TranscodingProfile(
      audioCodec: 'aac',
      container: 'mp4',
      type: DlnaProfileType.audio,
      context: EncodingContext.streaming,
    ),
  ],
  containerProfiles: [
    ContainerProfile(
      type: DlnaProfileType.video,
      container: 'mp4,mkv',
    ),
  ],
  codecProfiles: [
    // H.264 constraints - most TVs handle up to 1080p well
    CodecProfile(
      type: CodecType.video,
      codec: 'h264',
      conditions: [
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          $Value: '40000000',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videolevel,
          $Value: '52',
          isRequired: false,
        ),
      ],
    ),
    // HEVC/H.265 constraints - force transcode for HDR content
    CodecProfile(
      type: CodecType.video,
      codec: 'hevc',
      conditions: [
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          $Value: '40000000',
          isRequired: false,
        ),
        // Block HDR - force transcoding by rejecting HDR transfer functions
        ProfileCondition(
          condition: ProfileConditionType.notequals,
          property: ProfileConditionValue.videorangetype,
          $Value: 'HDR10',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.notequals,
          property: ProfileConditionValue.videorangetype,
          $Value: 'HLG',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.notequals,
          property: ProfileConditionValue.videorangetype,
          $Value: 'DOVIWithHDR10',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.notequals,
          property: ProfileConditionValue.videorangetype,
          $Value: 'DOVIWithHLG',
          isRequired: false,
        ),
      ],
    ),
    // VP9 constraints
    CodecProfile(
      type: CodecType.video,
      codec: 'vp9',
      conditions: [
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          $Value: '40000000',
          isRequired: false,
        ),
      ],
    ),
  ],
  subtitleProfiles: [
    SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
    SubtitleProfile(format: 'srt', method: SubtitleDeliveryMethod.$external),
    SubtitleProfile(format: 'ass', method: SubtitleDeliveryMethod.encode),
    SubtitleProfile(format: 'ssa', method: SubtitleDeliveryMethod.encode),
    SubtitleProfile(format: 'pgssub', method: SubtitleDeliveryMethod.encode),
    SubtitleProfile(format: 'sub', method: SubtitleDeliveryMethod.encode),
  ],
);

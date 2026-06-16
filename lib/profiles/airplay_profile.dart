import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Device profile for **video AirPlay via `AVPlayer`** (the `video_player`
/// dependency on iOS/macOS). Unlike the Chromecast default-receiver path, the
/// phone's `AVPlayer` plays the stream and the OS routes it to the Apple TV, so
/// we target what `AVPlayer` decodes natively: **HLS** (its preferred protocol)
/// with H.264/AAC.
///
/// We request an **HLS** transcode (not progressive MP4) because `AVPlayer`
/// adapts and seeks HLS reliably and it's the format AirPlay is built around.
/// H.264 (not HEVC) for the transcode keeps it decodable on the widest range of
/// Apple TV / AirPlay 2 receivers; already-friendly H.264/HEVC MP4 can direct
/// play.
const airplayMaxBitrate = 20000000; // 20 Mbps — generous for an Apple TV over LAN

const airplayProfile = DeviceProfile(
  maxStreamingBitrate: airplayMaxBitrate,
  maxStaticBitrate: airplayMaxBitrate,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'mp4,m4v,mov',
      videoCodec: 'h264,hevc',
      audioCodec: 'aac,mp3',
    ),
    DirectPlayProfile(
      type: DlnaProfileType.audio,
      container: 'mp3,aac,m4a',
    ),
  ],
  transcodingProfiles: [
    // HLS (TS segments) — AVPlayer's native adaptive path; the segments are
    // fetched by the phone's AVPlayer and routed out over AirPlay.
    TranscodingProfile(
      audioCodec: 'aac',
      container: 'ts',
      maxAudioChannels: '2',
      protocol: MediaStreamProtocol.hls,
      type: DlnaProfileType.video,
      videoCodec: 'h264',
      context: EncodingContext.streaming,
    ),
  ],
  codecProfiles: [
    CodecProfile(
      type: CodecType.video,
      codec: 'h264',
      conditions: [
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videolevel,
          $Value: '51', // H.264 level 5.1 — 4K-capable Apple TVs
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.width,
          $Value: '3840',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.height,
          $Value: '2160',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          $Value: '$airplayMaxBitrate',
          isRequired: false,
        ),
      ],
    ),
  ],
  containerProfiles: [],
  subtitleProfiles: [
    // HLS can carry WebVTT; external as a fallback. Track *switching* mid-play
    // is not wired for AirPlay (see CASTING.md) — this sets the burned/initial
    // selection the transcode is built with.
    SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.hls),
    SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
  ],
);

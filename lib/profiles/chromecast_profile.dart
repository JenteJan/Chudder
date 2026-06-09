import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Conservative device profile for Google's default Chromecast media receiver.
///
/// The receiver can only decode H.264 (up to ~level 4.1, 1080p) with AAC stereo,
/// at modest bitrates — far less than the local-playback profile's 120 Mbps. This
/// profile forces anything outside those limits (HEVC, 4K, 10-bit, high bitrate,
/// surround audio) to transcode to a Chromecast-friendly HLS stream, while letting
/// already-compatible content direct-play.
const chromecastMaxBitrate = 20000000; // 20 Mbps

const chromecastProfile = DeviceProfile(
  maxStreamingBitrate: chromecastMaxBitrate,
  maxStaticBitrate: chromecastMaxBitrate,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'mp4',
      videoCodec: 'h264',
      audioCodec: 'aac,mp3',
    ),
    DirectPlayProfile(
      type: DlnaProfileType.audio,
      container: 'mp3,aac',
    ),
  ],
  transcodingProfiles: [
    TranscodingProfile(
      audioCodec: 'aac',
      container: 'ts',
      maxAudioChannels: '2',
      protocol: MediaStreamProtocol.hls,
      type: DlnaProfileType.video,
      videoCodec: 'h264',
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
          $Value: '41',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.width,
          $Value: '1920',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.height,
          $Value: '1080',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          $Value: '$chromecastMaxBitrate',
          isRequired: false,
        ),
      ],
    ),
  ],
  containerProfiles: [],
  subtitleProfiles: [
    SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
  ],
);

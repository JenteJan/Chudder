import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Conservative device profile for Google's **default Cast media receiver**
/// (`CC1AD845`), targeting the lowest common denominator — a first-generation
/// Chromecast ("Eureka Dongle", 2013). That hardware decodes H.264 (up to
/// ~level 4.1, 1080p30) with AAC stereo only, at modest bitrates.
///
/// We request a **progressive (non-HLS) MP4** transcode so the on-device proxy
/// can re-serve it as a single range-able file (HLS would need playlist
/// rewriting). Anything outside the limits below is transcoded; already-friendly
/// content can direct-play.
const chromecastMaxBitrate = 8000000; // 8 Mbps — gentle for old hardware over LAN

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
    // Progressive MP4 over plain HTTP — a single file the proxy can stream with
    // Range support, and the most broadly decodable container for the default
    // receiver on old hardware.
    TranscodingProfile(
      audioCodec: 'aac',
      container: 'mp4',
      maxAudioChannels: '2',
      protocol: MediaStreamProtocol.http,
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

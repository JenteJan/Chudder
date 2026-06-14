import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';

/// Device profile for **DLNA/UPnP renderers** (LG webOS, Samsung Tizen, generic
/// MediaRenderers). Like the Chromecast default-receiver path, we ask Jellyfin
/// for a **progressive MP4** (H.264/AAC) the renderer can fetch over plain HTTP
/// from the on-device proxy with Range support — DLNA renderers can't take
/// arbitrary containers (a direct-play MKV makes webOS answer UPnP 701
/// "Transition not available").
///
/// Already-compatible H.264/AAC MP4 direct-streams (no re-encode); anything else
/// (e.g. MKV/HEVC) transcodes. 1080p ceiling keeps it broadly decodable across
/// TV hardware without pushing 4K transcodes server-side.
const dlnaMaxBitrate = 20000000; // 20 Mbps — comfortable for 1080p over LAN

const dlnaProfile = DeviceProfile(
  maxStreamingBitrate: dlnaMaxBitrate,
  maxStaticBitrate: dlnaMaxBitrate,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'mp4',
      videoCodec: 'h264',
      audioCodec: 'aac,mp3,ac3',
    ),
  ],
  transcodingProfiles: [
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
          $Value: '$dlnaMaxBitrate',
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

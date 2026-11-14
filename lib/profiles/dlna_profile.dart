import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';

/// Device profile for **DLNA/UPnP renderers** (LG webOS, Samsung Tizen, generic
/// MediaRenderers). We let the renderer **direct-play the original file** for the
/// common smart-TV containers/codecs — served over plain HTTP from the on-device
/// proxy with Range support — because a forced *live* transcode frequently won't
/// start on these TVs (they fetch the stream but answer UPnP 501/701 "Transition
/// not available" instead of transitioning to PLAYING). The renderer is the
/// authority on what it can decode; anything outside this list — or a subtitle
/// burn-in / quality cap chosen in-player — falls back to a **Matroska (MKV)**
/// transcode (1080p ceiling, broadly decodable). MKV is used rather than MP4
/// (whose live-transcode index lands at the end of the stream, so it can't
/// start on webOS/Tizen) or MPEG-TS (which those TVs reject at
/// SetAVTransportURI). The renderer already accepts video/x-matroska for direct
/// play, and MKV streams without an up-front index.
const dlnaMaxBitrate = 20000000; // 20 Mbps — comfortable for 1080p over LAN

/// The bitrate to ask for when a transcode is forced (a burned-in subtitle,
/// another audio track) with no quality picked. Asked for [dlnaMaxBitrate] the
/// server spends all of it, whatever the source: a 2.5 Mbps HEVC film went out
/// as 20 Mbps of H.264, every bit of it relayed by the phone over the same
/// Wi-Fi the television is on. Twice the source's video bitrate keeps what the
/// file has (H.264 needs about that against HEVC) plus room for the audio,
/// within a floor that keeps a small source clean and the usual ceiling.
int dlnaTranscodeBitrate(int? sourceVideoBitrate) {
  if (sourceVideoBitrate == null || sourceVideoBitrate <= 0) return dlnaMaxBitrate;
  return (sourceVideoBitrate * 2 + 1000000).clamp(6000000, dlnaMaxBitrate);
}

const dlnaProfile = DeviceProfile(
  maxStreamingBitrate: dlnaMaxBitrate,
  maxStaticBitrate: dlnaMaxBitrate,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    // Broad set covering what modern DLNA TVs (LG webOS, Samsung Tizen) decode
    // natively, so the renderer gets the original file instead of a live
    // transcode it can't start.
    DirectPlayProfile(
      type: DlnaProfileType.video,
      container: 'mp4,mkv,ts,avi,mov,m4v,webm,mpegts,m2ts,wmv',
      videoCodec: 'h264,hevc,h265,mpeg2video,mpeg4,vc1,vp8,vp9,av1',
      audioCodec: 'aac,mp3,ac3,eac3,dts,truehd,flac,opus,vorbis,pcm,wma',
    ),
  ],
  transcodingProfiles: [
    TranscodingProfile(
      audioCodec: 'aac,ac3',
      // Matroska: the renderer already accepts video/x-matroska (direct MKV
      // plays), and unlike MP4 it streams without an up-front index. webOS/Tizen
      // reject our MPEG-TS advertisement outright (SetAVTransportURI → UPnP 701,
      // without even fetching), so TS is a poor transcode target here.
      container: 'mkv',
      maxAudioChannels: '6',
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
          value: '41',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.width,
          value: '1920',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.height,
          value: '1080',
          isRequired: false,
        ),
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitrate,
          value: '$dlnaMaxBitrate',
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

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/profiles/web_profile.dart';
import 'package:chudder/providers/video_player_provider.dart';

final videoProfileProvider = StateProvider.autoDispose<DeviceProfile>((ref) =>
    defaultProfile(ref.read(videoPlayerProvider.select((value) => value.backend)) ?? PlayerOptions.platformDefaults));

DeviceProfile defaultProfile(PlayerOptions player) => kIsWeb
    ? webProfile
    : const DeviceProfile(
        maxStreamingBitrate: 120000000,
        maxStaticBitrate: 120000000,
        musicStreamingTranscodingBitrate: 384000,
        directPlayProfiles: [
          DirectPlayProfile(
            type: DlnaProfileType.video,
          ),
          DirectPlayProfile(
            type: DlnaProfileType.audio,
          )
        ],
        transcodingProfiles: [
          TranscodingProfile(
            audioCodec: 'aac,mp3,mp2',
            container: 'ts',
            maxAudioChannels: '2',
            protocol: MediaStreamProtocol.hls,
            type: DlnaProfileType.video,
            videoCodec: 'h264',
          ),
        ],
        containerProfiles: [],
        subtitleProfiles: [
          SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ass', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'ssa', method: SubtitleDeliveryMethod.$external),
          SubtitleProfile(format: 'pgssub', method: SubtitleDeliveryMethod.$external),
          // Picture subtitles stay in the file and the player draws them.
          //
          // A format the profile does not mention leaves the server no way to
          // deliver it, so it burns the track into the video instead - and a
          // burned-in track rules out direct play, so a DVD rip that would
          // have played untouched is transcoded end to end for its subtitle.
          SubtitleProfile(format: 'dvdsub', method: SubtitleDeliveryMethod.embed),
          SubtitleProfile(format: 'dvbsub', method: SubtitleDeliveryMethod.embed),
        ],
      );

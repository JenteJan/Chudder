import 'package:flutter/widgets.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/chapters_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_segments_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/trick_play_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';

/// Playback model for Live TV streams.
/// Key differences from DirectPlaybackModel:
/// - No seeking (isLiveStream = true)
/// - No duration tracking
/// - No playback position reporting to server
/// - Stores the LiveTvChannelDto for channel info
class LiveTvPlaybackModel extends PlaybackModel {
  final LiveTvChannelDto channel;

  /// Indicates this is a live stream (disables seeking, progress bar, etc.)
  @override
  bool get isLiveStream => true;

  LiveTvPlaybackModel({
    required this.channel,
    required super.item,
    required super.media,
    super.playbackInfo,
    super.mediaStreams,
    super.mediaSegments,
    super.chapters,
    super.trickPlay,
    super.queue,
    super.bitRateOptions,
  });

  @override
  List<SubStreamModel> get subStreams => [SubStreamModel.no(), ...mediaStreams?.subStreams ?? []];

  @override
  List<AudioStreamModel> get audioStreams => [AudioStreamModel.no(), ...mediaStreams?.audioStreams ?? []];

  @override
  Future<LiveTvPlaybackModel> setSubtitle(SubStreamModel? model, MediaControlsWrapper player) async {
    final newIndex = await player.setSubtitleTrack(model, this);
    return copyWith(mediaStreams: () => mediaStreams?.copyWith(defaultSubStreamIndex: newIndex));
  }

  @override
  Future<LiveTvPlaybackModel>? setAudio(AudioStreamModel? model, MediaControlsWrapper player) async {
    final newIndex = await player.setAudioTrack(model, this);
    return copyWith(mediaStreams: () => mediaStreams?.copyWith(defaultAudioStreamIndex: newIndex));
  }

  @override
  Future<LiveTvPlaybackModel>? setQualityOption(Map<Bitrate, bool> map) async {
    return copyWith(bitRateOptions: map);
  }

  /// Live streams don't report playback start to server
  @override
  Future<PlaybackModel?> playbackStarted(Duration position, Ref ref) async {
    return null;
  }

  /// Live streams don't report playback stop to server
  @override
  Future<PlaybackModel?> playbackStopped(Duration position, Duration? totalDuration, Ref ref) async {
    ref.read(playBackModel.notifier).update((state) => null);
    return null;
  }

  /// Live streams don't update playback position
  @override
  Future<PlaybackModel?> updatePlaybackPosition(Duration position, bool isPlaying, Ref ref) async {
    return null;
  }

  /// Live streams start from the beginning (live edge)
  @override
  Future<Duration>? startDuration() async => Duration.zero;

  @override
  LiveTvPlaybackModel? updateUserData(UserData userData) {
    return copyWith(
      item: item.copyWith(userData: userData),
    );
  }

  @override
  String toString() => 'LiveTvPlaybackModel(channel: ${channel.name}, item: $item)';

  @override
  LiveTvPlaybackModel copyWith({
    LiveTvChannelDto? channel,
    ItemBaseModel? item,
    ValueGetter<Media?>? media,
    ValueGetter<Duration>? lastPosition,
    ValueGetter<MediaStreamsModel?>? mediaStreams,
    ValueGetter<MediaSegmentsModel?>? mediaSegments,
    ValueGetter<List<Chapter>?>? chapters,
    ValueGetter<TrickPlayModel?>? trickPlay,
    List<ItemBaseModel>? queue,
    Map<Bitrate, bool>? bitRateOptions,
  }) {
    return LiveTvPlaybackModel(
      channel: channel ?? this.channel,
      item: item ?? this.item,
      media: media != null ? media() : this.media,
      mediaStreams: mediaStreams != null ? mediaStreams() : this.mediaStreams,
      mediaSegments: mediaSegments != null ? mediaSegments() : this.mediaSegments,
      chapters: chapters != null ? chapters() : this.chapters,
      trickPlay: trickPlay != null ? trickPlay() : this.trickPlay,
      queue: queue ?? this.queue,
      bitRateOptions: bitRateOptions ?? this.bitRateOptions,
    );
  }
}

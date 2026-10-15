import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/movie_model.dart';
import 'package:chudder/models/items/season_model.dart';
import 'package:chudder/models/items/series_model.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/localization_helper.dart';

/// Films and episodes join the queue of the video that is playing, the way
/// tracks join the music queue: "play next" straight after it, "add to queue"
/// at the end of what was added before.
extension VideoQueueing on ItemBaseModel {
  /// Whether this can go into the queue right now: a video is loaded (playing,
  /// paused or minimized) and this is something a video queue plays. In a
  /// SyncPlay group it goes into the group's queue, for every member.
  bool canJoinVideoQueue(WidgetRef ref) {
    if (this is! MovieModel && this is! EpisodeModel && this is! SeasonModel && this is! SeriesModel) return false;
    if (ref.read(mediaPlaybackProvider).state == VideoPlayerState.disposed) return false;
    final current = ref.read(playBackModel)?.item;
    return current != null && current is! AudioModel && current.id != id;
  }

  /// What joining the queue adds: this film or episode, or a show's or
  /// season's episodes not yet watched, in order.
  Future<List<ItemBaseModel>> _videoQueueItems(WidgetRef ref) async {
    final api = ref.read(jellyApiProvider);
    final episodes = switch (this) {
      SeriesModel series => await api.fetchEpisodeFromShow(seriesId: series.id),
      SeasonModel season => await api.fetchEpisodeFromShow(seriesId: season.seriesId, seasonId: season.id),
      _ => [this],
    };
    if (episodes.length == 1) return episodes;
    final unwatched = episodes.where((episode) => episode.userData.played != true).toList();
    return unwatched.isNotEmpty ? unwatched : episodes;
  }

  Future<void> joinVideoQueue(BuildContext context, WidgetRef ref, {required bool next}) async {
    final items = await _videoQueueItems(ref);
    if (!context.mounted) return;
    if (items.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }
    final player = ref.read(videoPlayerProvider.notifier);
    if (next) {
      await player.playNextInQueue(items);
    } else {
      await player.addToTemporaryQueue(items);
    }
    if (!context.mounted) return;
    FladderSnack.show(
      next ? context.localized.queuePlaysNext(items.length) : context.localized.queueAddedVideos(items.length),
      context: context,
    );
  }
}

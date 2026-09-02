import 'dart:async';
import 'dart:developer';
import 'dart:math' show max;

import 'package:background_downloader/background_downloader.dart';
import 'package:chopper/chopper.dart';
import 'package:collection/collection.dart';
import 'package:fladder/jellyfin/enum_models.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/chapters_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/item_shared_models.dart';
import 'package:fladder/models/items/media_segments_model.dart';
import 'package:fladder/models/items/media_streams_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/items/trick_play_model.dart';
import 'package:fladder/models/playback/direct_playback_model.dart';
import 'package:fladder/models/playback/offline_playback_model.dart';
import 'package:fladder/models/playback/playback_options_dialogue.dart';
import 'package:fladder/models/playback/playback_queue_source.dart';
import 'package:fladder/models/playback/playback_queue_state.dart';
import 'package:fladder/models/playback/transcode_playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
export 'playback_queue_source.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/models/syncing/sync_item.dart';
import 'package:fladder/models/syncplay/syncplay_models.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/profiles/default_profile.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/connectivity_provider.dart';
import 'package:fladder/providers/service_provider.dart';
import 'package:fladder/providers/settings/video_player_settings_provider.dart';
import 'package:fladder/providers/sync_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/providers/user_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/util/bitrate_helper.dart';
import 'package:fladder/util/duration_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/map_bool_helper.dart';
import 'package:fladder/util/streams_selection.dart';
import 'package:fladder/wrappers/media_control_wrapper.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

class Media {
  final String url;

  const Media({
    required this.url,
  });
}

extension PlaybackModelExtension on PlaybackModel? {
  SubStreamModel? get defaultSubStream {
    final streams = this?.subStreams;
    if (streams == null) return null;
    return streams.firstWhereOrNull((element) => element.index == this?.mediaStreams?.defaultSubStreamIndex) ??
        SubStreamModel.no();
  }

  AudioStreamModel? get defaultAudioStream {
    final streams = this?.audioStreams;
    if (streams == null) return null;
    return streams.firstWhereOrNull((element) => element.index == this?.mediaStreams?.defaultAudioStreamIndex) ??
        AudioStreamModel.no();
  }

  String? label(BuildContext context) => switch (this) {
        DirectPlaybackModel _ => PlaybackType.directStream.name(context),
        TranscodePlaybackModel _ => PlaybackType.transcode.name(context),
        OfflinePlaybackModel _ => PlaybackType.offline.name(context),
        TvPlaybackModel _ => PlaybackType.tv.name(context),
        _ => context.localized.unknown,
      };
}

class PlaybackModel {
  final ItemBaseModel item;
  final Media? media;
  final PlaybackQueueState playbackQueue;
  List<ItemBaseModel> get queue => playbackQueue.queue;
  List<ItemBaseModel> get nextUpQueue => playbackQueue.nextUpQueue;
  final PlaybackQueueSource? queueSource;
  final MediaSegmentsModel? mediaSegments;
  final PlaybackInfoResponse? playbackInfo;

  Map<Bitrate, bool> bitRateOptions;

  List<Chapter>? chapters = [];
  TrickPlayModel? trickPlay;

  Future<PlaybackModel?> updatePlaybackPosition(Duration position, bool isPlaying, Ref ref) =>
      throw UnimplementedError();

  Future<PlaybackModel?> playbackStarted(Duration position, Ref ref) => throw UnimplementedError();

  Future<PlaybackModel?> playbackStopped(Duration position, Duration? totalDuration, Ref ref) =>
      throw UnimplementedError();

  void dispose() {}

  final MediaStreamsModel? mediaStreams;

  List<SubStreamModel>? get subStreams => throw UnimplementedError();

  List<AudioStreamModel>? get audioStreams => throw UnimplementedError();

  bool get isAudioPlayback => item is AudioModel || item.type == FladderItemType.audio;

  Duration resolvedStopPosition(Duration position, Duration? totalDuration) {
    if (!isAudioPlayback) return position;
    return totalDuration ?? item.overview.runTime ?? position;
  }

  Future<Duration> resolvedStartPosition([Duration? requestedStartPosition]) async {
    if (isAudioPlayback) return Duration.zero;
    return requestedStartPosition ?? await startDuration() ?? Duration.zero;
  }

  Future<Duration>? startDuration() async => isAudioPlayback ? Duration.zero : item.userData.playBackPosition;

  PlaybackModel? updateUserData(UserData userData) => throw UnimplementedError();

  Future<PlaybackModel>? setSubtitle(SubStreamModel? model, MediaControlsWrapper player) => throw UnimplementedError();

  /// Optimistically drop a deleted external subtitle from the local model.
  /// Subclasses with media streams override; the base is a no-op.
  PlaybackModel removeSubtitle(int index) => this;

  /// Swap in a freshly listed set of subtitle streams for the current
  /// version. Subclasses with media streams override; the base is a no-op.
  PlaybackModel replaceSubtitles(List<SubStreamModel> subStreams) => this;

  Future<PlaybackModel>? setAudio(AudioStreamModel? model, MediaControlsWrapper player) => throw UnimplementedError();

  Future<PlaybackModel>? setQualityOption(Map<Bitrate, bool> map) => throw UnimplementedError();

  PlaybackModel updatePlaybackQueue(PlaybackQueueState newQueue) => throw UnimplementedError();

  ItemBaseModel? get nextVideo => playbackQueue.nextItem(item.id);
  ItemBaseModel? get previousVideo => playbackQueue.previousItem(item.id);

  PlaybackModel copyWith() => throw UnimplementedError();

  PlaybackModel({
    required this.playbackInfo,
    this.mediaStreams,
    required this.item,
    required this.media,
    List<ItemBaseModel> queue = const [],
    PlaybackQueueState? playbackQueue,
    this.queueSource,
    this.bitRateOptions = const {},
    this.mediaSegments,
    this.chapters,
    this.trickPlay,
  }) : playbackQueue = playbackQueue ??
            PlaybackQueueState.fromQueue(
              queue,
              initialItemId: item.id,
            );
}

final playbackModelHelper = Provider<PlaybackModelHelper>((ref) {
  return PlaybackModelHelper(ref: ref);
});

/// The last few shows' episode lists, briefly. Starting an episode in a
/// group asks for the show's queue twice within a second - once to set the
/// group's queue and once to build the playback model - and each was a fetch
/// of every episode of the show.
final Map<String, ({DateTime at, List<ItemBaseModel> queue})> _queueCache = {};

class PlaybackModelHelper {
  const PlaybackModelHelper({required this.ref});

  final Ref ref;

  JellyService get api => ref.read(jellyApiProvider);

  Future<void> _ensureLocalTrackSwitchAutoplay() async {
    // Poll for up to ~3 seconds, calling play() on every iteration the
    // player isn't already playing and isn't buffering. media-kit on web
    // sometimes drops the first one or two play() calls after a track
    // change or transcode reload (the underlying media isn't fully
    // ready yet, or the player is mid-transition). One-shot retries
    // weren't enough; this keeps re-issuing play until the state
    // stream confirms playing=true or we time out.
    for (var attempt = 0; attempt < 12; attempt++) {
      final playbackState = ref.read(mediaPlaybackProvider);
      if (playbackState.playing) {
        return;
      }
      if (!playbackState.buffering) {
        await ref.read(videoPlayerProvider).play();
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<PlaybackModel?> loadNewVideo(ItemBaseModel newItem) async {
    // When SyncPlay is active, route the next/previous episode through
    // the group queue using the lightweight NextItem/PreviousItem
    // endpoints (matches jellyfin-web). Determine direction from the
    // current playback model's queue and fall back to setNewQueue only
    // for non-adjacent jumps (e.g. user picked an arbitrary library item).
    if (ref.read(isSyncPlayActiveProvider)) {
      // Use the same setNewQueue flow as initial play in _playSyncPlay.
      // It reliably triggers the PlayQueue/NewPlaylist broadcast that
      // drives _startPlayback through _handlePlayQueue, so the user
      // sees the "Switching item…" overlay (SyncPlayCommandIndicator)
      // and then the new media without having to navigate away.
      //
      // NextItem/PreviousItem would preserve the server-side queue
      // context but in practice did not reliably trigger the
      // PlayQueue broadcast we rely on; setNewQueue does.
      await ref.read(syncPlayProvider.notifier).setNewQueue(
        itemIds: [newItem.id],
        playingItemPosition: 0,
        startPositionTicks: 0,
      );
      return null;
    }

    ref.read(videoPlayerProvider).pause();
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: true));
    final currentModel = ref.read(playBackModel);
    final newModel = (await createPlaybackModel(
          null,
          newItem,
          oldModel: currentModel,
        )) ??
        await _createOfflinePlaybackModel(
          newItem,
          null,
          await ref.read(syncProvider.notifier).getSyncedItem(newItem.id),
          oldModel: currentModel,
        );
    if (newModel == null) return null;
    // The new model inherits oldModel.playbackQueue verbatim, so its
    // mainQueueCurrentId still points at the episode we just left.
    // nextVideo/previousVideo anchor on that id, so without this advance
    // the auto-next overlay keeps offering the episode that is already
    // playing and re-loads it from the start.
    final advancedQueue = currentModel?.playbackQueue.advanceFromCurrentTo(currentModel.item.id, newItem.id);
    final modelToLoad = advancedQueue != null ? newModel.updatePlaybackQueue(advancedQueue) : newModel;
    ref.read(videoPlayerProvider.notifier).loadPlaybackItem(modelToLoad, Duration.zero);
    return modelToLoad;
  }

  Future<void> loadTVChannel(ChannelModel? channel) async {
    if (channel == null) return;
    ref.read(videoPlayerProvider).pause();
    ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(buffering: true));
    final currentModel = ref.read(playBackModel);

    PlaybackModel? serverModel;
    try {
      serverModel = await createPlaybackModel(
        null,
        channel,
        forcedPlaybackType: PlaybackType.tv,
        oldModel: currentModel,
      ).timeout(const Duration(seconds: 8), onTimeout: () {
        return null;
      });
    } catch (e) {
      serverModel = null;
    }

    final newModel = serverModel ??
        await _createOfflinePlaybackModel(
          channel,
          null,
          await ref.read(syncProvider.notifier).getSyncedItem(channel.id),
          oldModel: currentModel,
        );

    if (newModel == null) return;
    ref.read(videoPlayerProvider.notifier).loadPlaybackItem(newModel, Duration.zero);
  }

  Future<OfflinePlaybackModel?> _createOfflinePlaybackModel(
    ItemBaseModel item,
    MediaStreamsModel? streamModel,
    SyncedItem? syncedItem, {
    PlaybackModel? oldModel,
    PlaybackQueueSource? queueSource,
  }) async {
    final ItemBaseModel? syncedItemModel = syncedItem?.itemModel;
    if (syncedItemModel == null || syncedItem == null || !await syncedItem.videoFile.exists()) return null;

    final children = await ref.read(syncProvider.notifier).getSiblings(syncedItem);

    final syncedItems = children.where((element) => element.videoFile.existsSync()).toList();
    final itemQueue = syncedItems.map((e) => e.itemModel).nonNulls;

    return OfflinePlaybackModel(
      item: syncedItemModel,
      syncedItem: syncedItem,
      trickPlay: syncedItem.trickPlayModel,
      mediaSegments: syncedItem.mediaSegments,
      media: Media(url: syncedItem.videoFile.path),
      queue: itemQueue.nonNulls.toList(),
      playbackQueue: oldModel?.playbackQueue,
      queueSource: queueSource ?? oldModel?.queueSource,
      syncedQueue: children,
      mediaStreams: item.streamModel ?? syncedItemModel.streamModel,
    );
  }

  /// The whole playback model built from the sync database alone: no queue
  /// fetch, no item fetch, nothing that needs the server.
  ///
  /// [createPlaybackModel] asks the server for the queue and for the full
  /// item before it ever looks at what has been downloaded, so with the
  /// network off both calls threw and a downloaded episode ended at
  /// "unable to play media" — with the file sitting on disk the whole time.
  Future<OfflinePlaybackModel?> _createLocalOnlyPlaybackModel(
    ItemBaseModel item, {
    PlaybackModel? oldModel,
    List<ItemBaseModel>? libraryQueue,
    PlaybackQueueSource? queueSource,
  }) async {
    final syncNotifier = ref.read(syncProvider.notifier);

    // A show or a season is not itself playable: pick the same next-up
    // episode the online path picks, but out of what has been downloaded.
    ItemBaseModel? target = item;
    if (item is SeriesModel || item is SeasonModel) {
      final queue = oldModel?.queue ?? libraryQueue ?? await _collectLocalQueue(item);
      target = queue.whereType<EpisodeModel>().toList().nextUp;
    }

    if (target == null) return null;

    return _createOfflinePlaybackModel(
      target,
      target.streamModel,
      await syncNotifier.getSyncedItem(target.id),
      oldModel: oldModel,
      queueSource: queueSource,
    );
  }

  /// The episodes of [item] that are on disk, for the offline path's queue.
  /// Mirrors [collectQueue] with the sync database standing in for the server.
  Future<List<ItemBaseModel>> _collectLocalQueue(ItemBaseModel item) async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final synced = await syncNotifier.getSyncedItem(item.id);
    if (synced == null) return [];
    return (await syncNotifier.getNestedChildren(synced)).map((e) => e.itemModel).nonNulls.toList();
  }

  Future<PlaybackModel?> createPlaybackModel(
    BuildContext? context,
    ItemBaseModel? item, {
    PlaybackModel? oldModel,
    List<ItemBaseModel>? libraryQueue,
    PlaybackQueueSource? queueSource,
    bool showPlaybackOptions = false,
    PlaybackType? forcedPlaybackType,
    Duration? startPosition,
  }) async {
    try {
      if (item == null) return null;
      final userId = ref.read(userProvider)?.id;
      if (userId?.isEmpty == true) return null;

      // Before the queue fetch, not after it. Both of the calls below need the
      // server, and offline they don't fail fast — the API interceptor retries
      // a connection error twice with backoff first — so the user waited out
      // several seconds of that before being told the episode in their pocket
      // could not be played.
      if (ref.read(offlineStateProvider)) {
        return await _createLocalOnlyPlaybackModel(
          item,
          oldModel: oldModel,
          libraryQueue: libraryQueue,
          queueSource: queueSource,
        );
      }

      // The queue is the rest of the series, and only a show or a season
      // needs it before it knows what to play first. For an episode or a film
      // it is fetched alongside the item rather than in front of it - it is
      // the larger of the two requests, for buttons nobody has pressed yet.
      final knownQueue = oldModel?.queue ?? libraryQueue;
      final queueRequest = knownQueue != null ? Future.value(knownQueue) : collectQueue(item);
      queueRequest.ignore();
      final effectiveQueueSource = oldModel?.queueSource ?? queueSource;

      final firstItemToPlay = switch (item) {
        SeriesModel _ || SeasonModel _ => ((await queueRequest).whereType<EpisodeModel>().toList().nextUp),
        _ => item,
      };

      if (firstItemToPlay == null) return null;

      final fullItemRequest = api.usersUserIdItemsItemIdGet(itemId: firstItemToPlay.id);
      final syncedItemRequest = ref.read(syncProvider.notifier).getSyncedItem(firstItemToPlay.id);
      syncedItemRequest.ignore();

      final fullItem = (await fullItemRequest).body;
      final queue = await queueRequest;

      if (fullItem == null) {
        // The server answered with nothing. A downloaded copy still plays.
        return await _createLocalOnlyPlaybackModel(
          item,
          oldModel: oldModel,
          libraryQueue: queue,
          queueSource: effectiveQueueSource,
        );
      }

      SyncedItem? syncedItem = await syncedItemRequest;

      final firstItemIsSynced = syncedItem != null && syncedItem.status == TaskStatus.complete;

      final actualStartPosition = startPosition ?? fullItem.userData.playBackPosition;

      final options = {
        PlaybackType.directStream,
        PlaybackType.transcode,
        if (firstItemIsSynced) PlaybackType.offline,
      };

      final isOffline = ref.read(offlineStateProvider);

      if (firstItemToPlay is AudioModel && firstItemIsSynced) {
        final offlinePlayback = await _createOfflinePlaybackModel(
          fullItem,
          item.streamModel,
          syncedItem,
          oldModel: oldModel,
          queueSource: effectiveQueueSource,
        );

        if (offlinePlayback != null) {
          return offlinePlayback;
        }
      }

      Future<PlaybackModel?> getOfflineModel() => _createOfflinePlaybackModel(
            fullItem,
            item.streamModel,
            syncedItem,
            oldModel: oldModel,
            queueSource: effectiveQueueSource,
          );

      Future<PlaybackModel?> getServerModel(PlaybackType type) => _createServerPlaybackModel(
            fullItem,
            item.streamModel,
            forcedPlaybackType ?? type,
            oldModel: oldModel,
            libraryQueue: queue,
            queueSource: effectiveQueueSource,
            startPosition: actualStartPosition,
          );

      if (((showPlaybackOptions || firstItemIsSynced) && !isOffline) && context != null) {
        final playbackType = await showPlaybackTypeSelection(
          context: context,
          options: options,
        );

        if (!context.mounted) return null;

        return switch (playbackType) {
          PlaybackType.directStream || PlaybackType.transcode || PlaybackType.tv => await getServerModel(playbackType!),
          PlaybackType.offline => await getOfflineModel(),
          null => null,
        };
      }

      if (isOffline) {
        return await getOfflineModel();
      }

      return await getServerModel(PlaybackType.directStream) ?? await getOfflineModel();
    } catch (e) {
      log("Error creating playback model: ${e.toString()}");
      // Usually the server going away mid-request, which the connectivity
      // probe only notices seconds later. Until it does, this is the only
      // thing standing between the user and a file already on their disk.
      if (item == null) return null;
      return await _createLocalOnlyPlaybackModel(
        item,
        oldModel: oldModel,
        libraryQueue: libraryQueue,
        queueSource: queueSource,
      );
    }
  }

  Future<PlaybackModel?> _createServerPlaybackModel(
    ItemBaseModel item,
    MediaStreamsModel? streamModel,
    PlaybackType? type, {
    PlaybackModel? oldModel,
    required List<ItemBaseModel> libraryQueue,
    PlaybackQueueSource? queueSource,
    Duration? startPosition,
  }) async {
    try {
      final userId = ref.read(userProvider)?.id;
      if (userId?.isEmpty == true) return null;

      // An item picked out of a list carries no sources of its own — a show's
      // episodes are fetched without them, being megabytes of detail about
      // episodes nobody opened — so an empty model has to fall through to the
      // full item, which was just fetched and always has them. It used to fall
      // through only on a null one, and empty is what a list hands over.
      final newStreamModel =
          streamModel?.versionStreams.isNotEmpty == true ? streamModel : (item.streamModel ?? streamModel);

      Map<Bitrate, bool> qualityOptions = getVideoQualityOptions(
        VideoQualitySettings(
          maxBitRate: ref.read(videoPlayerSettingsProvider.select((value) => value.maxHomeBitrate)),
          videoBitRate: newStreamModel?.videoStreams.firstOrNull?.bitRate ?? 0,
          videoCodec: newStreamModel?.videoStreams.firstOrNull?.codec,
        ),
      );

      final audioStreamIndex = selectAudioStream(
          ref.read(userProvider.select((value) => value?.userConfiguration?.rememberAudioSelections ?? true)),
          oldModel?.mediaStreams?.currentAudioStream,
          newStreamModel?.audioStreams,
          newStreamModel?.defaultAudioStreamIndex);

      final subStreamIndex = selectSubStream(
          ref.read(userProvider.select((value) => value?.userConfiguration?.rememberSubtitleSelections ?? true)),
          oldModel?.mediaStreams?.currentSubStream,
          newStreamModel?.subStreams,
          newStreamModel?.defaultSubStreamIndex);

//Native player does not allow for loading external subtitles with transcoding
      final isNativePlayer =
          ref.read(videoPlayerSettingsProvider.select((value) => value.wantedPlayer == PlayerOptions.nativePlayer));
      final isExternalSub = newStreamModel?.currentSubStream?.isExternal == true;

      // Neither depends on the playback info, so they travel with it rather
      // than after it. Skip markers matter seconds in, trickplay only when
      // the scrubber is hovered; both used to hold the first frame.
      final mediaSegmentsRequest = api.mediaSegmentsGet(id: item.id);
      mediaSegmentsRequest.ignore();
      final trickPlayRequest = api.getTrickPlay(item: item, ref: ref);
      trickPlayRequest.ignore();

      final Response<PlaybackInfoResponse> response = await api.itemsItemIdPlaybackInfoPost(
        itemId: item.id,
        body: PlaybackInfoDto(
          startTimeTicks: startPosition?.toRuntimeTicks,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subStreamIndex,
          enableTranscoding: true,
          autoOpenLiveStream: true,
          deviceProfile: type != PlaybackType.tv ? ref.read(videoProfileProvider) : null,
          userId: userId,
          enableDirectPlay: type != PlaybackType.transcode,
          enableDirectStream: type != PlaybackType.transcode,
          alwaysBurnInSubtitleWhenTranscoding: isNativePlayer && isExternalSub,
          maxStreamingBitrate: qualityOptions.enabledFirst.keys.firstOrNull?.bitRate,
          mediaSourceId: newStreamModel?.currentVersionStream?.id,
        ),
      );

      PlaybackInfoResponse? playbackInfo = response.body;

      if (playbackInfo == null) {
        return null;
      }

      final mediaSource = playbackInfo.mediaSources?[newStreamModel?.versionStreamIndex ?? 0];

      if (mediaSource == null) {
        return null;
      }

      final mediaStreamsWithUrls = MediaStreamsModel.fromMediaStreamsList(playbackInfo.mediaSources, ref).copyWith(
        defaultAudioStreamIndex: audioStreamIndex,
        defaultSubStreamIndex: subStreamIndex,
      );

      final mediaSegments = await mediaSegmentsRequest;
      final trickPlayResp = await trickPlayRequest;

      final trickPlay = trickPlayResp?.body;
      final chapters = item.overview.chapters ?? [];

      final mediaPath = isValidVideoUrl(mediaSource.path ?? "");

      if (type == PlaybackType.tv && mediaPath != null) {
        final tvModel = TvPlaybackModel(
          channel: item as ChannelModel,
          isNativePlayerBackend: isNativePlayer,
          item: item,
          queue: libraryQueue,
          playbackQueue: oldModel?.playbackQueue,
          queueSource: queueSource,
          playbackInfo: playbackInfo,
          media: Media(url: mediaPath),
        );
        return tvModel;
      }

      if ((mediaSource.supportsDirectStream ?? false) || (mediaSource.supportsDirectPlay ?? false)) {
        final Map<String, String?> directOptions = {
          'Static': 'true',
          'mediaSourceId': mediaSource.id,
          ...authQueryParameters(ref.read(userProvider)?.credentials.token),
        };

        if (mediaSource.eTag != null) {
          directOptions['Tag'] = mediaSource.eTag;
        }

        if (mediaSource.liveStreamId != null) {
          directOptions['LiveStreamId'] = mediaSource.liveStreamId;
        }

        final playbackUrl = buildServerUrl(
          ref,
          pathSegments: ['Videos', mediaSource.id!, 'stream'],
          queryParameters: directOptions,
        );

        return DirectPlaybackModel(
          item: item,
          queue: libraryQueue,
          playbackQueue: oldModel?.playbackQueue,
          queueSource: queueSource,
          mediaSegments: mediaSegments?.body,
          chapters: chapters,
          playbackInfo: playbackInfo,
          trickPlay: trickPlay,
          media: Media(url: mediaPath ?? playbackUrl),
          mediaStreams: mediaStreamsWithUrls,
          bitRateOptions: qualityOptions,
        );
      } else if ((mediaSource.supportsTranscoding ?? false) && mediaSource.transcodingUrl != null) {
        return TranscodePlaybackModel(
          item: item,
          queue: libraryQueue,
          playbackQueue: oldModel?.playbackQueue,
          queueSource: queueSource,
          mediaSegments: mediaSegments?.body,
          chapters: chapters,
          trickPlay: trickPlay,
          playbackInfo: playbackInfo,
          media: Media(url: buildServerUrl(ref, relativeUrl: mediaSource.transcodingUrl)),
          mediaStreams: mediaStreamsWithUrls,
          bitRateOptions: qualityOptions,
        );
      }
      return null;
    } catch (e) {
      log(e.toString());
      return null;
    }
  }

  String? isValidVideoUrl(String path) {
    Uri? uri = Uri.tryParse(path);
    return (uri != null && uri.hasScheme && uri.hasAuthority) ? path : null;
  }

  Future<List<ItemBaseModel>> collectQueue(ItemBaseModel model) async {
    switch (model) {
      case EpisodeModel _:
      case SeriesModel _:
      case SeasonModel _:
        final cached = _queueCache[model.streamId];
        if (cached != null && DateTime.now().difference(cached.at) < const Duration(seconds: 10)) {
          return List.of(cached.queue);
        }
        List<EpisodeModel> episodeList = ((await fetchEpisodesFromSeries(model.streamId)).body ?? [])
          ..removeWhere((element) => element.status != EpisodeStatus.available);
        if (_queueCache.length > 4) _queueCache.remove(_queueCache.keys.first);
        _queueCache[model.streamId] = (at: DateTime.now(), queue: List<ItemBaseModel>.of(episodeList));
        return episodeList;
      default:
        return [];
    }
  }

  Future<Response<List<EpisodeModel>>> fetchEpisodesFromSeries(String seriesId) async {
    // Without streams or sources. These episodes are the queue - what is
    // next, what was before - and each is fetched in full again when its
    // turn comes. With them, a long show was a response of megabytes in
    // front of every episode's first frame.
    final response = await api.showsSeriesIdEpisodesGet(
      seriesId: seriesId,
      fields: [
        ItemFields.overview,
        ItemFields.originaltitle,
        ItemFields.mediasourcecount,
        ItemFields.width,
        ItemFields.height,
      ],
    );
    return Response(response.base, (response.body?.items?.map((e) => EpisodeModel.fromBaseDto(e, ref)).toList() ?? []));
  }

  /// Re-lists the item's subtitle streams from the server and swaps them into
  /// the live playback model without touching playback - the picker updates,
  /// the player keeps going. Returns the streams that were not listed before,
  /// or null when this playback cannot be refreshed (offline, live TV).
  ///
  /// With [scanServer] an admin account first asks the server to scan the
  /// item for new files, which is what makes a subtitle dropped next to the
  /// media by Bazarr (or by hand) show up. The server lists a just-downloaded
  /// subtitle only once its own metadata refresh has run, so [attempts] polls
  /// spaced by [retryDelay] until something new appears.
  Future<List<SubStreamModel>?> refreshSubtitleStreams(
    PlaybackModel playbackModel, {
    bool scanServer = false,
    int attempts = 1,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    if (playbackModel is OfflinePlaybackModel || playbackModel is TvPlaybackModel) return null;
    if (ref.read(videoPlayerProvider).isCasting) return null;
    final userId = ref.read(userProvider)?.id;
    if (userId == null || userId.isEmpty) return null;
    final current = playbackModel.mediaStreams;
    if (current == null) return null;

    if (scanServer && (ref.read(userProvider)?.policy?.isAdministrator ?? false)) {
      await ref.read(userProvider.notifier).refreshMetaData(
            playbackModel.item.id,
            metadataRefreshMode: MetadataRefresh.defaultRefresh,
          );
    }

    String key(SubStreamModel sub) => '${sub.isExternal}|${sub.language}|${sub.codec}|${sub.displayTitle}';
    final before = current.subStreams;
    final known = before.map(key).toSet();

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      final response = await api.itemsItemIdPlaybackInfoPost(
        itemId: playbackModel.item.id,
        body: PlaybackInfoDto(
          userId: userId,
          audioStreamIndex: current.defaultAudioStreamIndex,
          subtitleStreamIndex: current.defaultSubStreamIndex,
          enableDirectPlay: true,
          enableDirectStream: true,
          enableTranscoding: true,
          deviceProfile: ref.read(videoProfileProvider),
          mediaSourceId: current.currentVersionStream?.id,
        ),
      );
      final sources = response.body?.mediaSources;
      if (sources == null || sources.isEmpty) continue;
      final fresh = MediaStreamsModel.fromMediaStreamsList(sources, ref).subStreams;

      var added = fresh.where((sub) => !known.contains(key(sub))).toList();
      if (added.isEmpty && fresh.length > before.length) {
        // Same titles, more files: a second copy of a language. The new
        // external files sort last, so those are the ones that arrived.
        final externals = fresh.where((sub) => sub.isExternal).toList();
        added = externals.skip(max(0, externals.length - (fresh.length - before.length))).toList();
      }

      final isLast = attempt == attempts - 1;
      if (added.isNotEmpty || isLast) {
        final latest = ref.read(playBackModel);
        if (latest != null && latest.item.id == playbackModel.item.id) {
          ref.read(playBackModel.notifier).update((_) => latest.replaceSubtitles(fresh));
        }
        return added;
      }
    }
    return const [];
  }

  Future<void> shouldReload(
    PlaybackModel playbackModel, {
    bool isLocalTrackSwitch = false,
  }) async {
    if (playbackModel is OfflinePlaybackModel) {
      return;
    }

    // While casting, the remote player rebuilds its own stream on track/quality
    // changes (the Jellyfin receiver via changeStream; DLNA/AirPlay by resolving
    // a fresh URL and reloading). The local stop-and-reload below would build a
    // stream for the *local* device profile and fight the cast, so skip it.
    if (ref.read(videoPlayerProvider).isCasting) {
      return;
    }

    final item = playbackModel.item;

    final userId = ref.read(userProvider)?.id;
    if (userId?.isEmpty == true) return;

    // Check if syncplay is active and get position from syncplay if so
    final isSyncPlayActive = ref.read(isSyncPlayActiveProvider);
    final Duration currentPosition;

    final shouldReportGroupBuffering = (isSyncPlayActive && !isLocalTrackSwitch);

    if (isSyncPlayActive) {
      // Set reloading state in the player notifier to prevent premature ready reporting
      ref.read(videoPlayerProvider.notifier).setReloading(
            true,
            reportToSyncPlay: shouldReportGroupBuffering,
          );

      // Estimate the live group position rather than using the stale
      // SyncPlayState.positionTicks (which is frozen at the last server
      // event). Without this the local player reloads at an old position
      // and the drift correction immediately SkipToSyncs forward, producing
      // a visible jump after every audio/subtitle switch.
      final positionTicks = ref.read(syncPlayProvider.notifier).estimateCurrentGroupPositionTicks();
      currentPosition = Duration(milliseconds: ticksToMilliseconds(positionTicks));

      if (shouldReportGroupBuffering) {
        // Report buffering BEFORE stop/reload only when this reload should
        // affect group flow.
        await ref.read(syncPlayProvider.notifier).reportBuffering();
      }
    } else {
      currentPosition = ref.read(mediaPlaybackProvider.select((value) => value.position));
    }

    final audioIndex = selectAudioStream(
        ref.read(userProvider.select((value) => value?.userConfiguration?.rememberAudioSelections ?? true)),
        playbackModel.mediaStreams?.currentAudioStream,
        playbackModel.audioStreams,
        playbackModel.mediaStreams?.defaultAudioStreamIndex);
    final subIndex = selectSubStream(
        ref.read(userProvider.select((value) => value?.userConfiguration?.rememberSubtitleSelections ?? true)),
        playbackModel.mediaStreams?.currentSubStream,
        playbackModel.subStreams,
        playbackModel.mediaStreams?.defaultSubStreamIndex);

    Response<PlaybackInfoResponse> response = await api.itemsItemIdPlaybackInfoPost(
      itemId: item.id,
      body: PlaybackInfoDto(
        startTimeTicks: currentPosition.toRuntimeTicks,
        audioStreamIndex: audioIndex,
        enableDirectPlay: true,
        enableDirectStream: true,
        subtitleStreamIndex: subIndex,
        enableTranscoding: true,
        autoOpenLiveStream: true,
        deviceProfile: ref.read(videoProfileProvider),
        userId: userId,
        maxStreamingBitrate: playbackModel.bitRateOptions.enabledFirst.entries.firstOrNull?.key.bitRate,
        mediaSourceId: playbackModel.mediaStreams?.currentVersionStream?.id,
      ),
    );

    PlaybackInfoResponse playbackInfo = response.bodyOrThrow;

    final mediaSource = playbackInfo.mediaSources?.first;

    final mediaStreamsWithUrls = MediaStreamsModel.fromMediaStreamsList(playbackInfo.mediaSources, ref).copyWith(
      defaultAudioStreamIndex: audioIndex,
      defaultSubStreamIndex: subIndex,
    );

    if (mediaSource == null) return;

    PlaybackModel? newModel;

    if ((mediaSource.supportsDirectStream ?? false) || (mediaSource.supportsDirectPlay ?? false)) {
      final Map<String, String?> directOptions = {
        'Static': 'true',
        'mediaSourceId': mediaSource.id,
        ...authQueryParameters(ref.read(userProvider)?.credentials.token),
      };

      if (mediaSource.eTag != null) {
        directOptions['Tag'] = mediaSource.eTag;
      }

      if (mediaSource.liveStreamId != null) {
        directOptions['LiveStreamId'] = mediaSource.liveStreamId;
      }

      final directPlay = buildServerUrl(
        ref,
        pathSegments: ['Videos', mediaSource.id ?? '', 'stream'],
        queryParameters: directOptions,
      );

      final mediaPath = isValidVideoUrl(mediaSource.path ?? "");

      newModel = DirectPlaybackModel(
        item: playbackModel.item,
        queue: playbackModel.queue,
        playbackQueue: playbackModel.playbackQueue,
        mediaSegments: playbackModel.mediaSegments,
        chapters: playbackModel.chapters,
        playbackInfo: playbackInfo,
        trickPlay: playbackModel.trickPlay,
        media: Media(url: mediaPath ?? directPlay),
        mediaStreams: mediaStreamsWithUrls,
        bitRateOptions: playbackModel.bitRateOptions,
      );
    } else if ((mediaSource.supportsTranscoding ?? false) && mediaSource.transcodingUrl != null) {
      newModel = TranscodePlaybackModel(
        item: playbackModel.item,
        queue: playbackModel.queue,
        playbackQueue: playbackModel.playbackQueue,
        mediaSegments: playbackModel.mediaSegments,
        chapters: playbackModel.chapters,
        playbackInfo: playbackInfo,
        trickPlay: playbackModel.trickPlay,
        media: Media(url: buildServerUrl(ref, relativeUrl: mediaSource.transcodingUrl)),
        mediaStreams: mediaStreamsWithUrls,
        bitRateOptions: playbackModel.bitRateOptions,
      );
    }
    if (newModel == null) {
      if (isSyncPlayActive) {
        ref.read(videoPlayerProvider.notifier).setReloading(false);
      }
      return;
    }
    if (newModel.runtimeType != playbackModel.runtimeType || newModel is TranscodePlaybackModel) {
      await ref.read(videoPlayerProvider.notifier).loadPlaybackItem(
            newModel,
            currentPosition,
            waitForSyncPlayCommand: shouldReportGroupBuffering,
          );
      if (isLocalTrackSwitch) {
        await _ensureLocalTrackSwitchAutoplay();
      }
    } else if (isSyncPlayActive) {
      // If we didn't call loadPlaybackItem, we must reset reloading state
      ref.read(videoPlayerProvider.notifier).setReloading(
            false,
            reportToSyncPlay: false,
          );
      if (isLocalTrackSwitch) {
        await _ensureLocalTrackSwitchAutoplay();
      }
    }
  }
}

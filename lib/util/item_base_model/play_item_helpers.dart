import 'dart:developer';
import 'dart:math' show Random, min;

import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';

import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/album_model.dart';
import 'package:fladder/models/items/artist_model.dart';
import 'package:fladder/models/items/audio_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/photos_model.dart';
import 'package:fladder/models/items/playlist_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/playback/playback_model.dart';
import 'package:fladder/models/playback/tv_playback_model.dart';
import 'package:fladder/models/video_stream_model.dart';
import 'package:fladder/providers/api_provider.dart';
import 'package:fladder/providers/book_viewer_provider.dart';
import 'package:fladder/providers/items/book_details_provider.dart';
import 'package:fladder/providers/syncplay/syncplay_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/screens/book_viewer/book_viewer_screen.dart';
import 'package:fladder/screens/library_search/widgets/library_play_options_.dart';
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:fladder/widgets/shared/tv_dialog_frame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart' as logging;
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:square_progress_indicator/square_progress_indicator.dart';

import '../../models/syncplay/syncplay_models.dart';

part 'play_playlist_helpers.dart';

extension BookBaseModelExtension on BookModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    if (kIsWeb) {
      FladderSnack.show(context.localized.unableToPlayBooksOnWeb, context: context);
      return;
    }
    if (this == null) {
      return;
    }
    var newProvider = provider;

    if (newProvider == null) {
      newProvider = bookDetailsProvider(this?.id ?? "");
      await ref.watch(bookDetailsProvider(this?.id ?? "").notifier).fetchDetails(this!);
    }

    ref.read(bookViewerProvider.notifier).fetchBook(this);
    await openBookViewer(
      context,
      newProvider,
      initialPage: currentPage ?? this?.currentPage,
    );
    parentContext?.refreshData();
    if (context.mounted) {
      await context.refreshData();
    }
  }
}

extension PhotoAlbumExtension on PhotoAlbumModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    final albumModel = this;
    if (albumModel == null) return;

    final api = ref.read(jellyApiProvider);
    final op = CancelableOperation.fromFuture(api.itemsGet(
        parentId: albumModel.id,
        includeItemTypes: FladderItemType.galleryItem.map((e) => e.dtoKind).expand((e) => e).toList(),
        recursive: true));

    _showLoadingIndicator(context, albumModel, op);

    final getChildItems = await op.valueOrCancellation(null);
    if (op.isCanceled || getChildItems == null) {
      if (!op.isCanceled) {
        log('unableToPlayMedia [PhotoAlbumModel.play]: '
            'getChildItems was null for album=${albumModel.id}');
        _closeLoadingDialog(context);
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final photos = getChildItems.body?.items.whereType<PhotoModel>() ?? [];

    _closeLoadingDialog(context);

    if (photos.isEmpty) {
      return;
    }

    await context.pushRoute(PhotoViewerRoute(
      items: photos.toList(),
    ));

    if (context.mounted) {
      await context.refreshData();
    }
    return;
  }
}

extension ChannelModelExtension on ChannelModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    int? currentPage,
    AutoDisposeStateNotifierProvider<BookDetailsProviderNotifier, BookProviderModel>? provider,
    BuildContext? parentContext,
  }) async {
    if (this == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          this,
          forcedPlaybackType: PlaybackType.tv,
          showPlaybackOptions: false,
          startPosition: Duration.zero,
        ));

    _showLoadingIndicator(context, this!, op);

    final model = await op.valueOrCancellation(null);

    if (op.isCanceled || model == null) {
      if (!op.isCanceled) {
        log('unableToPlayMedia [ChannelModel.play]: '
            'createPlaybackModel returned null for channel=${this!.id}');
        _closeLoadingDialog(context);
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    if (model is! TvPlaybackModel) {
      return;
    }

    await _playVideo(
      context,
      startPosition: Duration.zero,
      current: model.copyWith(
        channel: this,
      ),
      ref: ref,
      cancelOperation: op,
    );
  }
}

extension AudioModelAudioPlayback on AudioModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final audio = this;
    if (audio == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = await _fetchAudioTrackQueue(audio, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final currentIndex = queue.indexWhere((element) => element.id == audio.id).clamp(0, queue.length - 1);
    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          audio,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension PlayQueueSource on PlaybackQueueSource? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final queueSource = this;
    if (queueSource == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = await queueSource.fetchQueue(ref.read);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          queue.firstOrNull,
          libraryQueue: queue,
          queueSource: queueSource,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension ArtistModelLatestTracksPlayback on ArtistModel? {
  Future<void> playLatestTracks(
    BuildContext context,
    WidgetRef ref, {
    AudioModel? startTrack,
    Duration? startPosition,
    bool showPlaybackOption = false,
    bool? shuffleEnabled,
  }) async {
    final artist = this;
    if (artist == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    if (shuffleEnabled != null) {
      ref.read(mediaPlaybackProvider.notifier).update((s) => s.copyWith(shuffleEnabled: shuffleEnabled));
    }

    final queueSource = ArtistCatalogQueueSource(artistId: artist.id, limit: 300);
    final queue = await queueSource.fetchQueue(ref.read);

    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final selectedItem = startTrack != null
        ? queue.firstWhereOrNull((element) => element.id == startTrack.id) ?? queue.first
        : (shuffleEnabled == true && queue.length > 1)
            ? queue[Random().nextInt(queue.length)]
            : queue.first;
    final currentIndex = queue.indexWhere((element) => element.id == selectedItem.id).clamp(0, queue.length - 1);

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          selectedItem,
          libraryQueue: queue,
          queueSource: queueSource,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }
}

extension AudioModelListPlayback on List<AudioModel> {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = cast<ItemBaseModel>().toList();

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          queue.first,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          0,
          actualStartPosition,
        );
  }
}

extension AlbumModelInstantMixPlayback on AlbumModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final album = this;
    if (album == null) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final queue = await _fetchAlbumQueue(album, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          queue.first,
          libraryQueue: queue,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled && !showPlaybackOption) {
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          queue,
          currentIndex,
          actualStartPosition,
        );
  }

  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final album = this;
    if (album == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: AlbumInstantMixQueueSource(albumId: album.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }

  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final album = this;
    if (album == null) return;

    final queue = await _fetchAlbumQueue(album, ref);
    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue(queue);
    if (context.mounted) {
      FladderSnack.show(context.localized.addedToQueue(queue.length), context: context);
    }
  }
}

extension ArtistModelInstantMixPlayback on ArtistModel? {
  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final artist = this;
    if (artist == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: ArtistInstantMixQueueSource(artistId: artist.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }
}

extension AudioModelInstantMixPlayback on AudioModel? {
  Future<void> playInstantMix(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    final audio = this;
    if (audio == null) return;

    await _playInstantMix(
      context,
      ref,
      queueSource: AudioInstantMixQueueSource(audioId: audio.id, limit: 50),
      startPosition: startPosition,
      showPlaybackOption: showPlaybackOption,
    );
  }
}

extension AudioModelAddToQueue on AudioModel? {
  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final audio = this;
    if (audio == null) return;

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue([audio]);
    FladderSnack.show(context.localized.addedToQueue(1), context: context);
  }
}

extension ArtistModelAddToQueue on ArtistModel? {
  Future<void> addToQueue(BuildContext context, WidgetRef ref) async {
    final artist = this;
    if (artist == null) return;

    final queueSource = ArtistCatalogQueueSource(artistId: artist.id, limit: 300);
    final queue = await queueSource.fetchQueue(ref.read);

    if (queue.isEmpty) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    await ref.read(videoPlayerProvider.notifier).addToTemporaryQueue(queue);
    if (context.mounted) {
      FladderSnack.show(context.localized.addedToQueue(queue.length), context: context);
    }
  }
}

Future<List<ItemBaseModel>> _fetchAlbumQueue(AlbumModel album, WidgetRef ref) async {
  final response = await ref.read(jellyApiProvider).itemsGet(
        parentId: album.id,
        includeItemTypes: [BaseItemKind.audio],
        enableUserData: true,
        enableImages: true,
        imageTypeLimit: 1,
        fields: [ItemFields.primaryimageaspectratio, ItemFields.mediasources, ItemFields.mediastreams],
        sortBy: [ItemSortBy.sortname, ItemSortBy.parentindexnumber],
        sortOrder: [SortOrder.ascending],
        limit: 200,
      );

  final tracks = response.body?.items.whereType<AudioModel>().toList() ?? [];
  return tracks;
}

Future<List<ItemBaseModel>> _fetchAudioTrackQueue(AudioModel audio, WidgetRef ref) async {
  final albumId = audio.albumId ?? audio.parentId;
  if (albumId == null || albumId.isEmpty) {
    return [audio];
  }

  final response = await ref.read(jellyApiProvider).itemsGet(
        parentId: albumId,
        includeItemTypes: [BaseItemKind.audio],
        enableUserData: true,
        enableImages: true,
        imageTypeLimit: 1,
        fields: [ItemFields.primaryimageaspectratio, ItemFields.mediasources, ItemFields.mediastreams],
        sortBy: [ItemSortBy.sortname, ItemSortBy.parentindexnumber],
        sortOrder: [SortOrder.ascending],
        limit: 200,
      );

  final tracks = response.body?.items.whereType<AudioModel>().toList() ?? [];

  if (tracks.isEmpty) {
    return [audio];
  }
  return tracks;
}

Future<void> _playInstantMix(
  BuildContext context,
  WidgetRef ref, {
  required PlaybackQueueSource queueSource,
  Duration? startPosition,
  bool showPlaybackOption = false,
}) async {
  await ref.read(videoPlayerProvider.notifier).init();

  final queue = await queueSource.fetchQueue(ref.read);
  if (queue.isEmpty) {
    FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    return;
  }

  final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
        context,
        queue.first,
        libraryQueue: queue,
        queueSource: queueSource,
        showPlaybackOptions: showPlaybackOption,
        startPosition: startPosition,
      ));

  final model = await op.valueOrCancellation(null);
  if (op.isCanceled || model == null) {
    if (!op.isCanceled && !showPlaybackOption) {
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    }
    return;
  }

  final currentIndex = queue.indexWhere((element) => element.id == model.item.id).clamp(0, queue.length - 1);
  final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

  await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
        model,
        queue,
        currentIndex,
        actualStartPosition,
      );
}

extension ItemBaseModelExtensions on ItemBaseModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async =>
      switch (this) {
        PhotoAlbumModel album => album.play(context, ref),
        AlbumModel album => album.play(context, ref),
        AudioModel audio => audio.play(context, ref),
        ArtistModel artist => artist.playLatestTracks(context, ref),
        PlaylistModel playlist => playlist.play(
            context,
            ref,
            startPosition: startPosition,
            showPlaybackOption: showPlaybackOption,
          ),
        BookModel book => book.play(context, ref),
        ChannelModel channel => channel.play(context, ref),
        _ => _default(context, this, ref, startPosition: startPosition, showPlaybackOption: showPlaybackOption),
      };

  Future<void> _default(
    BuildContext context,
    ItemBaseModel? itemModel,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async {
    if (itemModel == null) return;

    // Already playing this, minimized: bring it back rather than start it
    // over. Only for a plain play - a position or a choice of playback type
    // is a request to load it afresh. Before the SyncPlay branch on purpose:
    // in a group this used to set the group's queue to the item it was
    // already playing, which threw everyone back to that queue's position.
    if (startPosition == null && !showPlaybackOption && await _resumeIfCurrent(context, itemModel, ref)) return;

    // When SyncPlay is active, delegate to SyncPlay queue management.
    // _startPlayback (triggered by the server's PlayQueue response)
    // handles player init and route opening.
    final isSyncPlayActive = ref.read(isSyncPlayActiveProvider);
    if (isSyncPlayActive) {
      await _playSyncPlay(context, itemModel, ref, startPosition: startPosition);
      return;
    }

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(ref.read(playbackModelHelper).createPlaybackModel(
          context,
          itemModel,
          showPlaybackOptions: showPlaybackOption,
          startPosition: startPosition,
        ));

    // Not while the choice of direct or transcode is still being asked: a
    // loader under that dialog says something is already being launched, and
    // on a pad it took the focus and could not be sent away.
    if (!showPlaybackOption) _showLoadingIndicator(context, itemModel, op);

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      if (!op.isCanceled) {
        _closeLoadingDialog(context);
        if (!showPlaybackOption) {
          log('unableToPlayMedia [ItemBaseModel._default]: '
              'createPlaybackModel returned null for item=${itemModel.id}');
          FladderSnack.show(context.localized.unableToPlayMedia, context: context);
        }
      }
      return;
    }

    final actualStartPosition = startPosition ?? await model.startDuration() ?? Duration.zero;

    await _playVideo(context, startPosition: actualStartPosition, current: model, ref: ref, cancelOperation: op);
  }
}

/// Play item through SyncPlay - sets the queue and lets SyncPlay
/// handle synchronized playback. Mirrors the local playback path by
/// showing the same loader dialog so the user knows the request was
/// accepted while the server distributes the new queue and our own
/// `_startPlayback` runs.
Future<void> _playSyncPlay(
  BuildContext context,
  ItemBaseModel itemModel,
  WidgetRef ref, {
  Duration? startPosition,
}) async {
  // Build the full play queue so episodes are sent to the group WITH their
  // series context. The local playback path builds this via
  // createPlaybackModel -> collectQueue; the SyncPlay path must match it.
  // A lone single-episode queue is not started by the official Jellyfin
  // clients (e.g. the webOS TV app) even though movies — naturally
  // single-item — work fine. Movies return an empty seriesQueue and fall
  // back to a single item.
  final helper = ref.read(playbackModelHelper);

  // The loader goes up before the queue is fetched, not after: the fetch is
  // a round trip, and the tap felt dead for the whole of it.
  final notifier = ref.read(syncPlayProvider.notifier);
  final pending = notifier.awaitNextStartPlayback(
    timeout: const Duration(seconds: 20),
  );
  final op = CancelableOperation.fromFuture(pending);
  _showLoadingIndicator(context, itemModel, op, autoCloseOnComplete: true);

  final List<ItemBaseModel> seriesQueue = await helper.collectQueue(itemModel);

  // Series/Season tiles resolve to their next-up episode (mirrors
  // createPlaybackModel's firstItemToPlay switch).
  ItemBaseModel target = itemModel;
  if (itemModel is SeriesModel || itemModel is SeasonModel) {
    final resolved = seriesQueue.whereType<EpisodeModel>().toList().nextUp;
    if (resolved != null) target = resolved;
  }

  final List<String> itemIds = seriesQueue.isNotEmpty ? seriesQueue.map((e) => e.id).toList() : [target.id];
  final int playingItemPosition =
      seriesQueue.isNotEmpty ? seriesQueue.indexWhere((e) => e.id == target.id).clamp(0, itemIds.length - 1) : 0;

  // Fall back to the resolved item's saved resume position (mirrors the local
  // path's `model.startDuration()`) so "Continue Watching" resumes mid-item
  // for the whole group instead of restarting from 0. Previously, every play
  // that didn't pass an explicit startPosition sent startPositionTicks: 0.
  final effectiveStart = startPosition ?? target.userData.playBackPosition;
  final startPositionTicks = secondsToTicks(effectiveStart.inMilliseconds / 1000);

  final queueAccepted = await notifier.setNewQueue(
    itemIds: itemIds,
    playingItemPosition: playingItemPosition,
    startPositionTicks: startPositionTicks,
  );

  // setNewQueue is debounced server-side to avoid two participants
  // racing the same request. When suppressed there is no PlayQueue
  // broadcast and no `_startPlayback`, so awaiting it would always time
  // out 20s later with a misleading "unable to play" snack. Cancel the
  // pending wait and treat it as a successful no-op (the playback is
  // already in flight from another participant or our own previous
  // click).
  if (!queueAccepted) {
    log('SyncPlay: _playSyncPlay short-circuited - setNewQueue debounced '
        'or rejected for item=${itemModel.id}');
    if (!op.isCanceled) {
      await op.cancel();
    }
    // Op is cancelled so the auto-close listener on the dialog won't
    // fire (CancelableOperation.value never completes after cancel).
    // No player route has been pushed yet (no PlayQueue → no
    // _startPlayback), so popping the root navigator here safely closes
    // just the loader dialog.
    if (context.mounted) {
      try {
        _closeLoadingDialog(context);
      } catch (_) {}
    }
    return;
  }

  final ok = await op.valueOrCancellation(false) ?? false;
  // Loading dialog auto-closes via _LoadIndicatorCancelable when [op]
  // completes; do not pop the root navigator manually here, otherwise we
  // may pop the player route that `_startPlayback` pushed on top of the
  // dialog.
  if (!op.isCanceled && !ok && context.mounted) {
    log('unableToPlayMedia [_playSyncPlay]: '
        'awaitNextStartPlayback returned false for item=${itemModel.id}');
    FladderSnack.show(context.localized.unableToPlayMedia, context: context);
  }
}

/// How many series/albums to expand into their episodes or tracks at a time.
/// Playing a whole library used to request every one of them at once, which
/// hangs the app long before the queue is ready.
const _libraryExpandConcurrency = 5;

extension ItemBaseModelsBooleans on List<ItemBaseModel> {
  Future<void> playLibraryItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(Future(() async {
      final newList = await mapConcurrent(_libraryExpandConcurrency, (element) async {
        switch (element.type) {
          case FladderItemType.series:
            return await ref.read(jellyApiProvider).fetchEpisodeFromShow(seriesId: element.id);
          default:
            return [element];
        }
      });

      var expandedList =
          newList.expand((element) => element).toList().where((element) => element.playAble).toList().uniqueBy(
                (value) => value.id,
              );

      if (shuffle) {
        expandedList.shuffle();
      }

      // If in SyncPlay group, set the queue via SyncPlay
      final isSyncPlayActive = ref.read(isSyncPlayActiveProvider);
      if (isSyncPlayActive) {
        _closeLoadingDialog(context); // Pop loading indicator
        await ref.read(syncPlayProvider.notifier).setNewQueue(
              itemIds: expandedList.map((e) => e.id).toList(),
              playingItemPosition: 0,
              startPositionTicks: 0,
            );
        return (null, expandedList);
      }

      PlaybackModel? model = await ref.read(playbackModelHelper).createPlaybackModel(
            context,
            expandedList.firstOrNull,
            libraryQueue: expandedList,
          );

      return (model, expandedList);
    }));

    _showLoadingIndicator(context, null, op);

    final result = await op.valueOrCancellation(null);
    if (op.isCanceled || result == null) {
      if (!op.isCanceled) {
        log('unableToPlayMedia [playLibraryItems]: '
            'aggregated playback result was null (items=$length)');
        _closeLoadingDialog(context);
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final PlaybackModel? model = result.$1;
    final List<ItemBaseModel> expandedList = result.$2;

    // SyncPlay path: queue was set via setNewQueue, no local PlaybackModel
    if (model == null && expandedList.isNotEmpty) {
      if (context.mounted) {
        RefreshState.maybeOf(context)?.refresh();
      }
      return;
    }

    if (context.mounted) {
      await _playVideo(context, ref: ref, queue: expandedList, current: model, cancelOperation: op);
      if (context.mounted) {
        RefreshState.maybeOf(context)?.refresh();
      }
    }
  }

  Future<void> playMusicItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(Future(() async {
      final newList = await mapConcurrent(_libraryExpandConcurrency, (element) async {
        switch (element) {
          case AudioModel audio:
            return <ItemBaseModel>[audio];
          case AlbumModel album:
            return await _fetchAlbumQueue(album, ref);
          case ArtistModel artist:
            return await ArtistCatalogQueueSource(artistId: artist.id, limit: 300).fetchQueue(ref.read);
          default:
            return const <ItemBaseModel>[];
        }
      });

      final expandedList =
          newList.expand((element) => element).whereType<AudioModel>().cast<ItemBaseModel>().toList().uniqueBy(
                (value) => value.id,
              );

      if (shuffle) {
        expandedList.shuffle();
      }

      final model = await ref.read(playbackModelHelper).createPlaybackModel(
            context,
            expandedList.firstOrNull,
            libraryQueue: expandedList,
          );

      return (model, expandedList);
    }));

    _showLoadingIndicator(context, null, op);

    final result = await op.valueOrCancellation(null);
    if (op.isCanceled || result == null) {
      if (!op.isCanceled) {
        _closeLoadingDialog(context);
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final PlaybackModel? model = result.$1;
    final List<ItemBaseModel> expandedList = result.$2;

    if (model == null || expandedList.isEmpty) {
      _closeLoadingDialog(context);
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      return;
    }

    final currentIndex =
        expandedList.indexWhere((element) => element.id == model.item.id).clamp(0, expandedList.length - 1);
    final actualStartPosition = await model.startDuration() ?? Duration.zero;

    try {
      _closeLoadingDialog(context);
    } catch (_) {}

    await ref.read(videoPlayerProvider.notifier).loadAudioPlaybackItem(
          model,
          expandedList,
          currentIndex,
          actualStartPosition,
        );

    if (context.mounted) {
      RefreshState.maybeOf(context)?.refresh();
    }
  }
}

/// Closes the loading dialog and nothing else.
///
/// These call sites all mean "close the loader", but a bare pop closes
/// whatever happens to be on top — and the loader is often already gone,
/// because the cancel button closes it itself. That popped the page
/// underneath instead, which is how cancelling left a blank screen.
void _closeLoadingDialog(BuildContext context) {
  try {
    Navigator.of(context, rootNavigator: true).popUntil((route) => route is! RawDialogRoute);
  } catch (e) {
    log('Error closing loading dialog: $e');
  }
}

Future<void> _showLoadingIndicator(
  BuildContext context,
  ItemBaseModel? item,
  CancelableOperation op, {
  bool autoCloseOnComplete = false,
}) async {
  return showDialog(
    barrierDismissible: false,
    useRootNavigator: true,
    context: context,
    // Framed like every other dialog: on a pad the selection stays inside,
    // and back closes it - which cancels what it was waiting for.
    builder: (context) => TvDialogFrame(
      child: _LoadIndicatorCancelable(
        op: op,
        item: item,
        autoCloseOnComplete: autoCloseOnComplete,
      ),
    ),
  );
}

class _LoadIndicatorCancelable extends StatefulWidget {
  final ItemBaseModel? item;
  final CancelableOperation op;
  final bool autoCloseOnComplete;
  const _LoadIndicatorCancelable({
    required this.op,
    this.item,
    this.autoCloseOnComplete = false,
  });

  @override
  State<_LoadIndicatorCancelable> createState() => _LoadIndicatorCancelableState();
}

class _LoadIndicatorCancelableState extends State<_LoadIndicatorCancelable> {
  @override
  void initState() {
    super.initState();
    if (!widget.autoCloseOnComplete) {
      return;
    }
    // Auto-close as soon as the underlying operation finishes. Used by
    // the SyncPlay flow where `_startPlayback` pushes the player route
    // on top of this dialog after the server's PlayQueue update; if the
    // caller popped the root navigator manually after awaiting the op,
    // it would pop the player route instead of this dialog, which would
    // minimize the player and surface a spurious "unable to play" snack.
    widget.op.value.whenComplete(() {
      if (!mounted) {
        return;
      }
      try {
        _closeLoadingDialog(context);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    // Closed by back or escape rather than the button: nothing else would
    // stop what it was waiting for, and the player would open over whatever
    // the user had moved on to.
    if (!widget.op.isCompleted && !widget.op.isCanceled) {
      try {
        widget.op.cancel();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = const BorderRadius.all(Radius.circular(4));

    return Dialog(
      constraints: const BoxConstraints(
        maxWidth: 450,
        maxHeight: 500,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: 16,
          children: [
            Expanded(
              child: Row(
                spacing: 16,
                children: [
                  if (widget.item != null)
                    Flexible(
                      child: Container(
                        decoration: FladderTheme.defaultPosterDecoration,
                        clipBehavior: Clip.hardEdge,
                        height: 175,
                        child: AspectRatio(
                          aspectRatio: 0.7,
                          child: SquareProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                            strokeCap: StrokeCap.round,
                            strokeWidth: 8,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  color: Theme.of(context).colorScheme.surfaceContainer,
                                ),
                                foregroundDecoration: BoxDecoration(
                                  borderRadius: radius,
                                  border: Border.all(width: 1, color: Colors.white.withAlpha(45)),
                                ),
                                clipBehavior: Clip.hardEdge,
                                child: FladderImage(
                                  image: widget.item!.getPosters?.primary,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SquareProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        Text(
                          context.localized.loading,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.item != null) ...[
                          Text(
                            widget.item!.title,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // On a pad as well - it used to be hidden there, which left a
            // loader that could neither be reached nor sent away, and the
            // pad dead under it.
            IconButton(
              tooltip: context.localized.close,
              autofocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad,
              onPressed: () {
                try {
                  widget.op.cancel();
                } catch (_) {}
                _closeLoadingDialog(context);
              },
              icon: const Icon(IconsaxPlusLinear.close_square),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lands in the diagnostics file beside the SyncPlay traces.
final _playbackLog = logging.Logger('Playback');

/// Brings a minimized player showing [item] back to full screen. Returns
/// whether it did; false means [item] is not what is playing.
Future<bool> _resumeIfCurrent(BuildContext context, ItemBaseModel item, WidgetRef ref) async {
  final playing = ref.read(playBackModel)?.item;
  if (playing == null || playing.id != item.id) return false;
  if (ref.read(mediaPlaybackProvider).state != VideoPlayerState.minimized) return false;
  _playbackLog.info('play: ${item.name} is already playing; opening the player');
  ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));
  await ref.read(videoPlayerProvider.notifier).openPlayer(context);
  if (context.mounted && AdaptiveLayout.of(context).isDesktop && defaultTargetPlatform != TargetPlatform.macOS) {
    fullScreenHelper.closeFullScreen(ref);
  }
  return true;
}

Future<void> _playVideo(
  BuildContext context, {
  required PlaybackModel? current,
  Duration? startPosition,
  List<ItemBaseModel>? queue,
  required WidgetRef ref,
  VoidCallback? onPlayerExit,
  CancelableOperation? cancelOperation,
}) async {
  if (current == null) {
    if (context.mounted) {
      _closeLoadingDialog(context);
      log('unableToPlayMedia [_playVideo]: '
          'current PlaybackModel was null (queue=${queue?.length ?? 0})');
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    }
    return;
  }

  if (cancelOperation?.isCanceled ?? false) return;

  final actualStartPosition = startPosition ?? await current.startDuration() ?? Duration.zero;

  final playTimer = Stopwatch()..start();
  final loadedCorrectly = await ref.read(videoPlayerProvider.notifier).loadPlaybackItem(
        current,
        actualStartPosition,
        openFullScreen: true,
      );
  _playbackLog.info('play: ${current.item.name} loaded in ${playTimer.elapsedMilliseconds}ms');

  /// Past this point the player is loaded and playing, so a cancel has to tear
  /// it down rather than just walk away: returning left the media audible with
  /// no route pushed and no way back to it.
  Future<bool> cancelledAfterLoading() async {
    if (!(cancelOperation?.isCanceled ?? false)) return false;
    await ref.read(videoPlayerProvider).stop();
    return true;
  }

  if (!loadedCorrectly) {
    if (context.mounted) {
      _closeLoadingDialog(context);
      FladderSnack.show(context.localized.errorOpeningMedia, context: context);
    }
    return;
  }

  if (await cancelledAfterLoading()) return;

  try {
    _closeLoadingDialog(context);
  } catch (_) {}

  if (await cancelledAfterLoading()) return;

  await ref.read(videoPlayerProvider.notifier).openPlayer(context);
  _playbackLog.info('play: player route opened at ${playTimer.elapsedMilliseconds}ms');
  if (AdaptiveLayout.of(context).isDesktop && defaultTargetPlatform != TargetPlatform.macOS) {
    fullScreenHelper.closeFullScreen(ref);
  }

  if (context.mounted) {
    if (await cancelledAfterLoading()) return;
    await context.refreshData();
  }

  onPlayerExit?.call();
}

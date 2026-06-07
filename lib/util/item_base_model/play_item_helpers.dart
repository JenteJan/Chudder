import 'dart:developer';

import 'package:async/async.dart';
import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:fladder/models/book_model.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/channel_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/models/items/photos_model.dart';
import 'package:fladder/models/items/season_model.dart';
import 'package:fladder/models/items/series_model.dart';
import 'package:fladder/models/media_playback_model.dart';
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
import 'package:fladder/screens/shared/fladder_notification_overlay.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/list_extensions.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/refresh_state.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:square_progress_indicator/square_progress_indicator.dart';

import '../../models/syncplay/syncplay_models.dart';

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
        includeItemTypes: FladderItemType.galleryItem.map((e) => e.dtoKind).toList(),
        recursive: true));

    _showLoadingIndicator(context, albumModel, op);

    final getChildItems = await op.valueOrCancellation(null);
    if (op.isCanceled || getChildItems == null) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      if (!op.isCanceled) {
        log('unableToPlayMedia [PhotoAlbumModel.play]: '
            'getChildItems was null for album=${albumModel.id}');
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
      }
      return;
    }

    final photos = getChildItems.body?.items.whereType<PhotoModel>() ?? [];

    try {
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      log('Error closing loading dialog: $e');
    }

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
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      if (!op.isCanceled) {
        log('unableToPlayMedia [ChannelModel.play]: '
            'createPlaybackModel returned null for channel=${this!.id}');
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

extension ItemBaseModelExtensions on ItemBaseModel? {
  Future<void> play(
    BuildContext context,
    WidgetRef ref, {
    Duration? startPosition,
    bool showPlaybackOption = false,
  }) async =>
      switch (this) {
        PhotoAlbumModel album => album.play(context, ref),
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

    _showLoadingIndicator(context, itemModel, op);

    final model = await op.valueOrCancellation(null);
    if (op.isCanceled || model == null) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      if (!op.isCanceled && !showPlaybackOption) {
        log('unableToPlayMedia [ItemBaseModel._default]: '
            'createPlaybackModel returned null for item=${itemModel.id}');
        FladderSnack.show(context.localized.unableToPlayMedia, context: context);
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

  final notifier = ref.read(syncPlayProvider.notifier);
  final pending = notifier.awaitNextStartPlayback(
    timeout: const Duration(seconds: 20),
  );
  final op = CancelableOperation.fromFuture(pending);

  _showLoadingIndicator(context, itemModel, op, autoCloseOnComplete: true);

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
        Navigator.of(context, rootNavigator: true).pop();
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

extension ItemBaseModelsBooleans on List<ItemBaseModel> {
  Future<void> playLibraryItems(BuildContext context, WidgetRef ref, {bool shuffle = false}) async {
    if (isEmpty) return;

    await ref.read(videoPlayerProvider.notifier).init();

    final op = CancelableOperation.fromFuture(Future(() async {
      List<List<ItemBaseModel>> newList = await Future.wait(map((element) async {
        switch (element.type) {
          case FladderItemType.series:
            return await ref.read(jellyApiProvider).fetchEpisodeFromShow(seriesId: element.id);
          default:
            return [element];
        }
      }));

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
        Navigator.of(context, rootNavigator: true).pop(); // Pop loading indicator
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
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      if (!op.isCanceled) {
        log('unableToPlayMedia [playLibraryItems]: '
            'aggregated playback result was null (items=$length)');
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
    builder: (context) => _LoadIndicatorCancelable(
      op: op,
      item: item,
      autoCloseOnComplete: autoCloseOnComplete,
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
        Navigator.of(context, rootNavigator: true).pop();
      } catch (_) {}
    });
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
            if (AdaptiveLayout.inputDeviceOf(context) != InputDevice.dPad)
              IconButton(
                tooltip: context.localized.close,
                onPressed: () {
                  try {
                    widget.op.cancel();
                  } catch (_) {}
                  Navigator.of(context, rootNavigator: true).pop();
                },
                icon: const Icon(IconsaxPlusLinear.close_square),
              ),
          ],
        ),
      ),
    );
  }
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
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      log('unableToPlayMedia [_playVideo]: '
          'current PlaybackModel was null (queue=${queue?.length ?? 0})');
      FladderSnack.show(context.localized.unableToPlayMedia, context: context);
    }
    return;
  }

  if (cancelOperation?.isCanceled ?? false) return;

  final actualStartPosition = startPosition ?? await current.startDuration() ?? Duration.zero;

  final loadedCorrectly = await ref.read(videoPlayerProvider.notifier).loadPlaybackItem(
        current,
        actualStartPosition,
      );

  if (!loadedCorrectly) {
    if (context.mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
      } catch (e) {
        log('Error closing loading dialog: $e');
      }
      FladderSnack.show(context.localized.errorOpeningMedia, context: context);
    }
    return;
  }

  if (cancelOperation?.isCanceled ?? false) return;

  try {
    Navigator.of(context, rootNavigator: true).pop();
  } catch (_) {}

  ref.read(mediaPlaybackProvider.notifier).update((state) => state.copyWith(state: VideoPlayerState.fullScreen));

  if (cancelOperation?.isCanceled ?? false) return;

  await ref.read(videoPlayerProvider.notifier).openPlayer(context);
  if (AdaptiveLayout.of(context).isDesktop && defaultTargetPlatform != TargetPlatform.macOS) {
    fullScreenHelper.closeFullScreen(ref);
  }

  if (context.mounted) {
    if (cancelOperation?.isCanceled ?? false) return;
    await context.refreshData();
  }

  onPlayerExit?.call();
}

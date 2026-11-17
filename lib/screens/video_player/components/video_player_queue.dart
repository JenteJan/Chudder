import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/audio_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/models/media_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/playback_queue_state.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/wrappers/media_control_wrapper.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/item_base_model/item_base_model_extensions.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

typedef QueueSectionReorderCallback = Future<void> Function(
  AudioQueueSection section,
  int oldIndex,
  int newIndex,
);

/// How many items the player's queue holds, "up next" included.
int playerQueueLength(PlaybackModel? model) {
  if (model == null) return 0;
  final queue = model.playbackQueue;
  return queue.queue.length + queue.nextUpQueue.length;
}

/// Whether there is a queue to show: something lined up in "up next", or a
/// queue of more than what is playing.
///
/// A show's own episodes too, beside the episodes panel. That panel shows the
/// season in the order the show has it; a shuffled show plays in another, and
/// what comes next was nowhere to be seen.
bool canShowPlayerQueue(PlaybackModel? model) {
  if (model == null) return false;
  final queue = model.playbackQueue;
  return queue.nextUpQueue.isNotEmpty || queue.queue.length >= 2;
}

/// The queue of what is playing, to look through and rearrange: drag to
/// reorder, or move with the item's menu from a remote.
Future<void> showPlayerQueue(BuildContext context, WidgetRef ref) {
  final model = ref.read(playBackModel);
  final notifier = ref.read(videoPlayerProvider.notifier);
  return showFullScreenItemQueue(
    context,
    items: model?.queue ?? const [],
    currentItem: model?.item,
    onSectionReorder: notifier.reorderAudioQueueSection,
    // A video swaps the way an episode picked from the panel does; music
    // goes through its own queue, which cross-fades.
    playSelected: model?.item is AudioModel
        ? notifier.playAudioQueueItem
        : (item) => ref.read(playbackModelHelper).loadNewVideo(item),
  );
}

Future<void> showFullScreenItemQueue(
  BuildContext context, {
  required List<ItemBaseModel> items,
  QueueSectionReorderCallback? onSectionReorder,
  Function(ItemBaseModel itemStreamModel)? playSelected,
  ItemBaseModel? currentItem,
}) {
  return showDialog(
    useSafeArea: false,
    useRootNavigator: true,
    context: context,
    builder: (context) {
      return TvDialogFrame(
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: TvDialogSurface(
              child: VideoPlayerQueue(
                items: items,
                currentItem: currentItem,
                onSectionReorder: onSectionReorder,
                playSelected: playSelected,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class VideoPlayerQueue extends ConsumerStatefulWidget {
  final List<ItemBaseModel> items;
  final ItemBaseModel? currentItem;
  final Function(ItemBaseModel)? playSelected;
  final QueueSectionReorderCallback? onSectionReorder;

  const VideoPlayerQueue({super.key, required this.items, this.currentItem, this.playSelected, this.onSectionReorder});

  @override
  ConsumerState<VideoPlayerQueue> createState() => _VideoPlayerQueueState();
}

class _VideoPlayerQueueState extends ConsumerState<VideoPlayerQueue> {
  /// The item being moved with up and down, by where it is now. Held until
  /// OK (or back) puts it down.
  ({AudioQueueSection section, int index})? _moving;

  /// The last step taken, for the two rows that swapped to slide into their
  /// new places rather than jump there.
  ({AudioQueueSection section, int from, int to, int serial})? _lastStep;
  int _steps = 0;
  bool _stepping = false;

  /// A selection per place in the list rather than per row: a moved item's
  /// row is built anew at its new place, and the selection goes with the
  /// place it moved to.
  final Map<String, FocusNode> _nodes = {};

  FocusNode _nodeFor(AudioQueueSection section, int index) =>
      _nodes.putIfAbsent('${section.name}:$index', () => FocusNode(debugLabel: 'queue ${section.name} $index'));

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _focusLater(FocusNode node, {bool down = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = node.context;
        if (!mounted || context == null) return;
        node.requestFocus();
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignmentPolicy:
              down ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      });

  void _onItemTapped(ItemBaseModel item) {
    if (widget.playSelected != null) {
      widget.playSelected!(item);
    } else {
      ref.read(videoPlayerProvider.notifier).playAudioQueueItem(item);
    }
    context.maybePop();
  }

  Future<void> _reorder(AudioQueueSection section, int oldIndex, int newIndex) async {
    await widget.onSectionReorder?.call(section, oldIndex, newIndex);
  }

  void _startMove(AudioQueueSection section, int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _moving = (section: section, index: index);
      _lastStep = null;
    });
    _focusLater(_nodeFor(section, index));
  }

  void _endMove() {
    final moving = _moving;
    if (moving == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _moving = null;
      _lastStep = null;
    });
    _focusLater(_nodeFor(moving.section, moving.index));
  }

  /// One place up ([by] -1) or down, within the item's own section.
  Future<void> _step(int by, int count) async {
    final moving = _moving;
    if (moving == null) return;
    final to = moving.index + by;
    if (to < 0 || to >= count) return;
    if (_stepping) return;
    _stepping = true;
    HapticFeedback.selectionClick();
    try {
      // The queue first, then the held place: both land in the same frame,
      // so the highlight never shows on the row being passed.
      await _reorder(moving.section, moving.index, to);
    } finally {
      _stepping = false;
    }
    if (!mounted) return;
    setState(() {
      _moving = (section: moving.section, index: to);
      _lastStep = (section: moving.section, from: moving.index, to: to, serial: ++_steps);
    });
    _focusLater(_nodeFor(moving.section, to), down: by > 0);
  }

  /// Up and down move the held item; OK, back and escape put it down; left
  /// and right go nowhere while it is held.
  KeyEventResult _movingKeys(KeyEvent event, int count) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _step(-1, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _step(1, count);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) return KeyEventResult.handled;
    if (event is KeyDownEvent && (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack)) {
      _endMove();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showItemActionsMenu(
    ItemBaseModel item,
    Offset globalPosition, {
    required int count,
    AudioQueueSection? section,
    int? index,
  }) async {
    final notifier = ref.read(videoPlayerProvider.notifier);
    final itemActions = item.generateActions(
      context,
      ref,
      exclude: {
        ItemActions.play,
        ItemActions.playNext,
        ItemActions.addToQueue,
        ItemActions.refreshMetaData,
      },
    );
    final canMove = section != null && index != null && widget.onSectionReorder != null && count > 1;

    await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        if (section != null)
          ItemActionButton(
            label: Text(context.localized.queuePlayNow),
            icon: const Icon(IconsaxPlusLinear.play),
            action: () => _onItemTapped(item),
          ),
        // From further down the queue straight to after what is playing.
        if (section == AudioQueueSection.existing)
          ItemActionButton(
            label: Text(context.localized.playNext),
            icon: const Icon(IconsaxPlusLinear.next),
            action: () async {
              await notifier.playQueueItemNext(item);
            },
          ),
        if (canMove)
          ItemActionButton(
            label: Text(context.localized.queueMove),
            icon: const Icon(IconsaxPlusLinear.arrow_3),
            action: () => _startMove(section, index),
          ),
        ItemActionButton(
          label: Text(context.localized.removeFromQueue),
          icon: const Icon(IconsaxPlusLinear.minus_cirlce),
          action: () => switch (section) {
            AudioQueueSection.nextUp => notifier.removeAudioQueueSectionItem(AudioQueueSection.nextUp, index ?? 0),
            // By the item: the section's numbers count from what is playing,
            // the queue's own from its start.
            _ => notifier.removeAudioQueueItem(item),
          },
        ),
        if (itemActions.isNotEmpty) ItemActionDivider(),
        ...itemActions,
      ].popupMenuItems(useIcons: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playbackInfo = ref.watch(mediaPlaybackProvider);
    final player = ref.watch(videoPlayerProvider);
    // Watched so the lists follow every change made here.
    ref.watch(playBackModel.select((value) => value?.playbackQueue));

    final shouldWrap = playbackInfo.repeatMode == AudioRepeatMode.all;
    final providerItems = player.audioQueueForDisplay(wrapAround: shouldWrap);
    // A film on its own has no queue of its own, only what was added after
    // it: the list starts with it all the same, as "up next" counts from it.
    final current = ref.watch(playBackModel.select((value) => value?.item)) ?? widget.currentItem;
    final listed = providerItems.isNotEmpty ? providerItems : widget.items;
    final items = current != null && listed.firstOrNull?.id != current.id ? [current, ...listed] : listed;
    final tempStart = player.temporaryQueueStartInDisplay(wrapAround: shouldWrap);
    final tempCount = player.temporaryQueueCountInDisplay() ?? 0;

    final nowPlaying = items.firstOrNull;

    final nextUpItems = <ItemBaseModel>[];
    final existingItems = <ItemBaseModel>[];
    if (items.isNotEmpty) {
      final tempEnd = tempStart != null ? tempStart + tempCount : -1;
      for (var i = 1; i < items.length; i++) {
        final isNextUp = tempStart != null && tempCount > 0 && i >= tempStart && i < tempEnd;
        if (isNextUp) {
          nextUpItems.add(items[i]);
        } else {
          existingItems.add(items[i]);
        }
      }
    }

    final dPad = AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad;
    final canMove = widget.onSectionReorder != null;

    Widget section(AudioQueueSection section, List<ItemBaseModel> sectionItems) => _QueueSortList(
          items: sectionItems,
          dragHandles: !dPad && canMove && _moving == null,
          onReorder: (oldIndex, newIndex) => _reorder(section, oldIndex, newIndex),
          tileFor: (index, item) {
            final moving = _moving?.section == section && _moving?.index == index;
            // The held row comes from where it was; the one it passed goes
            // the other way. In rows, which are all the same height.
            final step = _lastStep;
            final slideFrom = step == null || step.section != section
                ? 0.0
                : index == step.to
                    ? (step.from - step.to).toDouble()
                    : index == step.from
                        ? (step.to - step.from).toDouble()
                        : 0.0;
            return _QueueTile(
              slideFrom: slideFrom,
              slideSerial: step?.serial ?? 0,
              item: item,
              focusNode: _nodeFor(section, index),
              moving: moving,
              dragIndex: !dPad && canMove && _moving == null ? index : null,
              onTap: moving ? _endMove : () => _onItemTapped(item),
              onLongPress:
                  canMove && sectionItems.length > 1 && _moving == null ? () => _startMove(section, index) : null,
              onKeyEvent: moving ? (event) => _movingKeys(event, sectionItems.length) : null,
              onStep: moving ? (by) => _step(by, sectionItems.length) : null,
              onShowActions: (globalPosition) => _showItemActionsMenu(
                item,
                globalPosition,
                count: sectionItems.length,
                section: section,
                index: index,
              ),
            );
          },
        );

    // Back puts a held item down before it closes anything.
    return PopScope(
      canPop: _moving == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endMove();
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.localized.queue,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Opacity(
                          opacity: 0.6,
                          child: Text(
                            _moving != null
                                ? context.localized.queueMoveHint
                                : context.localized.queueItemCount(items.length),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // On a television the dialog's surface puts its own close
                  // button in the corner.
                  if (!tvControlsOf(context, ref))
                    IconButton(
                      tooltip: context.localized.close,
                      onPressed: () => context.maybePop(),
                      icon: const Icon(IconsaxPlusLinear.close_circle),
                    ),
                ],
              ),
            ),
            const Divider(),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 4).copyWith(bottom: 16),
                  children: [
                    if (nowPlaying != null) ...[
                      _QueueSectionHeader(
                        icon: IconsaxPlusLinear.play_circle,
                        title: context.localized.nowPlaying,
                      ),
                      _QueueTile(
                        item: nowPlaying,
                        isCurrent: true,
                        autofocus: true,
                        onTap: () => context.maybePop(),
                        onShowActions: (globalPosition) => _showItemActionsMenu(
                          nowPlaying,
                          globalPosition,
                          count: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (nextUpItems.isNotEmpty) ...[
                      _QueueSectionHeader(
                        icon: IconsaxPlusLinear.next,
                        title: context.localized.upNext,
                        trailing: TextButton.icon(
                          onPressed: _moving != null
                              ? null
                              : () => ref.read(videoPlayerProvider.notifier).clearTemporaryQueue(),
                          icon: const Icon(Icons.clear_all_rounded, size: 18),
                          label: Text(context.localized.clear),
                        ),
                      ),
                      section(AudioQueueSection.nextUp, nextUpItems),
                      const SizedBox(height: 8),
                    ],
                    // A video's queue is one list in the order it plays: no
                    // "later" under an "up next" (music keeps both).
                    if (nowPlaying is! AudioModel && nextUpItems.isEmpty)
                      _QueueSectionHeader(
                        icon: IconsaxPlusLinear.next,
                        title: context.localized.upNext,
                      )
                    else
                      _QueueSectionHeader(
                        icon: IconsaxPlusLinear.task_square,
                        title: context.localized.queueLater,
                      ),
                    if (existingItems.isEmpty)
                      Opacity(
                        opacity: 0.6,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          child: Text(
                            context.localized.queueIsEmpty,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    else
                      section(AudioQueueSection.existing, existingItems),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;

  const _QueueSectionHeader({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _QueueSortList extends StatelessWidget {
  final List<ItemBaseModel> items;
  final bool dragHandles;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget Function(int index, ItemBaseModel item) tileFor;

  const _QueueSortList({
    required this.items,
    required this.dragHandles,
    required this.onReorder,
    required this.tileFor,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderItem: onReorder,
      itemBuilder: (context, index) => KeyedSubtree(
        key: ValueKey('${items[index].id}-$index'),
        child: tileFor(index, items[index]),
      ),
    );
  }
}

/// One item in the queue, in the shape of a track in the subtitle picker:
/// the row is one stop with the app's selection ring, its menu sits beside
/// it (right reaches it, left comes back), and a long press - or holding OK -
/// picks it up to move with up and down.
class _QueueTile extends StatelessWidget {
  final ItemBaseModel item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<Offset> onShowActions;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;

  /// Moves the held item a place up (-1) or down, for a pointer.
  final ValueChanged<int>? onStep;
  final FocusNode? focusNode;
  final bool isCurrent;
  final bool moving;
  final bool autofocus;
  final int? dragIndex;

  /// Rows away the tile starts from, sliding into place; see [slideSerial].
  final double slideFrom;

  /// Which step [slideFrom] belongs to: a new one starts the slide again.
  final int slideSerial;

  const _QueueTile({
    this.slideFrom = 0,
    this.slideSerial = 0,
    required this.item,
    required this.onTap,
    required this.onShowActions,
    this.onLongPress,
    this.onKeyEvent,
    this.onStep,
    this.focusNode,
    this.isCurrent = false,
    this.moving = false,
    this.autofocus = false,
    this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isAudio = item is AudioModel;
    final radius = BorderRadius.circular(12);
    final ImageData? image = switch (item) {
      AudioModel() || EpisodeModel() => item.images?.primary,
      _ => item.images?.thumb ?? item.images?.backDrop?.firstOrNull ?? item.images?.primary,
    };
    final placeholder = Center(
      child: Icon(isAudio ? Icons.music_note_rounded : IconsaxPlusLinear.video_play, size: 20),
    );
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            // Picked up: a little larger, lifted off the list.
            child: AnimatedScale(
              scale: moving ? 1.03 : 1,
              duration: const Duration(milliseconds: 140),
              curve: moving ? Curves.easeOutBack : Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: moving ? 0.45 : 0),
                      blurRadius: moving ? 18 : 0,
                      offset: Offset(0, moving ? 6 : 0),
                    ),
                  ],
                ),
                child: FocusButton(
                  focusNode: focusNode,
                  autoFocus: autofocus,
                  onTap: onTap,
                  onLongPress: onLongPress,
                  onSecondaryTapDown: (details) => onShowActions(details.globalPosition),
                  onKeyEvent: onKeyEvent == null ? null : (node, event) => onKeyEvent!(event),
                  forceFocusOutline: moving,
                  borderRadius: radius,
                  darkOverlay: false,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      color: moving
                          ? scheme.primaryContainer.withValues(alpha: 0.7)
                          : isCurrent
                              ? scheme.primaryContainer.withValues(alpha: 0.35)
                              : Colors.transparent,
                    ),
                    child: Row(
                      spacing: 12,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(isAudio ? 20 : 6),
                          child: Container(
                            width: isAudio ? 40 : 72,
                            height: 40,
                            color: scheme.surfaceContainerHighest,
                            child: FladderImage(
                              image: image,
                              fit: BoxFit.cover,
                              placeHolder: placeholder,
                              imageErrorBuilder: (context, error, stack) => placeholder,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: isCurrent || moving ? FontWeight.bold : null,
                                ),
                              ),
                              Text(
                                item.subTextShort(context.localized) ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        if (moving) Icon(IconsaxPlusLinear.arrow_3, size: 20, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (moving && onStep != null)
            // For a finger or a mouse; a remote moves it with up and down,
            // so these are no stops of their own.
            ExcludeFocus(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: context.localized.queueMoveUp,
                    onPressed: () => onStep!(-1),
                    icon: const Icon(IconsaxPlusLinear.arrow_up_2),
                  ),
                  IconButton(
                    tooltip: context.localized.queueMoveDown,
                    onPressed: () => onStep!(1),
                    icon: const Icon(IconsaxPlusLinear.arrow_down_1),
                  ),
                ],
              ),
            )
          else ...[
            Builder(
              builder: (context) => IconButton(
                tooltip: context.localized.options,
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox?;
                  onShowActions(box?.localToGlobal(box.size.center(Offset.zero)) ?? Offset.zero);
                },
                icon: const Icon(IconsaxPlusLinear.more),
              ),
            ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Icon(Icons.drag_indicator_rounded),
                ),
              ),
          ],
        ],
      ),
    );
    if (slideFrom == 0) return row;
    return TweenAnimationBuilder<double>(
      key: ValueKey(slideSerial),
      tween: Tween(begin: slideFrom, end: 0),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (context, rows, child) => FractionalTranslation(translation: Offset(0, rows), child: child),
      child: row,
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/episode_model.dart';
import 'package:chudder/models/playback/direct_playback_model.dart';
import 'package:chudder/models/playback/offline_playback_model.dart';
import 'package:chudder/models/playback/playback_model.dart';
import 'package:chudder/models/playback/transcode_playback_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/models/items/media_streams_model.dart';
import 'package:chudder/providers/subtitles/subtitle_file_actions.dart';
import 'package:chudder/providers/subtitles/subtitle_finder_provider.dart';
import 'package:chudder/providers/subtitles/subtitle_fix_service.dart';
import 'package:chudder/providers/subtitles/subtitle_timing_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/syncplay/syncplay_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/collections/add_to_collection.dart';
import 'package:chudder/screens/metadata/info_screen.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/subtitles/subtitle_finder.dart';
import 'package:chudder/screens/subtitles/subtitle_track_actions.dart';
import 'package:chudder/screens/playlists/add_to_playlists.dart';
import 'package:chudder/screens/video_player/components/subtitle_fixes.dart';
import 'package:chudder/screens/video_player/components/video_player_episodes.dart';
import 'package:chudder/screens/video_player/components/video_player_quality_controls.dart';
import 'package:chudder/screens/video_player/components/video_player_queue.dart';
import 'package:chudder/screens/video_player/components/video_subtitle_controls.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/device_orientation_extension.dart';
import 'package:chudder/util/list_padding.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/util/map_bool_helper.dart';
import 'package:chudder/util/refresh_state.dart';
import 'package:chudder/util/string_extensions.dart';
import 'package:chudder/util/subtitle_names.dart';
import 'package:chudder/widgets/shared/enum_selection.dart';
import 'package:chudder/widgets/shared/fladder_slider.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/modal_bottom_sheet.dart';
import 'package:chudder/widgets/shared/spaced_list_tile.dart';

Future<void> showVideoPlayerOptions(BuildContext context, Function() minimizePlayer) {
  return showBottomSheetPill(
    context: context,
    content: (context, scrollController) {
      return VideoOptions(
        controller: scrollController,
        minimizePlayer: minimizePlayer,
      );
    },
  );
}

class VideoOptions extends ConsumerStatefulWidget {
  final ScrollController controller;
  final Function() minimizePlayer;
  const VideoOptions({required this.controller, required this.minimizePlayer, super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _VideoOptionsMobileState();
}

class _VideoOptionsMobileState extends ConsumerState<VideoOptions> {
  late int page = 0;

  @override
  Widget build(BuildContext context) {
    final currentItem = ref.watch(playBackModel.select((value) => value?.item));
    final videoSettings = ref.watch(videoPlayerSettingsProvider);
    final currentMediaStreams = ref.watch(playBackModel.select((value) => value?.mediaStreams));
    final bitRateOptions = ref.watch(playBackModel.select((value) => value?.bitRateOptions));
    final hasEpisodes = ref.watch(playBackModel.select(canBrowseEpisodes));

    Widget mainPage() {
      return ListView(
        key: const Key("mainPage"),
        shrinkWrap: true,
        controller: widget.controller,
        children: [
          InkWell(
            onTap: () => setState(() => page = 2),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentItem?.title ?? "",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Opacity(opacity: 0.1, child: Icon(Icons.info_outline_rounded))
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // The way to the show's episodes when the control row is too narrow
          // to carry its own button for them.
          if (hasEpisodes)
            SpacedListTile(
              title: Text(context.localized.episode(2)),
              content: Text(
                currentItem is EpisodeModel ? currentItem.seasonEpisodeLabel(context.localized) : "",
              ),
              onTap: () {
                Navigator.of(context).pop();
                showPlayerEpisodes(context, ref);
              },
            ),
          if (!AdaptiveLayout.of(context).isDesktop)
            ListTile(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(flex: 1, child: Text(context.localized.screenBrightness)),
                  Flexible(
                    child: Row(
                      children: [
                        Flexible(
                          child: Opacity(
                            opacity: videoSettings.screenBrightness == null ? 0.5 : 1,
                            child: Slider(
                              value: videoSettings.screenBrightness ?? 1.0,
                              min: 0,
                              max: 1,
                              onChanged: (value) =>
                                  ref.read(videoPlayerSettingsProvider.notifier).setScreenBrightness(value),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => ref.read(videoPlayerSettingsProvider.notifier).setScreenBrightness(null),
                          icon: Opacity(
                            opacity: videoSettings.screenBrightness != null ? 0.5 : 1,
                            child: Icon(
                              IconsaxPlusBold.autobrightness,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SpacedListTile(
            title: Text(context.localized.subtitles),
            content: Text(currentMediaStreams?.currentSubStream?.label(context) ?? context.localized.off),
            onTap: currentMediaStreams?.subStreams.isNotEmpty == true ? () => showSubSelection(context) : null,
          ),
          SpacedListTile(
            title: Text(context.localized.audio(1)),
            content: Text(currentMediaStreams?.currentAudioStream?.label(context) ?? context.localized.off),
            onTap: currentMediaStreams?.audioStreams.isNotEmpty == true ? () => showAudioSelection(context) : null,
          ),
          ListTile(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: EnumSelection(
                    label: Text(context.localized.scale),
                    current: videoSettings.videoFit.name.toUpperCaseSplit(),
                    itemBuilder: (context) => BoxFit.values
                        .map((value) => ItemActionButton(
                              label: Text(value.name.toUpperCaseSplit()),
                              action: () => ref.read(videoPlayerSettingsProvider.notifier).setFitType(value),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: Text(context.localized.playerSettingsAmbientBlurTitle),
            value: videoSettings.ambientBlur,
            onChanged: (value) {
              ref.read(videoPlayerSettingsProvider.notifier).setAmbientBlur(value == true);
            },
          ),
          if (!AdaptiveLayout.of(context).isDesktop)
            ListTile(
              onTap: () => ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(!videoSettings.fillScreen),
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(context.localized.videoScalingFill),
                  ),
                  const Spacer(),
                  Switch(
                    value: videoSettings.fillScreen,
                    onChanged: (value) => ref.read(videoPlayerSettingsProvider.notifier).setFillScreen(value),
                  )
                ],
              ),
            ),
          if (!AdaptiveLayout.of(context).isDesktop && !kIsWeb)
            SpacedListTile(
              title: Text(context.localized.playerSettingsOrientationTitle),
              onTap: () => showOrientationOptions(context, ref),
            ),
          ListTile(
            onTap: () {
              Navigator.of(context).pop();
              showPlaybackSpeed(context);
            },
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(context.localized.playbackRate),
                ),
                const Spacer(),
                Text("x${ref.watch(playbackRateProvider)}")
              ],
            ),
          ),
          if (bitRateOptions?.isNotEmpty == true)
            ListTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(context.localized.qualityOptionsTitle),
                  ),
                  const Spacer(),
                  Text(bitRateOptions?.enabledFirst.keys.firstOrNull?.label(context) ?? "")
                ],
              ),
              onTap: () {
                Navigator.of(context).pop();
                openQualityOptions(context);
              },
            )
        ],
      );
    }

    Widget playbackSettings() {
      final playbackState = ref.watch(playBackModel);
      return ListView(
        key: const Key("PlaybackSettings"),
        shrinkWrap: true,
        controller: widget.controller,
        children: [
          navTitle(context.localized.playBackSettings, null),
          if (playbackState?.queue.isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.video_collection_rounded),
              title: const Text("Show queue"),
              onTap: () {
                Navigator.of(context).pop();
                ref.read(videoPlayerProvider).pause();
                showFullScreenItemQueue(
                  context,
                  items: playbackState?.queue ?? [],
                  currentItem: playbackState?.item,
                  onSectionReorder: (section, oldIndex, newIndex) {
                    return ref.read(videoPlayerProvider.notifier).reorderAudioQueueSection(
                          section,
                          oldIndex,
                          newIndex,
                        );
                  },
                  playSelected: ref.read(videoPlayerProvider.notifier).playAudioQueueItem,
                );
              },
            )
        ],
      );
    }

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (page) {
              1 => playbackSettings(),
              2 => itemInfo(currentItem, context),
              _ => mainPage(),
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  ListView itemInfo(ItemBaseModel? currentItem, BuildContext context) {
    return ListView(
      shrinkWrap: true,
      controller: widget.controller,
      children: [
        navTitle(currentItem?.title, currentItem?.subTextShort(context.localized)),
        if (currentItem != null) ...{
          if (currentItem.type == FladderItemType.episode)
            ListTile(
              onTap: () {
                Navigator.of(context).pop();
                widget.minimizePlayer();
                (this as EpisodeModel).parentBaseModel.navigateTo(context);
              },
              title: Text(context.localized.openShow),
            ),
          ListTile(
            onTap: () async {
              Navigator.of(context).pop();
              widget.minimizePlayer();
              await currentItem.navigateTo(context);
            },
            title: Text(context.localized.showDetails),
          ),
          if (currentItem.type != FladderItemType.boxset)
            ListTile(
              onTap: () async {
                await addItemToCollection(context, [currentItem]);
                if (context.mounted) {
                  context.refreshData();
                }
              },
              title: Text(context.localized.addToCollection),
            ),
          if (currentItem.type != FladderItemType.playlist)
            ListTile(
              onTap: () async {
                await addItemToPlaylist(context, [currentItem]);
                if (context.mounted) {
                  context.refreshData();
                }
              },
              title: Text(context.localized.addToPlaylist),
            ),
          ListTile(
            onTap: () async {
              final response = await ref
                  .read(userProvider.notifier)
                  .setAsFavorite(!(currentItem.userData.isFavourite == true), currentItem.id);
              final newItem = currentItem.copyWith(userData: response?.body);
              final playbackModel = switch (ref.read(playBackModel)) {
                DirectPlaybackModel value => value.copyWith(item: newItem),
                TranscodePlaybackModel value => value.copyWith(item: newItem),
                OfflinePlaybackModel value => value.copyWith(item: newItem),
                _ => null
              };
              ref.read(playBackModel.notifier).update((state) => playbackModel);
              Navigator.of(context).pop();
            },
            title: Text(currentItem.userData.isFavourite == true
                ? context.localized.removeAsFavorite
                : context.localized.addAsFavorite),
          ),
          ListTile(
            onTap: () {
              Navigator.of(context).pop();
              showInfoScreen(context, currentItem);
            },
            title: Text(context.localized.info),
          ),
        }
      ],
    );
  }

  Widget navTitle(String? title, String? subText) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            BackButton(
              onPressed: () => setState(() => page = 0),
            ),
            const SizedBox(width: 16),
            Column(
              children: [
                if (title != null)
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                if (subText != null)
                  Text(
                    subText,
                    style: Theme.of(context).textTheme.titleMedium,
                  )
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Takes a subtitle file away mid-watch. The dialog works out who can do
/// it (Jellyfin for an admin, Bazarr for a file it knows) and does it; this
/// switches the track off if it was playing, and waits for the server's new
/// numbering before trusting the list again.
Future<void> _removeSubtitle(
  BuildContext context,
  WidgetRef ref,
  PlaybackModel playbackModel,
  SubStreamModel subModel,
) async {
  final localized = context.localized;
  final name = subModel.fileName.isNotEmpty ? subModel.fileName : subModel.displayTitle;
  final choice = await confirmRemoveSubtitle(
    context,
    ref,
    itemId: playbackModel.item.id,
    mediaSourceId: playbackModel.mediaStreams?.currentVersionStream?.id,
    index: subModel.index,
    path: subModel.path,
    label: name,
  );
  if (choice == null) return;
  final wasOn = await _hideSubtitle(ref, subModel);
  final relisted = await scheduleSubtitleRemoval(
    ref,
    choice,
    name: shortSubtitleName(name),
    localized: localized,
    onUndone: () => _restoreSubtitle(ref, playbackModel.item.id, subModel, turnOn: wasOn),
  );
  if (relisted == null) return;
  _subtitleLog.info('Removed subtitle index=${subModel.index} "$name" of item=${playbackModel.item.id}');
  await _awaitSubtitleGone(ref, playbackModel.item.id, subModel, relisted: relisted);
}

/// Takes the row away at once and switches the track off if it was the one
/// playing. Resolves with whether it was.
Future<bool> _hideSubtitle(WidgetRef ref, SubStreamModel subModel) async {
  final playing = ref.read(playBackModel);
  if (playing == null) return false;
  _markChanged(ref, playing);
  final wasOn = playing.mediaStreams?.defaultSubStreamIndex == subModel.index;
  ref.read(playBackModel.notifier).update((state) => state?.removeSubtitle(subModel.index));
  if (wasOn) {
    final current = ref.read(playBackModel) ?? playing;
    final deselected = await current.setSubtitle(SubStreamModel.no(), ref.read(videoPlayerProvider));
    if (deselected != null) ref.read(playBackModel.notifier).update((_) => deselected);
  }
  return wasOn;
}

/// Puts an undone row back where it was - nothing was deleted, so its
/// number still holds - and the track on again if it was playing.
Future<void> _restoreSubtitle(WidgetRef ref, String itemId, SubStreamModel subModel, {required bool turnOn}) async {
  final latest = ref.read(playBackModel);
  final listed = latest?.mediaStreams?.subStreams;
  if (latest == null || listed == null || latest.item.id != itemId) return;
  if (listed.any((sub) => sub.index == subModel.index)) return;
  final at = listed.indexWhere((sub) => sub.index > subModel.index);
  final restored = [...listed]..insert(at == -1 ? listed.length : at, subModel);
  ref.read(playBackModel.notifier).update((_) => latest.replaceSubtitles(restored));
  if (turnOn) await _selectSubtitle(ref, subModel);
}

/// The server's own numbering once its refresh lands. The refresh
/// renumbers the external subtitles that are left, so until then the other
/// rows carry old numbers - removal finds its file by path, so that cannot
/// take the wrong one.
Future<void> _awaitSubtitleGone(WidgetRef ref, String itemId, SubStreamModel subModel, {required bool relisted}) async {
  final current = ref.read(playBackModel);
  // Playback may have moved on to another item inside the undo window.
  if (current == null || current.item.id != itemId) return;
  _markChanged(ref, current);
  if (!relisted) return;
  await ref
      .read(playbackModelHelper)
      .awaitSubtitleDeletion(current, subModel.index, deletedPath: subModel.path);
}

Future<void> showSubSelection(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) {
      return TvDialogFrame(
        child: Consumer(
          builder: (context, ref, child) {
            final playbackModel = ref.watch(playBackModel);
            final player = ref.watch(videoPlayerProvider);
            final canFind = canFindSubtitles(ref.watch(userProvider));
            final mightRemove = mightRemoveSubtitles(ref);
            // subStreams builds a new list (and a new "Off" entry) on every
            // read, so read it once and pair rows with suffixes by position.
            final streams = playbackModel?.subStreams ?? const <SubStreamModel>[];
            final suffixes = distinctSubtitleSuffixes(streams.map((s) => s.fileName).toList());
            return SimpleDialog(
              contentPadding: const EdgeInsets.only(top: 8, bottom: 24),
              title: Row(
                spacing: 8,
                children: [
                  Text(context.localized.subtitle),
                  const Spacer(),
                  if (playbackModel != null && playbackModel is! OfflinePlaybackModel) ...[
                    IconButton.outlined(
                      tooltip: context.localized.refreshSubtitles,
                      onPressed: () => _refreshSubtitles(context, ref, playbackModel),
                      icon: const Icon(IconsaxPlusLinear.refresh),
                    ),
                  ],
                  if (player.backend == PlayerOptions.libMPV || player.backend == PlayerOptions.libMDK)
                    IconButton.outlined(
                        onPressed: () {
                          Navigator.pop(context);
                          showSubtitleControls(
                            context: context,
                            label: context.localized.subtitleConfiguration,
                          );
                        },
                        icon: const Icon(Icons.display_settings_rounded)),
                  const TvDialogClose(),
                ],
              ),
              children: [
                if (playbackModel != null)
                  ...streams.indexed.map(
                  (entry) {
                    final (position, subModel) = entry;
                    final suffix = suffixes.elementAtOrNull(position) ?? subModel.fileName;
                    final selected = playbackModel.mediaStreams?.defaultSubStreamIndex == subModel.index;
                    // Downloads of one language share a display title, so the
                    // file name behind them is what tells two rows apart.
                    final details = [
                      if (subModel.language.isNotEmpty) subModel.language.capitalize(),
                      if (subModel.isExternal && suffix.isNotEmpty) shortSubtitleName(suffix)
                      else if (!subModel.isExternal && subModel.index != -1) context.localized.subtitleManagerEmbedded,
                    ].join(' • ');
                    final online = playbackModel is! OfflinePlaybackModel;
                    // Only files next to the video can be swapped or taken
                    // away; a track inside the container is part of the file.
                    final external = online && subModel.isExternal && subModel.index != -1;
                    final canReplace = external && canFind;
                    final canRemove = external && mightRemove;
                    final canFix = online && mightFixSubtitle(ref, subModel);
                    final canTime = subModel.index != -1 && player.supportsSubtitleDelay;
                    final canSync = external && (ref.read(userProvider)?.bazarrCredentials?.isConfigured ?? false);
                    return ListTile(
                      title: Text(subModel.label(context)),
                      tileColor: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3) : null,
                      subtitle: details.isNotEmpty
                          ? Opacity(
                              opacity: 0.6,
                              child: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
                            )
                          : null,
                      trailing: canReplace || canRemove || canFix || canTime
                          ? PopupMenuButton<String>(
                              tooltip: context.localized.moreOptions,
                              icon: const Icon(IconsaxPlusLinear.more),
                              onSelected: (value) => _onSubtitleMenu(context, ref, playbackModel, subModel, value),
                              itemBuilder: (context) => [
                                if (canTime)
                                  PopupMenuItem(
                                    value: 'timing',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.timer_1),
                                      title: Text(context.localized.subtitleTimingAdjust),
                                    ),
                                  ),
                                if (canSync)
                                  PopupMenuItem(
                                    value: 'sync',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.sound),
                                      title: Text(context.localized.subtitleFixSync),
                                      subtitle: Text(context.localized.subtitleFixSyncHint),
                                    ),
                                  ),
                                if (canFix) ...[
                                  PopupMenuItem(
                                    value: 'fps',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.video_time),
                                      title: Text(context.localized.subtitleFixFrameRate),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'hi',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.headphone),
                                      title: Text(context.localized.subtitleFixRemoveHi),
                                    ),
                                  ),
                                ],
                                if (canSync) ...[
                                  PopupMenuItem(
                                    value: 'translate',
                                    child: ListTile(
                                      leading: const Icon(Icons.translate_rounded),
                                      title: Text(context.localized.subtitleFixTranslate),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'errors',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.magicpen),
                                      title: Text(context.localized.subtitleFixCommonErrors),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'caps',
                                    child: ListTile(
                                      leading: const Icon(Icons.text_fields_rounded),
                                      title: Text(context.localized.subtitleFixUppercase),
                                    ),
                                  ),
                                ],
                                if ((canTime || canSync || canFix) && (canReplace || canRemove))
                                  const PopupMenuDivider(),
                                if (canReplace)
                                  PopupMenuItem(
                                    value: 'replace',
                                    child: ListTile(
                                      leading: const Icon(IconsaxPlusLinear.arrow_swap_horizontal),
                                      title: Text(context.localized.subtitleReplace),
                                    ),
                                  ),
                                if (canRemove)
                                  PopupMenuItem(
                                    value: 'remove',
                                    child: ListTile(
                                      leading: Icon(IconsaxPlusLinear.trash, color: Theme.of(context).colorScheme.error),
                                      title: Text(context.localized.subtitleRemove),
                                    ),
                                  ),
                              ],
                            )
                          : null,
                      onTap: () => _selectSubtitle(ref, subModel),
                    );
                  },
                ),
                if (playbackModel != null &&
                    ((playbackModel.mediaStreams?.currentSubStream?.index ?? -1) != -1 ||
                        (playbackModel is! OfflinePlaybackModel && canFind)))
                  const Divider(height: 16, indent: 16, endIndent: 16),
                if (playbackModel != null && (playbackModel.mediaStreams?.currentSubStream?.index ?? -1) != -1)
                  Consumer(builder: (context, ref, _) {
                    final delay = ref.watch(subtitleTimingProvider.select((t) => t.delay));
                    final seconds = (delay.inMilliseconds.abs() / 1000).toStringAsFixed(2);
                    return ListTile(
                      leading: const Icon(IconsaxPlusLinear.timer_1),
                      title: Text(context.localized.subtitleTimingTitle),
                      subtitle: Text(switch (delay) {
                        Duration.zero => context.localized.subtitleTimingAsFile,
                        final d when d > Duration.zero => context.localized.subtitleTimingLaterBy(seconds),
                        _ => context.localized.subtitleTimingEarlierBy(seconds),
                      }),
                      trailing: const Icon(IconsaxPlusLinear.arrow_right_3),
                      onTap: () {
                        ref.read(subtitleTimingProvider.notifier).show();
                        Navigator.of(context).maybePop();
                      },
                    );
                  }),
                if (playbackModel != null && playbackModel is! OfflinePlaybackModel && canFind)
                  ListTile(
                    leading: const Icon(IconsaxPlusLinear.search_normal_1),
                    title: Text(context.localized.subtitleFindMore),
                    onTap: () => _findSubtitles(context, ref, playbackModel),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

/// What a subtitle row's menu does.
Future<void> _onSubtitleMenu(
  BuildContext context,
  WidgetRef ref,
  PlaybackModel playbackModel,
  SubStreamModel subModel,
  String value,
) async {
  final localized = context.localized;
  final picker = ModalRoute.of(context);
  switch (value) {
    case 'replace':
      await _findSubtitles(context, ref, playbackModel, replacing: subModel);
    case 'remove':
      await _removeSubtitle(context, ref, playbackModel, subModel);
    case 'timing':
      // The bar works on the track that is on, and wants the picture free.
      if (playbackModel.mediaStreams?.defaultSubStreamIndex != subModel.index) await _selectSubtitle(ref, subModel);
      ref.read(subtitleTimingProvider.notifier).show();
      _closePicker(picker);
    case 'sync':
      _closePicker(picker);
      ref.read(subtitleTimingProvider.notifier).show(pinned: false);
      await applySubtitleFixInPlayer(ref, localized, subModel, const SyncToAudioFix());
    case 'fps':
      final fix = await askFrameRate(context, videoRate: playbackModel.mediaStreams?.videoStreams.firstOrNull?.frameRate);
      if (fix == null) return;
      _closePicker(picker);
      ref.read(subtitleTimingProvider.notifier).show(pinned: false);
      await applySubtitleFixInPlayer(ref, localized, subModel, fix);
    case 'hi':
      _closePicker(picker);
      ref.read(subtitleTimingProvider.notifier).show(pinned: false);
      await applySubtitleFixInPlayer(ref, localized, subModel, const RemoveHearingImpairedFix());
    case 'errors' || 'caps':
      _closePicker(picker);
      ref.read(subtitleTimingProvider.notifier).show(pinned: false);
      await applySubtitleFixInPlayer(
          ref, localized, subModel, value == 'errors' ? const CommonErrorsFix() : const UppercaseFix());
    case 'translate':
      final fix = await askTranslation(context, ref);
      if (fix == null) return;
      _closePicker(picker);
      ref.read(subtitleTimingProvider.notifier).show(pinned: false);
      await applySubtitleFixInPlayer(ref, localized, subModel, fix);
  }
}

/// Switches the live playback to [subModel], for code outside this file.
Future<void> selectSubtitleInPlayer(WidgetRef ref, SubStreamModel subModel) => _selectSubtitle(ref, subModel);

/// Switches the live playback to [subModel], local-only under SyncPlay so the
/// group is not paused for a caption change.
Future<void> _selectSubtitle(WidgetRef ref, SubStreamModel subModel) async {
  final playbackModel = ref.read(playBackModel);
  if (playbackModel == null) return;
  final player = ref.read(videoPlayerProvider);

  Future<void> doSwitch() async {
    final newModel = await playbackModel.setSubtitle(subModel, player);
    ref.read(playBackModel.notifier).update((state) => newModel);
    if (newModel != null) {
      await ref.read(playbackModelHelper).shouldReload(
            newModel,
            isLocalTrackSwitch: true,
          );
    }
  }

  if (ref.read(isSyncPlayActiveProvider)) {
    await ref.read(syncPlayProvider.notifier).runLocalOnly(doSwitch);
  } else {
    await doSwitch();
  }
}

/// Finds subtitles mid-watch. The finder waits for the server to list its
/// pick; once it does, the new track is switched on - you searched for it,
/// you want it - and the picker gets out of the way so you can see it. With
/// [replacing], the old file goes once the new one plays. The confirmation
/// offers to try another, for when the pick turns out to be off after all.
Future<void> _findSubtitles(
  BuildContext context,
  WidgetRef ref,
  PlaybackModel playbackModel, {
  SubStreamModel? replacing,
}) async {
  final localized = context.localized;
  // The navigator outlives the picker this was opened from, so "try
  // another" still has somewhere to open the finder.
  final navigatorContext = Navigator.of(context).context;
  // The picker, if this came from one - the only thing to close afterwards.
  // Opened again from "try another" there is none, and closing "whatever is
  // on top" then took the player itself down to the mini player.
  final picker = ModalRoute.of(context);
  final downloaded = await showSubtitleFinder(
    context,
    itemId: playbackModel.item.id,
    itemName: playbackModel.item.detailedName(localized) ?? playbackModel.item.name,
    mediaSourceId: playbackModel.mediaStreams?.currentVersionStream?.id,
    replacingName: replacing == null
        ? null
        : (replacing.fileName.isNotEmpty ? replacing.fileName : replacing.displayTitle),
    replacingLanguage: replacing?.language,
  );
  if (downloaded == null) return;
  if (downloaded.pending) {
    FladderSnack.show(localized.subtitleSavedPending, duration: const Duration(seconds: 8));
    return;
  }

  try {
    final current = ref.read(playBackModel) ?? playbackModel;
    await ref.read(playbackModelHelper).refreshSubtitleStreams(
          current,
          attempts: 4,
          retryDelay: const Duration(milliseconds: 1500),
        );
    final path = downloaded.stream?.path;
    final listed = ref.read(playBackModel)?.subStreams ?? const <SubStreamModel>[];
    final target = listed.firstWhereOrNull((sub) => path != null && sub.path == path) ??
        listed.firstWhereOrNull((sub) => sub.index == downloaded.stream?.index && sub.isExternal);
    if (target == null) {
      FladderSnack.show(localized.subtitleDownloadedNotListed, duration: const Duration(seconds: 8));
      return;
    }
    // Bazarr writes over a file of the same name, so the new subtitle can be
    // the track that is already on: switch it off and on so the player
    // reads the file again.
    if (ref.read(playBackModel)?.mediaStreams?.defaultSubStreamIndex == target.index) {
      await _selectSubtitle(ref, SubStreamModel.no());
    }
    await _selectSubtitle(ref, target);
    _closePicker(picker);
    _markChanged(ref, current);

    if (replacing != null && replacing.path != target.path) {
      final removed = await _removeReplaced(ref, replacing);
      if (!removed) {
        FladderSnack.show(localized.subtitleReplaceKeptOld(shortSubtitleName(replacing.fileName)),
            duration: const Duration(seconds: 8));
      }
    }

    FladderSnack.show(
      localized.subtitleNowShowing(target.fileName.isNotEmpty ? shortSubtitleName(target.fileName) : target.displayTitle),
      duration: const Duration(seconds: 10),
      actionLabel: localized.subtitleTryAnother,
      onActionPressed: () {
        final latest = ref.read(playBackModel);
        if (latest == null || !navigatorContext.mounted) return;
        final again = latest.subStreams?.firstWhereOrNull((sub) => sub.path == target.path) ?? target;
        _findSubtitles(navigatorContext, ref, latest, replacing: again);
      },
    );
  } catch (error) {
    _subtitleLog.warning('Switching to the downloaded subtitle failed: $error');
    FladderSnack.show(localized.subtitleDownloadedNotListed, duration: const Duration(seconds: 8));
  }
}

void _markChanged(WidgetRef ref, PlaybackModel playback) =>
    markSubtitlesChanged(ref.read(subtitleChangeProvider.notifier), playback.item.id, playback.item.parentId);

/// Closes the subtitle picker [route] if it is still open - and nothing
/// else.
void _closePicker(ModalRoute<dynamic>? route) {
  if (route is! PopupRoute || !route.isActive) return;
  route.navigator?.removeRoute(route);
}

/// The file a replacement took the place of. No second question - the
/// viewer asked for the swap - and blocked in Bazarr when Bazarr downloaded
/// it, so it does not come back. Resolves with whether it is gone.
Future<bool> _removeReplaced(WidgetRef ref, SubStreamModel replaced) async {
  final latest = ref.read(playBackModel);
  // Numbers moved when the new file arrived: find the old one by its file.
  final old = latest?.subStreams?.firstWhereOrNull((sub) => replaced.path != null && sub.path == replaced.path);
  if (latest == null || old == null) return true;
  final actions = ref.read(subtitleFileActionsProvider);
  try {
    final plan = await actions.plan(
      itemId: latest.item.id,
      mediaSourceId: latest.mediaStreams?.currentVersionStream?.id,
      index: old.index,
      path: old.path,
    );
    if (!plan.possible) return false;
    final relisted = await actions.remove(plan, block: plan.canBlock);
    await _hideSubtitle(ref, old);
    await _awaitSubtitleGone(ref, latest.item.id, old, relisted: relisted);
    return true;
  } catch (error) {
    _subtitleLog.warning('Removing the replaced subtitle failed: $error');
    return false;
  }
}

/// Re-lists the item's subtitle files without interrupting playback. An
/// admin account also has the server scan the item first, which is what
/// picks up a file Bazarr (or a person) dropped next to the media.
Future<void> _refreshSubtitles(BuildContext context, WidgetRef ref, PlaybackModel playbackModel) async {
  final localized = context.localized;
  final isAdmin = ref.read(userProvider)?.policy?.isAdministrator ?? false;
  FladderSnack.show(localized.refreshingSubtitles, duration: const Duration(seconds: 2));
  try {
    final added = await ref.read(playbackModelHelper).refreshSubtitleStreams(
          playbackModel,
          scanServer: true,
          attempts: isAdmin ? 4 : 1,
          retryDelay: const Duration(milliseconds: 2500),
        );
    if (added == null) return;
    FladderSnack.show(added.isEmpty ? localized.noNewSubtitlesFound : localized.newSubtitlesFound(added.length));
  } catch (error) {
    _subtitleLog.warning('Refreshing subtitles failed: $error');
    FladderSnack.show('$error', duration: const Duration(seconds: 6));
  }
}

Future<void> showAudioSelection(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) {
      return TvDialogFrame(
        child: Consumer(
          builder: (context, ref, child) {
            final playbackModel = ref.watch(playBackModel);
            final player = ref.watch(videoPlayerProvider);
            return SimpleDialog(
              contentPadding: const EdgeInsets.only(top: 8, bottom: 24),
              title: Row(
                children: [
                  Text(context.localized.audio(1)),
                  const Spacer(),
                  const TvDialogClose(),
                ],
              ),
              children: playbackModel?.audioStreams?.mapIndexed(
                (index, audioStream) {
                  final selected = playbackModel.mediaStreams?.defaultAudioStreamIndex == audioStream.index;
                  return ListTile(
                      title: Text(audioStream.label(context)),
                      tileColor: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3) : null,
                      subtitle: audioStream.language.isNotEmpty
                          ? Opacity(opacity: 0.6, child: Text(audioStream.language.capitalize()))
                          : null,
                      onTap: () async {
                        Future<void> doSwitch() async {
                          final newModel = await playbackModel.setAudio(audioStream, player);
                          ref.read(playBackModel.notifier).update((state) => newModel);
                          if (newModel != null) {
                            await ref.read(playbackModelHelper).shouldReload(
                                  newModel,
                                  isLocalTrackSwitch: true,
                                );
                          }
                        }

                        if (ref.read(isSyncPlayActiveProvider)) {
                          await ref.read(syncPlayProvider.notifier).runLocalOnly(doSwitch);
                        } else {
                          await doSwitch();
                        }
                      });
                },
              ).toList(),
            );
          },
        ),
      );
    },
  );
}

Future<void> showPlaybackSpeed(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) {
      return TvDialogFrame(
        child: StatefulBuilder(builder: (context, setState) {
          return Consumer(
            builder: (context, ref, child) {
              final player = ref.watch(videoPlayerProvider);
              final lastSpeed = ref.watch(playbackRateProvider);
              return SimpleDialog(
                contentPadding: const EdgeInsets.only(top: 8, bottom: 24),
                title: Row(children: [
                  Text(context.localized.playbackRate),
                  const Spacer(),
                  const TvDialogClose(),
                ]),
                children: [
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text("${context.localized.speed}: "),
                        Flexible(
                          child: SizedBox(
                            width: 250,
                            child: FladderSlider(
                              min: 0.25,
                              max: 3,
                              value: lastSpeed,
                              divisions: 55,
                              onChanged: (value) {
                                ref.read(playbackRateProvider.notifier).state = value;
                                player.setSpeed(value);
                              },
                            ),
                          ),
                        ),
                        Text("x${lastSpeed.toStringAsFixed(2)}")
                      ].addInBetween(const SizedBox(width: 8)),
                    ),
                  )
                ],
              );
            },
          );
        }),
      );
    },
  );
}

Future<void> showOrientationOptions(BuildContext context, WidgetRef ref) async {
  Set<DeviceOrientation> orientations = ref
      .read(videoPlayerSettingsProvider
          .select((value) => value.allowedOrientations ?? Set.from(DeviceOrientation.values)))
      .toSet();

  void toggleOrientation(DeviceOrientation orientation) {
    if (orientations.contains(orientation) && orientations.length > 1) {
      orientations.remove(orientation);
    } else {
      orientations.add(orientation);
    }
  }

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(builder: (context, state) {
        return SimpleDialog(
          contentPadding: const EdgeInsets.only(top: 8, bottom: 24),
          title: Row(children: [
            Text(context.localized.playerSettingsOrientationTitle),
            const Spacer(),
            const TvDialogClose(),
          ]),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Divider(),
                  ...DeviceOrientation.values.map(
                    (orientation) => CheckboxListTile(
                      title: Text(orientation.label(context)),
                      value: orientations.contains(orientation),
                      onChanged: (value) {
                        state(() => toggleOrientation(orientation));
                      },
                    ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(context.localized.cancel),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          ref.read(videoPlayerSettingsProvider.notifier).toggleOrientation(orientations);
                        },
                        child: Text(context.localized.save),
                      ),
                    ].addInBetween(const SizedBox(width: 8)),
                  )
                ].addInBetween(const SizedBox(width: 8)),
              ),
            )
          ],
        );
      });
    },
  );
}

// Lands in cast_log.txt: the crash-log filter forwards loggers whose name
// starts with "Cast".
final _subtitleLog = Logger('CastSubtitleDelete');

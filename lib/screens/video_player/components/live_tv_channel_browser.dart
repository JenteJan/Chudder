import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/playback/live_tv_playback_model.dart';
import 'package:fladder/providers/live_tv_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/localization_helper.dart';

/// Shows the Live TV channel browser as a side panel/drawer.
void showLiveTvChannelBrowser(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => LiveTvChannelBrowser(
        scrollController: scrollController,
      ),
    ),
  );
}

/// Channel browser widget for switching channels during live TV playback.
class LiveTvChannelBrowser extends ConsumerWidget {
  final ScrollController scrollController;

  const LiveTvChannelBrowser({
    required this.scrollController,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(liveTvChannelsProvider);
    final currentChannel = ref.watch(currentLiveTvChannelProvider);
    final currentPlayback = ref.watch(playBackModel);
    
    // Get current channel from playback model if available
    final activeChannelId = currentPlayback is LiveTvPlaybackModel
        ? currentPlayback.channel.id
        : currentChannel?.id;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(IconsaxPlusBold.monitor),
                const SizedBox(width: 12),
                Text(
                  context.localized.channelBrowser,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const Divider(),
          // Channel list
          Expanded(
            child: channelsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        IconsaxPlusLinear.warning_2,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 8),
                      Text(context.localized.somethingWentWrong),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref.read(liveTvChannelsProvider.notifier).refresh(),
                        icon: const Icon(IconsaxPlusLinear.refresh),
                        label: Text(context.localized.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (channels) {
                if (channels.isEmpty) {
                  return Center(
                    child: Text(context.localized.noChannelsAvailable),
                  );
                }
                return ListView.builder(
                  controller: scrollController,
                  itemCount: channels.length,
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    final isActive = channel.id == activeChannelId;
                    return _ChannelListTile(
                      channel: channel,
                      isActive: isActive,
                      onTap: () => _switchChannel(context, ref, channel),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switchChannel(
    BuildContext context,
    WidgetRef ref,
    LiveTvChannelDto channel,
  ) async {
    // Close the browser
    Navigator.of(context).pop();

    // Update current channel state
    ref.read(currentLiveTvChannelProvider.notifier).state = channel;

    // Switch to the new channel
    await ref.read(videoPlayerProvider.notifier).playLiveTvChannel(channel);
  }
}

class _ChannelListTile extends StatelessWidget {
  final LiveTvChannelDto channel;
  final bool isActive;
  final VoidCallback onTap;

  const _ChannelListTile({
    required this.channel,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      selected: isActive,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: _buildChannelIcon(context),
      title: Text(
        channel.name ?? 'Unknown Channel',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: channel.category != null
          ? Text(
              _getCategoryLabel(context, channel.category!),
              style: Theme.of(context).textTheme.bodySmall,
            )
          : null,
      trailing: isActive
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.localized.liveIndicator,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            )
          : null,
    );
  }

  Widget _buildChannelIcon(BuildContext context) {
    if (channel.iconUrl != null && channel.iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: FladderTheme.smallShape.borderRadius,
        child: SizedBox(
          width: 48,
          height: 48,
          child: CachedNetworkImage(
            imageUrl: channel.iconUrl!,
            fit: BoxFit.contain,
            placeholder: (context, url) => _buildPlaceholderIcon(context),
            errorWidget: (context, url, error) => _buildPlaceholderIcon(context),
          ),
        ),
      );
    }
    return _buildPlaceholderIcon(context);
  }

  Widget _buildPlaceholderIcon(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: FladderTheme.smallShape.borderRadius,
      ),
      child: Icon(
        IconsaxPlusBold.monitor,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
      ),
    );
  }

  String _getCategoryLabel(BuildContext context, LiveTvChannelCategory category) {
    return switch (category) {
      LiveTvChannelCategory.general => context.localized.categoryGeneral,
      LiveTvChannelCategory.sports => context.localized.categorySports,
      LiveTvChannelCategory.cinema => context.localized.categoryCinema,
      LiveTvChannelCategory.kids => context.localized.categoryKids,
      LiveTvChannelCategory.documentary => context.localized.categoryDocumentary,
      LiveTvChannelCategory.music => context.localized.categoryMusic,
      LiveTvChannelCategory.news => context.localized.categoryNews,
      LiveTvChannelCategory.other => context.localized.categoryOther,
      _ => '',
    };
  }
}


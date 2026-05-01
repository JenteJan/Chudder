import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/models/media_playback_model.dart';
import 'package:fladder/providers/jellybot_live_tv_provider.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/screens/shared/nested_scaffold.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/sliver_list_padding.dart';
import 'package:fladder/util/custom_cache_manager.dart';
import 'package:fladder/widgets/full_screen_helpers/full_screen_wrapper.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/pull_to_refresh.dart';

@RoutePage()
class JellybotLiveTvChannelsScreen extends ConsumerStatefulWidget {
  const JellybotLiveTvChannelsScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _JellybotLiveTvChannelsScreenState();
}

class _JellybotLiveTvChannelsScreenState
    extends ConsumerState<JellybotLiveTvChannelsScreen> {
  final GlobalKey<RefreshIndicatorState>? refreshKey = GlobalKey();
  bool refreshing = false;

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(jellybotLiveTvChannelsProvider);
    final padding = AdaptiveLayout.adaptivePadding(context);

    return NestedScaffold(
      body: PullToRefresh(
        refreshOnStart: true,
        refreshKey: refreshKey,
        onRefresh: () async {
          if (refreshing) return;
          setState(() => refreshing = true);
          try {
            await ref.read(jellybotLiveTvChannelsProvider.notifier).refresh();
          } finally {
            if (mounted) {
              setState(() => refreshing = false);
            }
          }
        },
        child: (context) => AnimatedOpacity(
          opacity: refreshing ? 0.75 : 1.0,
          duration: const Duration(milliseconds: 175),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const DefaultSliverTopBadding(),
              if (AdaptiveLayout.viewSizeOf(context) == ViewSize.phone)
                SliverAppBar(
                  floating: true,
                  title: Row(
                    children: [
                      const Icon(IconsaxPlusBold.monitor),
                      const SizedBox(width: 12),
                      Text(context.localized.liveTv),
                    ],
                  ),
                ),
              channelsAsync.when(
                loading: () => const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stack) => SliverFillRemaining(
                  child: _buildErrorState(context, error),
                ),
                data: (channels) {
                  if (channels.isEmpty) {
                    return SliverFillRemaining(
                      child: _buildEmptyState(context),
                    );
                  }
                  return _buildChannelRows(context, channels, padding);
                },
              ),
              DefaultSliverBottomPadding(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              IconsaxPlusLinear.warning_2,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              context.localized.somethingWentWrong,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(jellybotLiveTvChannelsProvider.notifier).refresh(),
              icon: const Icon(IconsaxPlusLinear.refresh),
              label: Text(context.localized.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              IconsaxPlusLinear.monitor,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              context.localized.noChannelsAvailable,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => ref.read(jellybotLiveTvChannelsProvider.notifier).refresh(),
              icon: const Icon(IconsaxPlusLinear.refresh),
              label: Text(context.localized.retry),
            ),
          ],
        ),
      ),
    );
  }

  /// Group channels by category and build horizontal rows
  Widget _buildChannelRows(BuildContext context, List<LiveTvChannelDto> channels, EdgeInsets padding) {
    // Group channels by category
    final groupedChannels = groupBy<LiveTvChannelDto, LiveTvChannelCategory?>(
      channels,
      (channel) => channel.category,
    );

    // Define category order for consistent display
    final categoryOrder = [
      LiveTvChannelCategory.general,
      LiveTvChannelCategory.news,
      LiveTvChannelCategory.sports,
      LiveTvChannelCategory.cinema,
      LiveTvChannelCategory.documentary,
      LiveTvChannelCategory.kids,
      LiveTvChannelCategory.music,
      LiveTvChannelCategory.other,
      null, // Channels without category
    ];

    // Sort categories according to order
    final sortedCategories = groupedChannels.keys.toList()
      ..sort((a, b) {
        final indexA = categoryOrder.indexOf(a);
        final indexB = categoryOrder.indexOf(b);
        return indexA.compareTo(indexB);
      });

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final category = sortedCategories[index];
          final categoryChannels = (groupedChannels[category] ?? []).toList()
            ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
          if (categoryChannels.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: _ChannelCategoryRow(
              category: category,
              channels: categoryChannels,
              contentPadding: padding,
              onChannelTap: _playChannel,
            ),
          );
        },
        childCount: sortedCategories.length,
      ),
    );
  }

  Future<void> _playChannel(LiveTvChannelDto channel) async {
    if (channel.streamUrl == null || channel.streamUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.localized.streamNotAvailable)),
      );
      return;
    }

    // Set the current channel
    ref.read(currentJellybotLiveTvChannelProvider.notifier).state = channel;

    // Create and play the live TV stream
    final loaded = await ref.read(videoPlayerProvider.notifier).playLiveTvChannel(channel);

    if (!loaded) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.localized.streamNotAvailable)),
        );
      }
      return;
    }

    // Set player state to fullscreen and open the player
    ref.read(mediaPlaybackProvider.notifier).update(
          (state) => state.copyWith(state: VideoPlayerState.fullScreen),
        );

    if (mounted) {
      await ref.read(videoPlayerProvider.notifier).openPlayer(context);
      if (AdaptiveLayout.of(context).isDesktop) {
        fullScreenHelper.closeFullScreen(ref);
      }
    }
  }
}

/// A horizontal row of channels for a specific category
class _ChannelCategoryRow extends StatelessWidget {
  final LiveTvChannelCategory? category;
  final List<LiveTvChannelDto> channels;
  final EdgeInsets contentPadding;
  final Function(LiveTvChannelDto channel) onChannelTap;

  const _ChannelCategoryRow({
    required this.category,
    required this.channels,
    required this.contentPadding,
    required this.onChannelTap,
  });

  @override
  Widget build(BuildContext context) {
    return HorizontalList<LiveTvChannelDto>(
      contentPadding: contentPadding,
      label: _getCategoryLabel(context, category),
      height: 160,
      items: channels,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return LiveTvChannelCard(
          channel: channel,
          onTap: () => onChannelTap(channel),
        );
      },
    );
  }

  String _getCategoryLabel(BuildContext context, LiveTvChannelCategory? category) {
    if (category == null) return context.localized.categoryOther;
    return switch (category) {
      LiveTvChannelCategory.general => context.localized.categoryGeneral,
      LiveTvChannelCategory.sports => context.localized.categorySports,
      LiveTvChannelCategory.cinema => context.localized.categoryCinema,
      LiveTvChannelCategory.kids => context.localized.categoryKids,
      LiveTvChannelCategory.documentary => context.localized.categoryDocumentary,
      LiveTvChannelCategory.music => context.localized.categoryMusic,
      LiveTvChannelCategory.news => context.localized.categoryNews,
      LiveTvChannelCategory.other => context.localized.categoryOther,
      _ => context.localized.categoryOther,
    };
  }
}

/// Card widget for displaying a single TV channel
class LiveTvChannelCard extends StatelessWidget {
  final LiveTvChannelDto channel;
  final VoidCallback onTap;

  const LiveTvChannelCard({
    required this.channel,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FocusButton(
      onTap: onTap,
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: FladderTheme.smallShape.borderRadius,
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: _buildChannelIcon(context),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                channel.name ?? 'Unknown',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelIcon(BuildContext context) {
    final iconUrl = channel.iconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: iconUrl,
          cacheManager: CustomCacheManager.instance,
          cacheKey: 'live_tv_${channel.id}',
          fit: BoxFit.contain,
          placeholder: (context, url) => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          errorWidget: (context, url, error) => _buildPlaceholderIcon(context),
        ),
      );
    }
    return _buildPlaceholderIcon(context);
  }

  Widget _buildPlaceholderIcon(BuildContext context) {
    return Icon(
      IconsaxPlusBold.monitor,
      size: 40,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
    );
  }
}

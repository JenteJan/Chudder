import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/jellyfin/jellybot.swagger.dart';
import 'package:fladder/providers/jellybot_api_provider.dart';

part 'live_tv_provider.g.dart';

/// Provider for fetching and caching Live TV channels from Jellybot API.
/// Returns empty list if API fails - this will hide Live TV from navigation.
@riverpod
class LiveTvChannels extends _$LiveTvChannels {
  @override
  Future<List<LiveTvChannelDto>> build() async {
    return _fetchChannels();
  }

  Future<List<LiveTvChannelDto>> _fetchChannels() async {
    try {
      final api = ref.read(jellybotApiProvider);
      final response = await api.apiLiveTvChannelsGet();
      return response.body ?? [];
    } catch (e) {
      // Return empty list on failure - this hides Live TV from navigation
      return [];
    }
  }

  /// Refresh the channel list
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchChannels());
  }
}

/// Provider to check if Live TV channels are available.
/// Used to conditionally show/hide Live TV in navigation.
@riverpod
bool hasLiveTvChannels(Ref ref) {
  final channelsAsync = ref.watch(liveTvChannelsProvider);
  return channelsAsync.maybeWhen(
    data: (channels) => channels.isNotEmpty,
    orElse: () => false,
  );
}

/// Provider for the currently selected Live TV channel during playback.
final currentLiveTvChannelProvider = StateProvider<LiveTvChannelDto?>((ref) => null);


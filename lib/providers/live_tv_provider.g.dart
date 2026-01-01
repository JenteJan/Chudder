// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'live_tv_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$hasLiveTvChannelsHash() => r'333f05e3307b2c9e75cfdf366b10f0959bb84d77';

/// Provider to check if Live TV channels are available.
/// Used to conditionally show/hide Live TV in navigation.
///
/// Copied from [hasLiveTvChannels].
@ProviderFor(hasLiveTvChannels)
final hasLiveTvChannelsProvider = AutoDisposeProvider<bool>.internal(
  hasLiveTvChannels,
  name: r'hasLiveTvChannelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hasLiveTvChannelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HasLiveTvChannelsRef = AutoDisposeProviderRef<bool>;
String _$liveTvChannelsHash() => r'35fde83202a6620faf6dbcb5c772dba5ee7ab69c';

/// Provider for fetching and caching Live TV channels from Jellybot API.
/// Returns empty list if API fails - this will hide Live TV from navigation.
///
/// Copied from [LiveTvChannels].
@ProviderFor(LiveTvChannels)
final liveTvChannelsProvider = AutoDisposeAsyncNotifierProvider<LiveTvChannels,
    List<LiveTvChannelDto>>.internal(
  LiveTvChannels.new,
  name: r'liveTvChannelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$liveTvChannelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$LiveTvChannels = AutoDisposeAsyncNotifier<List<LiveTvChannelDto>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jellybot_live_tv_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$hasJellybotLiveTvChannelsHash() =>
    r'1ee36b7e4161b9e1bf58a33bdaaeaa9c424b50bc';

/// Provider to check if Live TV channels are available.
/// Used to conditionally show/hide Live TV in navigation.
///
/// Copied from [hasJellybotLiveTvChannels].
@ProviderFor(hasJellybotLiveTvChannels)
final hasJellybotLiveTvChannelsProvider = AutoDisposeProvider<bool>.internal(
  hasJellybotLiveTvChannels,
  name: r'hasJellybotLiveTvChannelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$hasJellybotLiveTvChannelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef HasJellybotLiveTvChannelsRef = AutoDisposeProviderRef<bool>;
String _$jellybotLiveTvChannelsHash() =>
    r'7b2b089eab5a40d5f65f7b121f21b3ea8a5dd146';

/// Provider for fetching and caching Live TV channels from Jellybot API.
/// Returns empty list if API fails - this will hide Live TV from navigation.
///
/// Copied from [JellybotLiveTvChannels].
@ProviderFor(JellybotLiveTvChannels)
final jellybotLiveTvChannelsProvider = AutoDisposeAsyncNotifierProvider<
    JellybotLiveTvChannels, List<LiveTvChannelDto>>.internal(
  JellybotLiveTvChannels.new,
  name: r'jellybotLiveTvChannelsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$jellybotLiveTvChannelsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$JellybotLiveTvChannels
    = AutoDisposeAsyncNotifier<List<LiveTvChannelDto>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

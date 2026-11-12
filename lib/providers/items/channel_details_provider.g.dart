// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'channel_details_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ChannelDetails)
final channelDetailsProvider = ChannelDetailsFamily._();

final class ChannelDetailsProvider
    extends $NotifierProvider<ChannelDetails, ChannelModel?> {
  ChannelDetailsProvider._({
    required ChannelDetailsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'channelDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$channelDetailsHash();

  @override
  String toString() {
    return r'channelDetailsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChannelDetails create() => ChannelDetails();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChannelModel? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChannelModel?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChannelDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$channelDetailsHash() => r'267e6e7f5043e7a913d4c31dba20f3cb093e5adc';

final class ChannelDetailsFamily extends $Family
    with
        $ClassFamilyOverride<
          ChannelDetails,
          ChannelModel?,
          ChannelModel?,
          ChannelModel?,
          String
        > {
  ChannelDetailsFamily._()
    : super(
        retry: null,
        name: r'channelDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ChannelDetailsProvider call(String id) =>
      ChannelDetailsProvider._(argument: id, from: this);

  @override
  String toString() => r'channelDetailsProvider';
}

abstract class _$ChannelDetails extends $Notifier<ChannelModel?> {
  late final _$args = ref.$arg as String;
  String get id => _$args;

  ChannelModel? build(String id);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ChannelModel?, ChannelModel?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChannelModel?, ChannelModel?>,
              ChannelModel?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

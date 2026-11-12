// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'control_device_discovery_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ControlDeviceDiscovery)
final controlDeviceDiscoveryProvider = ControlDeviceDiscoveryProvider._();

final class ControlDeviceDiscoveryProvider
    extends
        $NotifierProvider<ControlDeviceDiscovery, ControlDeviceDiscoveryModel> {
  ControlDeviceDiscoveryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'controlDeviceDiscoveryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$controlDeviceDiscoveryHash();

  @$internal
  @override
  ControlDeviceDiscovery create() => ControlDeviceDiscovery();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlDeviceDiscoveryModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlDeviceDiscoveryModel>(value),
    );
  }
}

String _$controlDeviceDiscoveryHash() =>
    r'2d01dd615a1afd7dd6f3ec69dd332c341a0fdc81';

abstract class _$ControlDeviceDiscovery
    extends $Notifier<ControlDeviceDiscoveryModel> {
  ControlDeviceDiscoveryModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<ControlDeviceDiscoveryModel, ControlDeviceDiscoveryModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ControlDeviceDiscoveryModel,
                ControlDeviceDiscoveryModel
              >,
              ControlDeviceDiscoveryModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

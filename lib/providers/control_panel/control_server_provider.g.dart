// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'control_server_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ControlServer)
final controlServerProvider = ControlServerProvider._();

final class ControlServerProvider
    extends $NotifierProvider<ControlServer, ControlServerModel> {
  ControlServerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'controlServerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$controlServerHash();

  @$internal
  @override
  ControlServer create() => ControlServer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlServerModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlServerModel>(value),
    );
  }
}

String _$controlServerHash() => r'6b0310b063bd0de6ba7b332f056dd5da50648af4';

abstract class _$ControlServer extends $Notifier<ControlServerModel> {
  ControlServerModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ControlServerModel, ControlServerModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ControlServerModel, ControlServerModel>,
              ControlServerModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

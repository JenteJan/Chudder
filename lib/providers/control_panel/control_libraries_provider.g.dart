// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'control_libraries_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ControlLibraries)
final controlLibrariesProvider = ControlLibrariesProvider._();

final class ControlLibrariesProvider
    extends $NotifierProvider<ControlLibraries, ControlLibrariesModel> {
  ControlLibrariesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'controlLibrariesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$controlLibrariesHash();

  @$internal
  @override
  ControlLibraries create() => ControlLibraries();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlLibrariesModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlLibrariesModel>(value),
    );
  }
}

String _$controlLibrariesHash() => r'e3da05dc3d283260923cedee26a2069ad6ec2ab0';

abstract class _$ControlLibraries extends $Notifier<ControlLibrariesModel> {
  ControlLibrariesModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ControlLibrariesModel, ControlLibrariesModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ControlLibrariesModel, ControlLibrariesModel>,
              ControlLibrariesModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

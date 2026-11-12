// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'control_activity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ControlActivity)
final controlActivityProvider = ControlActivityProvider._();

final class ControlActivityProvider
    extends $NotifierProvider<ControlActivity, List<ControlActivityModel>> {
  ControlActivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'controlActivityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$controlActivityHash();

  @$internal
  @override
  ControlActivity create() => ControlActivity();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<ControlActivityModel> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<ControlActivityModel>>(value),
    );
  }
}

String _$controlActivityHash() => r'6bf669b9917ca9c694b6e0d498c57bbf1e77748c';

abstract class _$ControlActivity extends $Notifier<List<ControlActivityModel>> {
  List<ControlActivityModel> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref
            as $Ref<List<ControlActivityModel>, List<ControlActivityModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                List<ControlActivityModel>,
                List<ControlActivityModel>
              >,
              List<ControlActivityModel>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'control_livetv_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ControlLiveTv)
final controlLiveTvProvider = ControlLiveTvProvider._();

final class ControlLiveTvProvider
    extends $NotifierProvider<ControlLiveTv, ControlLiveTvModel> {
  ControlLiveTvProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'controlLiveTvProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$controlLiveTvHash();

  @$internal
  @override
  ControlLiveTv create() => ControlLiveTv();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ControlLiveTvModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ControlLiveTvModel>(value),
    );
  }
}

String _$controlLiveTvHash() => r'f82b3b1ae56471d190aa7fa8fb5a34a6ccd73761';

abstract class _$ControlLiveTv extends $Notifier<ControlLiveTvModel> {
  ControlLiveTvModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ControlLiveTvModel, ControlLiveTvModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ControlLiveTvModel, ControlLiveTvModel>,
              ControlLiveTvModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

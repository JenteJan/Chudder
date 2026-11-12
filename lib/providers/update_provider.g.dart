// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Update)
final updateProvider = UpdateProvider._();

final class UpdateProvider extends $NotifierProvider<Update, UpdatesModel> {
  UpdateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateHash();

  @$internal
  @override
  Update create() => Update();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdatesModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdatesModel>(value),
    );
  }
}

String _$updateHash() => r'43c92e539ff445127583023f01f3f14403fefd20';

abstract class _$Update extends $Notifier<UpdatesModel> {
  UpdatesModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<UpdatesModel, UpdatesModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UpdatesModel, UpdatesModel>,
              UpdatesModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

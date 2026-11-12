// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seerr_user_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SeerrUser)
final seerrUserProvider = SeerrUserProvider._();

final class SeerrUserProvider
    extends $NotifierProvider<SeerrUser, SeerrUserModel?> {
  SeerrUserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seerrUserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seerrUserHash();

  @$internal
  @override
  SeerrUser create() => SeerrUser();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeerrUserModel? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeerrUserModel?>(value),
    );
  }
}

String _$seerrUserHash() => r'75a43a03320f22923b8a367902a5bc3d3e13ea7c';

abstract class _$SeerrUser extends $Notifier<SeerrUserModel?> {
  SeerrUserModel? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SeerrUserModel?, SeerrUserModel?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SeerrUserModel?, SeerrUserModel?>,
              SeerrUserModel?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

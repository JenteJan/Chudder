// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seerr_request_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SeerrRequest)
final seerrRequestProvider = SeerrRequestProvider._();

final class SeerrRequestProvider
    extends $NotifierProvider<SeerrRequest, SeerrRequestModel> {
  SeerrRequestProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seerrRequestProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seerrRequestHash();

  @$internal
  @override
  SeerrRequest create() => SeerrRequest();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeerrRequestModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeerrRequestModel>(value),
    );
  }
}

String _$seerrRequestHash() => r'985de35a81ccf086e636c9dde24e5e0c7f3577c0';

abstract class _$SeerrRequest extends $Notifier<SeerrRequestModel> {
  SeerrRequestModel build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SeerrRequestModel, SeerrRequestModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SeerrRequestModel, SeerrRequestModel>,
              SeerrRequestModel,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seerr_search_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SeerrSearch)
final seerrSearchProvider = SeerrSearchProvider._();

final class SeerrSearchProvider
    extends $NotifierProvider<SeerrSearch, SeerrSearchModel> {
  SeerrSearchProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'seerrSearchProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$seerrSearchHash();

  @$internal
  @override
  SeerrSearch create() => SeerrSearch();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SeerrSearchModel value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SeerrSearchModel>(value),
    );
  }
}

String _$seerrSearchHash() => r'1af2cb2331703ecf0769fff2a410cf97e0f6c3e2';

abstract class _$SeerrSearch extends $Notifier<SeerrSearchModel> {
  SeerrSearchModel build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SeerrSearchModel, SeerrSearchModel>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SeerrSearchModel, SeerrSearchModel>,
              SeerrSearchModel,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

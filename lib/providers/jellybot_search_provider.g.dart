// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jellybot_search_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$jellybotProvidersHash() => r'b5a7b3a357318938349ccac25ef3a1714c335880';

/// See also [jellybotProviders].
@ProviderFor(jellybotProviders)
final jellybotProvidersProvider =
    AutoDisposeFutureProvider<List<IProvider>>.internal(
  jellybotProviders,
  name: r'jellybotProvidersProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$jellybotProvidersHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef JellybotProvidersRef = AutoDisposeFutureProviderRef<List<IProvider>>;
String _$jellybotSearchFiltersHash() =>
    r'65e3dbf40d3d960dd23c3643ce580fcd60c5b43c';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [jellybotSearchFilters].
@ProviderFor(jellybotSearchFilters)
const jellybotSearchFiltersProvider = JellybotSearchFiltersFamily();

/// See also [jellybotSearchFilters].
class JellybotSearchFiltersFamily
    extends Family<AsyncValue<List<ISearchFilter>>> {
  /// See also [jellybotSearchFilters].
  const JellybotSearchFiltersFamily();

  /// See also [jellybotSearchFilters].
  JellybotSearchFiltersProvider call(
    String providerId,
    MediaCategory category,
  ) {
    return JellybotSearchFiltersProvider(
      providerId,
      category,
    );
  }

  @override
  JellybotSearchFiltersProvider getProviderOverride(
    covariant JellybotSearchFiltersProvider provider,
  ) {
    return call(
      provider.providerId,
      provider.category,
    );
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'jellybotSearchFiltersProvider';
}

/// See also [jellybotSearchFilters].
class JellybotSearchFiltersProvider
    extends AutoDisposeFutureProvider<List<ISearchFilter>> {
  /// See also [jellybotSearchFilters].
  JellybotSearchFiltersProvider(
    String providerId,
    MediaCategory category,
  ) : this._internal(
          (ref) => jellybotSearchFilters(
            ref as JellybotSearchFiltersRef,
            providerId,
            category,
          ),
          from: jellybotSearchFiltersProvider,
          name: r'jellybotSearchFiltersProvider',
          debugGetCreateSourceHash:
              const bool.fromEnvironment('dart.vm.product')
                  ? null
                  : _$jellybotSearchFiltersHash,
          dependencies: JellybotSearchFiltersFamily._dependencies,
          allTransitiveDependencies:
              JellybotSearchFiltersFamily._allTransitiveDependencies,
          providerId: providerId,
          category: category,
        );

  JellybotSearchFiltersProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.providerId,
    required this.category,
  }) : super.internal();

  final String providerId;
  final MediaCategory category;

  @override
  Override overrideWith(
    FutureOr<List<ISearchFilter>> Function(JellybotSearchFiltersRef provider)
        create,
  ) {
    return ProviderOverride(
      origin: this,
      override: JellybotSearchFiltersProvider._internal(
        (ref) => create(ref as JellybotSearchFiltersRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        providerId: providerId,
        category: category,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<ISearchFilter>> createElement() {
    return _JellybotSearchFiltersProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is JellybotSearchFiltersProvider &&
        other.providerId == providerId &&
        other.category == category;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, providerId.hashCode);
    hash = _SystemHash.combine(hash, category.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin JellybotSearchFiltersRef
    on AutoDisposeFutureProviderRef<List<ISearchFilter>> {
  /// The parameter `providerId` of this provider.
  String get providerId;

  /// The parameter `category` of this provider.
  MediaCategory get category;
}

class _JellybotSearchFiltersProviderElement
    extends AutoDisposeFutureProviderElement<List<ISearchFilter>>
    with JellybotSearchFiltersRef {
  _JellybotSearchFiltersProviderElement(super.provider);

  @override
  String get providerId => (origin as JellybotSearchFiltersProvider).providerId;
  @override
  MediaCategory get category =>
      (origin as JellybotSearchFiltersProvider).category;
}
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package

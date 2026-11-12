// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ConnectivityStatus)
final connectivityStatusProvider = ConnectivityStatusProvider._();

final class ConnectivityStatusProvider
    extends $NotifierProvider<ConnectivityStatus, ConnectionState> {
  ConnectivityStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityStatusHash();

  @$internal
  @override
  ConnectivityStatus create() => ConnectivityStatus();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionState>(value),
    );
  }
}

String _$connectivityStatusHash() =>
    r'834fbf3eef0753c223270efa20f966362a783d2c';

abstract class _$ConnectivityStatus extends $Notifier<ConnectionState> {
  ConnectionState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ConnectionState, ConnectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectionState, ConnectionState>,
              ConnectionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

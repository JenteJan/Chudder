// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'syncplay_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for SyncPlay controller instance

@ProviderFor(SyncPlay)
final syncPlayProvider = SyncPlayProvider._();

/// Provider for SyncPlay controller instance
final class SyncPlayProvider
    extends $NotifierProvider<SyncPlay, SyncPlayState> {
  /// Provider for SyncPlay controller instance
  SyncPlayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayHash();

  @$internal
  @override
  SyncPlay create() => SyncPlay();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncPlayState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncPlayState>(value),
    );
  }
}

String _$syncPlayHash() => r'4cba9445cb6ec86fb97bc80e25efae0261eb7a57';

/// Provider for SyncPlay controller instance

abstract class _$SyncPlay extends $Notifier<SyncPlayState> {
  SyncPlayState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SyncPlayState, SyncPlayState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncPlayState, SyncPlayState>,
              SyncPlayState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Provider to check if currently in a SyncPlay session

@ProviderFor(isSyncPlayActive)
final isSyncPlayActiveProvider = IsSyncPlayActiveProvider._();

/// Provider to check if currently in a SyncPlay session

final class IsSyncPlayActiveProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Provider to check if currently in a SyncPlay session
  IsSyncPlayActiveProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isSyncPlayActiveProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isSyncPlayActiveHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isSyncPlayActive(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isSyncPlayActiveHash() => r'bf9cda97aa9130fed8fc6558481c02f10f815f99';

/// Provider for current SyncPlay group name

@ProviderFor(syncPlayGroupName)
final syncPlayGroupNameProvider = SyncPlayGroupNameProvider._();

/// Provider for current SyncPlay group name

final class SyncPlayGroupNameProvider
    extends $FunctionalProvider<String?, String?, String?>
    with $Provider<String?> {
  /// Provider for current SyncPlay group name
  SyncPlayGroupNameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayGroupNameProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayGroupNameHash();

  @$internal
  @override
  $ProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  String? create(Ref ref) {
    return syncPlayGroupName(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$syncPlayGroupNameHash() => r'f73f243808920efbfbfa467d1ba1234fec622283';

/// Provider for SyncPlay group state

@ProviderFor(syncPlayGroupState)
final syncPlayGroupStateProvider = SyncPlayGroupStateProvider._();

/// Provider for SyncPlay group state

final class SyncPlayGroupStateProvider
    extends
        $FunctionalProvider<
          SyncPlayGroupState,
          SyncPlayGroupState,
          SyncPlayGroupState
        >
    with $Provider<SyncPlayGroupState> {
  /// Provider for SyncPlay group state
  SyncPlayGroupStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayGroupStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayGroupStateHash();

  @$internal
  @override
  $ProviderElement<SyncPlayGroupState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SyncPlayGroupState create(Ref ref) {
    return syncPlayGroupState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncPlayGroupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncPlayGroupState>(value),
    );
  }
}

String _$syncPlayGroupStateHash() =>
    r'dff5dba3297066e06ff5ed1b9b273ee19bc27878';

/// Provider for SyncPlay correction runtime state (UI + diagnostics).

@ProviderFor(syncCorrectionState)
final syncCorrectionStateProvider = SyncCorrectionStateProvider._();

/// Provider for SyncPlay correction runtime state (UI + diagnostics).

final class SyncCorrectionStateProvider
    extends
        $FunctionalProvider<
          SyncCorrectionState,
          SyncCorrectionState,
          SyncCorrectionState
        >
    with $Provider<SyncCorrectionState> {
  /// Provider for SyncPlay correction runtime state (UI + diagnostics).
  SyncCorrectionStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncCorrectionStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncCorrectionStateHash();

  @$internal
  @override
  $ProviderElement<SyncCorrectionState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SyncCorrectionState create(Ref ref) {
    return syncCorrectionState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncCorrectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncCorrectionState>(value),
    );
  }
}

String _$syncCorrectionStateHash() =>
    r'0c623c5a3e9b99b5dc09c14b50d4cbf120151af9';

/// Provider for active correction strategy.

@ProviderFor(syncCorrectionStrategy)
final syncCorrectionStrategyProvider = SyncCorrectionStrategyProvider._();

/// Provider for active correction strategy.

final class SyncCorrectionStrategyProvider
    extends
        $FunctionalProvider<
          SyncCorrectionStrategy,
          SyncCorrectionStrategy,
          SyncCorrectionStrategy
        >
    with $Provider<SyncCorrectionStrategy> {
  /// Provider for active correction strategy.
  SyncCorrectionStrategyProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncCorrectionStrategyProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncCorrectionStrategyHash();

  @$internal
  @override
  $ProviderElement<SyncCorrectionStrategy> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SyncCorrectionStrategy create(Ref ref) {
    return syncCorrectionStrategy(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncCorrectionStrategy value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncCorrectionStrategy>(value),
    );
  }
}

String _$syncCorrectionStrategyHash() =>
    r'eaa4de3db8e9d9155b6f41465462f087833744e0';

/// True when a SyncPlay-driven `_startPlayback` is currently in flight
/// (initial play, episode switch, rejoin). UI can use this to display
/// a loading indicator while the local player is being prepared.

@ProviderFor(syncPlayStartPlaybackInProgress)
final syncPlayStartPlaybackInProgressProvider =
    SyncPlayStartPlaybackInProgressProvider._();

/// True when a SyncPlay-driven `_startPlayback` is currently in flight
/// (initial play, episode switch, rejoin). UI can use this to display
/// a loading indicator while the local player is being prepared.

final class SyncPlayStartPlaybackInProgressProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// True when a SyncPlay-driven `_startPlayback` is currently in flight
  /// (initial play, episode switch, rejoin). UI can use this to display
  /// a loading indicator while the local player is being prepared.
  SyncPlayStartPlaybackInProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayStartPlaybackInProgressProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayStartPlaybackInProgressHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return syncPlayStartPlaybackInProgress(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$syncPlayStartPlaybackInProgressHash() =>
    r'883e5426c30e568f8374656112a2de902a98f5dc';

/// True when the group has an active item the local user could
/// resume from outside the player route.

@ProviderFor(syncPlayHasActivePlayback)
final syncPlayHasActivePlaybackProvider = SyncPlayHasActivePlaybackProvider._();

/// True when the group has an active item the local user could
/// resume from outside the player route.

final class SyncPlayHasActivePlaybackProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// True when the group has an active item the local user could
  /// resume from outside the player route.
  SyncPlayHasActivePlaybackProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayHasActivePlaybackProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayHasActivePlaybackHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return syncPlayHasActivePlayback(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$syncPlayHasActivePlaybackHash() =>
    r'007d108b36b600d13f83e6e04f7c47e3123f3a79';

/// Provider for the list of SyncPlay groups (load/refresh from sheet).
///
/// The server has no push notification for "a group was created" - group
/// update frames only reach members of that group. So while the sheet is
/// showing the browse list, we poll for it; autoDispose tears the timer
/// down the moment nothing is watching this anymore (sheet closed, or a
/// group was joined and the active-group view replaced the list).

@ProviderFor(SyncPlayGroups)
final syncPlayGroupsProvider = SyncPlayGroupsProvider._();

/// Provider for the list of SyncPlay groups (load/refresh from sheet).
///
/// The server has no push notification for "a group was created" - group
/// update frames only reach members of that group. So while the sheet is
/// showing the browse list, we poll for it; autoDispose tears the timer
/// down the moment nothing is watching this anymore (sheet closed, or a
/// group was joined and the active-group view replaced the list).
final class SyncPlayGroupsProvider
    extends $NotifierProvider<SyncPlayGroups, SyncPlayGroupsState> {
  /// Provider for the list of SyncPlay groups (load/refresh from sheet).
  ///
  /// The server has no push notification for "a group was created" - group
  /// update frames only reach members of that group. So while the sheet is
  /// showing the browse list, we poll for it; autoDispose tears the timer
  /// down the moment nothing is watching this anymore (sheet closed, or a
  /// group was joined and the active-group view replaced the list).
  SyncPlayGroupsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncPlayGroupsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncPlayGroupsHash();

  @$internal
  @override
  SyncPlayGroups create() => SyncPlayGroups();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncPlayGroupsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncPlayGroupsState>(value),
    );
  }
}

String _$syncPlayGroupsHash() => r'8bd07a0f6855a08e8d910c95b68a3373c4c4e199';

/// Provider for the list of SyncPlay groups (load/refresh from sheet).
///
/// The server has no push notification for "a group was created" - group
/// update frames only reach members of that group. So while the sheet is
/// showing the browse list, we poll for it; autoDispose tears the timer
/// down the moment nothing is watching this anymore (sheet closed, or a
/// group was joined and the active-group view replaced the list).

abstract class _$SyncPlayGroups extends $Notifier<SyncPlayGroupsState> {
  SyncPlayGroupsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SyncPlayGroupsState, SyncPlayGroupsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncPlayGroupsState, SyncPlayGroupsState>,
              SyncPlayGroupsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

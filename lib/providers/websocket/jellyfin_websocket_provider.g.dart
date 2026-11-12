// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'jellyfin_websocket_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-level shared Jellyfin WebSocket.
///
/// Owns a single [JellyfinWebSocket], connects when a user is
/// authenticated, and re-broadcasts the socket's streams through
/// long-lived controllers so consumers stay subscribed transparently
/// across account switches / socket rebuilds.

@ProviderFor(JellyfinWebSocketController)
final jellyfinWebSocketControllerProvider =
    JellyfinWebSocketControllerProvider._();

/// App-level shared Jellyfin WebSocket.
///
/// Owns a single [JellyfinWebSocket], connects when a user is
/// authenticated, and re-broadcasts the socket's streams through
/// long-lived controllers so consumers stay subscribed transparently
/// across account switches / socket rebuilds.
final class JellyfinWebSocketControllerProvider
    extends
        $NotifierProvider<
          JellyfinWebSocketController,
          WebSocketConnectionState
        > {
  /// App-level shared Jellyfin WebSocket.
  ///
  /// Owns a single [JellyfinWebSocket], connects when a user is
  /// authenticated, and re-broadcasts the socket's streams through
  /// long-lived controllers so consumers stay subscribed transparently
  /// across account switches / socket rebuilds.
  JellyfinWebSocketControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'jellyfinWebSocketControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$jellyfinWebSocketControllerHash();

  @$internal
  @override
  JellyfinWebSocketController create() => JellyfinWebSocketController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WebSocketConnectionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WebSocketConnectionState>(value),
    );
  }
}

String _$jellyfinWebSocketControllerHash() =>
    r'6e0b4bcef9e0b4441ad20624746fbe9d9591f649';

/// App-level shared Jellyfin WebSocket.
///
/// Owns a single [JellyfinWebSocket], connects when a user is
/// authenticated, and re-broadcasts the socket's streams through
/// long-lived controllers so consumers stay subscribed transparently
/// across account switches / socket rebuilds.

abstract class _$JellyfinWebSocketController
    extends $Notifier<WebSocketConnectionState> {
  WebSocketConnectionState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref =
        this.ref as $Ref<WebSocketConnectionState, WebSocketConnectionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<WebSocketConnectionState, WebSocketConnectionState>,
              WebSocketConnectionState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

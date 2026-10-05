import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:chudder/jellyfin/enum_models.dart';
import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart' as enums;
import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/api_result.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/library_filters_model.dart';
import 'package:chudder/models/bazarr_credentials_model.dart';
import 'package:chudder/models/seerr_credentials_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/connectivity_provider.dart';
import 'package:chudder/providers/image_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/providers/video_player_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/localization_helper.dart';

part 'user_provider.g.dart';

@riverpod
bool showSyncButtonProvider(Ref ref) {
  final userCanSync = ref.watch(userProvider.select((value) => value?.canDownload ?? false));
  final hasSyncedItems = ref.watch(syncProvider.select((value) => value.items.isNotEmpty));
  return userCanSync || hasSyncedItems;
}

@Riverpod(keepAlive: true)
class User extends _$User {
  late final JellyService api = ref.read(jellyApiProvider);

  set userState(AccountModel? account) {
    state = account?.copyWith(lastUsed: DateTime.now());
    if (account != null) {
      ref.read(sharedUtilityProvider).updateAccountInfo(account);
    }
  }

  Future<Response<bool>> quickConnect(String pin) async => api.quickConnect(pin);

  /// The latest refresh of the server's side of the account, while it runs.
  Future<Object?>? _informationPending;

  /// Done once the latest refresh of the account has landed; never fails.
  ///
  /// The library list goes out alongside that refresh rather than behind it,
  /// and waits here only before it is written: the order of the libraries and
  /// which of them are left out of Latest come with the user's configuration,
  /// which is not stored between launches.
  Future<void> get informationSettled async {
    final pending = _informationPending;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {}
  }

  Future<Response<AccountModel>?> updateInformation() {
    final request = _updateInformation();
    _informationPending = request;
    request.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_informationPending, request)) _informationPending = null;
    });
    return request;
  }

  Future<Response<AccountModel>?> _updateInformation() async {
    if (state == null) return null;
    try {
      // Four round trips that share nothing, so they share the wait. This is
      // the first thing the dashboard does on every launch and every refresh;
      // serially it cost the whole screen three requests' worth of waiting for
      // information that is not even shown on it.
      final results = await Future.wait<Object?>([
        api.usersMeGet(),
        api.quickConnectEnabled(),
        api.systemConfigurationGet(),
        api.getCustomConfig(),
      ]);
      final response = results[0] as Response<UserDto>;
      final quickConnectStatus = results[1] as Response<bool>;
      final systemConfiguration = results[2] as Response<ServerConfiguration>;
      final customConfig = results[3] as Response<UserSettings>;

      var imageUrl = ref.read(imageUtilityProvider).getUserImageUrl(response.body?.id ?? "");

      final user = response.body;
      if (user == null) return null;

      if (response.isSuccessful && response.body != null) {
        userState = state?.copyWith(
          name: user.name ?? state?.name ?? "",
          policy: user.policy,
          lastKnownCanDownload: user.policy?.enableContentDownloading ?? false,
          avatar: imageUrl,
          serverConfiguration: systemConfiguration.body,
          userConfiguration: user.configuration,
          quickConnectState: quickConnectStatus.body ?? false,
          latestItemsExcludes: user.configuration?.latestItemsExcludes ?? [],
          userSettings: customConfig.body,
          hasConfiguredPassword: user.hasConfiguredPassword ?? false,
          hasPassword: user.hasPassword ?? false,
        );
        return response.copyWith(body: state);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  void setRememberAudioSelections() async {
    final newUserConfiguration = await api.updateRememberAudioSelections();
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void setRememberSubtitleSelections() async {
    final newUserConfiguration = await api.updateRememberSubtitleSelections();
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void updateSubtitleLanguagePreference(String? language) async {
    final currentUserConfiguration = state?.userConfiguration;
    if (currentUserConfiguration == null) return;

    final normalizedLanguage = language?.trim().toLowerCase();
    final updated = currentUserConfiguration.copyWithWrapped(
      subtitleLanguagePreference:
          Wrapped<String?>.value((normalizedLanguage?.isEmpty ?? true) ? null : normalizedLanguage),
    );
    final newUserConfiguration = await api.updateUserConfiguration(updated);
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  /// Picks the Chromecast receiver app, saved in the Jellyfin account like
  /// jellyfin-web's "Google Cast version", so both clients agree. Returns
  /// whether the server took it.
  Future<bool> setCastReceiver(String receiverId) async {
    final currentUserConfiguration = state?.userConfiguration;
    if (currentUserConfiguration == null) return false;
    final updated = currentUserConfiguration.copyWith(castReceiverId: receiverId);
    final newUserConfiguration = await api.updateUserConfiguration(updated);
    if (newUserConfiguration == null) return false;
    userState = state?.copyWith(userConfiguration: newUserConfiguration);
    return true;
  }

  void updateSubtitleMode(enums.SubtitlePlaybackMode? mode) async {
    final currentUserConfiguration = state?.userConfiguration;
    if (currentUserConfiguration == null) return;

    final updated = currentUserConfiguration.copyWith(subtitleMode: mode);
    final newUserConfiguration = await api.updateUserConfiguration(updated);
    if (newUserConfiguration != null) {
      userState = state?.copyWith(userConfiguration: newUserConfiguration);
    }
  }

  void setBackwardSpeed(int value) {
    final userSettings = state?.userSettings?.copyWith(skipBackDuration: Duration(seconds: value));
    if (userSettings != null) {
      updateCustomConfig(userSettings);
    }
  }

  void setForwardSpeed(int value) {
    final userSettings = state?.userSettings?.copyWith(skipForwardDuration: Duration(seconds: value));
    if (userSettings != null) {
      updateCustomConfig(userSettings);
    }
  }

  Future<Response<dynamic>> updateCustomConfig(UserSettings settings) async {
    state = state?.copyWith(userSettings: settings);
    return api.setCustomConfig(settings);
  }

  Future<ApiResult> refreshMetaData(
    String itemId, {
    MetadataRefresh? metadataRefreshMode,
    bool? replaceAllMetadata,
    bool? replaceTrickplayImages,
  }) async {
    return api
        .itemsItemIdRefreshPost(
          itemId: itemId,
          metadataRefreshMode: switch (metadataRefreshMode) {
            MetadataRefresh.defaultRefresh => MetadataRefresh.defaultRefresh,
            _ => MetadataRefresh.fullRefresh,
          },
          imageRefreshMode: switch (metadataRefreshMode) {
            MetadataRefresh.defaultRefresh => MetadataRefresh.defaultRefresh,
            _ => MetadataRefresh.fullRefresh,
          },
          replaceAllMetadata: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => true,
            _ => false,
          },
          replaceAllImages: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => replaceAllMetadata,
            MetadataRefresh.validation => replaceAllMetadata,
            _ => false,
          },
          replaceTrickplayImages: switch (metadataRefreshMode) {
            MetadataRefresh.fullRefresh => replaceTrickplayImages,
            MetadataRefresh.validation => replaceTrickplayImages,
            _ => false,
          },
        )
        .apiResult;
  }

  Future<Response<UserData>?> setAsFavorite(bool favorite, String itemId) {
    return _changeUserData(
      itemId,
      online: () async {
        final response = await (favorite
            ? api.usersUserIdFavoriteItemsItemIdPost(itemId: itemId)
            : api.usersUserIdFavoriteItemsItemIdDelete(itemId: itemId));
        return Response(response.base, UserData.fromDto(response.body));
      },
      queue: () => ref.read(syncProvider.notifier).updateFavoriteItem(itemId, isFavorite: favorite),
      locally: (data) => data.copyWith(isFavourite: favorite),
    );
  }

  Future<Response<UserData>?> markAsPlayed(bool enable, String itemId) {
    final datePlayed = DateTime.now();
    return _changeUserData(
      itemId,
      online: () async {
        final response = await (enable
            ? api.usersUserIdPlayedItemsItemIdPost(
                itemId: itemId,
                datePlayed: datePlayed,
              )
            : api.usersUserIdPlayedItemsItemIdDelete(
                itemId: itemId,
              ));
        return Response(response.base, UserData.fromDto(response.body));
      },
      queue: () => ref.read(syncProvider.notifier).updatePlayedItem(itemId, datePlayed: datePlayed, played: enable),
      // What the sync store writes for the same change, so the page shows
      // what the downloads will.
      locally: (data) => data.copyWith(
        played: enable,
        playbackPositionTicks: 0,
        progress: 0.0,
        lastPlayed: datePlayed.toUtc(),
      ),
    );
  }

  String? _lastNotice;
  DateTime _lastNoticeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Once, for a whole selection marked at the same time, rather than a
  /// message for every item in it.
  void _notice(String? message) {
    if (message == null) return;
    final now = DateTime.now();
    if (message == _lastNotice && now.difference(_lastNoticeAt) < const Duration(seconds: 4)) return;
    _lastNotice = message;
    _lastNoticeAt = now;
    FladderSnack.show(message);
  }

  /// A change to the user's own data on an item, which works without the
  /// server where it can.
  ///
  /// A downloaded item keeps its own copy of that data, and a change the
  /// server has not heard about yet is marked on it and sent once the app is
  /// back online (see `updateSyncStates`). So offline, or when the request
  /// cannot reach the server, a downloaded item takes the change there and
  /// the page shows it as done. Anything else genuinely needs the server:
  /// the user is told so, calmly, and the call returns null - where it used
  /// to throw a connection error into the page after the request's retries.
  Future<Response<UserData>?> _changeUserData(
    String itemId, {
    required Future<Response<UserData>?> Function() online,
    required Future<void> Function() queue,
    required UserData Function(UserData data) locally,
  }) async {
    Future<Response<UserData>?> withoutServer() async {
      final synced = await ref.read(syncProvider.notifier).getSyncedItem(itemId);
      final data = synced?.userData;
      final localized = ref.read(localizationContextProvider)?.localized;
      if (data == null) {
        _notice(localized?.needsConnection);
        return null;
      }
      await queue();
      _notice(localized?.savedUntilOnline);
      return Response(http.Response('', 200), locally(data));
    }

    if (ref.read(offlineStateProvider)) return withoutServer();
    try {
      return await online();
    } on IOException {
      // The request has already marked a downloaded item's change as waiting
      // for the server (see the service), so this only answers the page.
      return withoutServer();
    } on TimeoutException {
      return withoutServer();
    }
  }

  void clear() => userState = null;
  void updateUser(AccountModel? user) => userState = user;
  void loginUser(AccountModel? user) => state = user;
  void setAuthMethod(Authentication method) => userState = state?.copyWith(authMethod: method);
  void setLocalURL(String? value) {
    final user = state;
    if (user == null) return;
    state = user.copyWith(
      credentials: user.credentials.copyWith(localUrl: value?.isEmpty == true ? null : value),
    );
    userState = state;
  }

  void setSeerrServerUrl(String? value) {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      serverUrl: value?.trim() ?? "",
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  void logoutSeerr() {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      apiKey: "",
      sessionCookie: "",
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  void setSeerrApiKey(String? value) {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      apiKey: value?.trim() ?? "",
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  /// Stores the Bazarr connection, or clears it with null.
  void setBazarrCredentials(BazarrCredentialsModel? value) {
    final user = state;
    if (user == null) return;
    userState = user.copyWith(bazarrCredentials: value);
  }

  void setSeerrSessionCookie(String? value) {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      sessionCookie: value?.trim() ?? "",
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  void setSeerrCustomHeaders(Map<String, String> headers) {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      customHeaders: headers,
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  void clearSeerrCustomHeaders() {
    final user = state;
    if (user == null) return;
    final updated = (user.seerrCredentials ?? const SeerrCredentialsModel()).copyWith(
      customHeaders: {},
    );
    userState = user.copyWith(seerrCredentials: updated);
  }

  void addSearchQuery(String value) {
    if (value.isEmpty) return;
    final newList = state?.searchQueryHistory.toList() ?? [];
    if (newList.contains(value)) {
      newList.remove(value);
    }
    newList.add(value);
    userState = state?.copyWith(searchQueryHistory: newList);
  }

  void removeSearchQuery(String value) {
    userState = state?.copyWith(
      searchQueryHistory: state?.searchQueryHistory ?? []
        ..remove(value)
        ..take(50),
    );
  }

  void clearSearchQuery() {
    userState = state?.copyWith(searchQueryHistory: []);
  }

  Future<void> logoutUser() async {
    await ref.read(videoPlayerProvider).stop();
    // The stop report is sent in the background; here it has to arrive
    // before the session it reports to is closed.
    await ref.read(videoPlayerProvider).flushReports();
    if (state == null) return;
    userState = null;
  }

  Future<void> forceLogoutUser(AccountModel account) async {
    userState = account;
    await api.sessionsLogoutPost();
    userState = null;
  }

  @override
  AccountModel? build() {
    return null;
  }

  void removeFilter(LibraryFiltersModel model) {
    final currentList = (state?.libraryFilters ?? []).toList(growable: true);
    currentList.remove(model);
    userState = state?.copyWith(libraryFilters: currentList);
  }

  void saveFilter(LibraryFiltersModel model) {
    final currentList = (state?.libraryFilters ?? []).toList(growable: true);
    final index = currentList.indexWhere((value) => value.id == model.id);
    if (index != -1) {
      currentList[index] = model;
    } else {
      currentList.add(model);
    }
    userState = state?.copyWith(libraryFilters: currentList);
  }

  void hideFilterFromSideBar(LibraryFiltersModel model) {
    final currentList = (state?.libraryFilters ?? []).toList(growable: true);
    final index = currentList.indexWhere((value) => value.id == model.id);
    if (index != -1) {
      final updatedModel = model.copyWith(showInSideBar: false);
      currentList[index] = updatedModel;
      userState = state?.copyWith(libraryFilters: currentList);
    }
  }

  void deleteAllFilters() => userState = state?.copyWith(libraryFilters: []);

  String? createDownloadUrl(ItemBaseModel item) {
    // Both auth parameter names, for the reason documented on
    // [authQueryParameters] — spelled out here because this URL is
    // assembled as a string rather than through the Uri builders.
    final token = state?.credentials.token;
    return Uri.encodeFull(
      "${state?.credentials.url}/Items/${item.id}/Download?api_key=$token&ApiKey=$token",
    );
  }

  Future<void> createNewUser(
    String userName,
    String password, {
    required bool enableAllFolders,
    required List<String> enabledFolders,
  }) async {
    final newUser = (await api.createNewUser(
      CreateUserByName(name: userName, password: password),
    ))
        .body;
    if (newUser == null) return;
    await api.setUserPolicy(
      id: newUser.id ?? "",
      policy: newUser.policy?.copyWith(
        enableAllFolders: enableAllFolders,
        enabledFolders: enabledFolders,
      ),
    );
  }

  void toggleIncognitoMode() {
    final currentMode = state?.incognitoMode;
    userState = state?.copyWith(incognitoMode: currentMode == true ? null : true);
  }
}

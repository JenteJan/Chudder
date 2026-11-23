import 'package:flutter/material.dart';

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/api_result.dart';
import 'package:chudder/models/credentials_model.dart';
import 'package:chudder/models/login_screen_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/dashboard_provider.dart';
import 'package:chudder/providers/favourites_provider.dart';
import 'package:chudder/providers/image_provider.dart';
import 'package:chudder/providers/library_screen_provider.dart';
import 'package:chudder/providers/music_dashboard_provider.dart';
import 'package:chudder/providers/seerr_api_provider.dart';
import 'package:chudder/providers/seerr_dashboard_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/providers/views_provider.dart';
import 'package:chudder/screens/login/lock_screen.dart';
import 'package:chudder/util/fladder_config.dart';
import 'package:chudder/util/list_extensions.dart';
import 'package:chudder/util/localization_helper.dart';

final authProvider = StateNotifierProvider<AuthNotifier, LoginScreenModel>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<LoginScreenModel> {
  AuthNotifier(this.ref) : super(LoginScreenModel());

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  BuildContext? get localContext => ref.read(localizationContextProvider);

  Future<void> initModel() async {
    ref.read(userProvider.notifier).clear();
    final currentAccounts = getSavedAccounts();
    ref.read(lockScreenActiveProvider.notifier).update((state) => true);
    if (FladderConfig.baseUrl != null) {
      final url = FladderConfig.baseUrl;
      state = state.copyWith(
        hasBaseUrl: true,
      );
      if (url != null) {
        await setServer(url);
      }
    }
    state = state.copyWith(
      accounts: currentAccounts,
      screen: currentAccounts.isEmpty ? LoginScreenType.login : LoginScreenType.users,
    );
  }

  /// Bumped on every connect, so an answer from an address the user has
  /// since replaced is thrown away.
  int _connectAttempt = 0;

  /// Asks [url] who it is before anything else. The sign-in step only shows
  /// once a Jellyfin server has answered; until then the screen stays on the
  /// address, with the reason it failed under it.
  Future<void> _fetchServerInfo(String url, int attempt) async {
    final newCredentials = CredentialsModel.createNewCredentials().copyWith(url: url);
    final newLoginModel = ServerLoginModel(tempCredentials: newCredentials);
    // The requests below go to the address in the login model.
    state = state.copyWith(serverLoginModel: newLoginModel);
    try {
      final serverResponse = await api.systemInfoPublicGet();
      if (attempt != _connectAttempt) return;
      final info = serverResponse.body;
      if (!serverResponse.isSuccessful || info == null || (info.id ?? "").isEmpty) {
        _connectFailed(url);
        return;
      }
      final serverId = info.id ?? "";

      // Extras: a server that keeps its user list or branding private is
      // still a server to sign in to.
      final results = await Future.wait<Object?>([
        getPublicUsers().then((value) => value?.body).catchError((_) => null),
        api.quickConnectEnabled().then((value) => value.body).catchError((_) => null),
        api.getBranding().then((value) => value.body?.loginDisclaimer).catchError((_) => null),
      ]);
      if (attempt != _connectAttempt) return;
      final publicUsers = (results[0] as List<AccountModel>?) ?? [];
      final quickConnectStatus = (results[1] as bool?) ?? false;
      final loginDisclaimer = results[2] as String?;

      state = state.copyWith(
        errorMessage: null,
        connecting: false,
        screen: quickConnectStatus ? LoginScreenType.code : LoginScreenType.login,
        serverLoginModel: newLoginModel.copyWith(
          tempCredentials: newCredentials.copyWith(
            serverName: info.serverName ?? "",
            serverId: serverId,
          ),
          accounts: publicUsers,
          hasQuickConnect: quickConnectStatus,
          serverMessage: loginDisclaimer,
        ),
        loading: false,
      );

      final seerrUrl = _findSeerrUrlForServer(serverId);
      setTempSeerrUrl(seerrUrl);
    } catch (e) {
      if (attempt != _connectAttempt) return;
      _connectFailed(url);
    }
  }

  void _connectFailed(String url) {
    state = state.copyWith(
      serverLoginModel: null,
      errorMessage: localContext?.localized.loginServerUnreachable(url) ?? url,
      connecting: false,
      loading: false,
    );
  }

  Future<Response<List<AccountModel>>?> getPublicUsers() async {
    try {
      state = state.copyWith(loading: true);
      final credentials = state.serverLoginModel?.tempCredentials;
      if (credentials == null) return null;
      var response = await api.usersPublicGet(credentials);
      if (response.isSuccessful && response.body != null) {
        var models = response.body ?? [];
        return response.copyWith(body: models.toList());
      }
      state = state.copyWith(
        serverLoginModel: state.serverLoginModel?.copyWith(
          accounts: response.body ?? [],
        ),
      );
      return response.copyWith(body: []);
    } catch (e) {
      return null;
    } finally {
      state = state.copyWith(loading: false);
    }
  }

  Future<ApiResult<AccountModel>> authenticateUsingSecret(String secret) async {
    clearAllProviders();
    var response = await api.quickConnectAuthenticate(secret);
    return _createAccountModel(response).apiResult;
  }

  Future<Response<AccountModel>?> authenticateByName(String userName, String password) async {
    clearAllProviders();
    var response = await api.usersAuthenticateByNamePost(userName: userName, password: password);
    return _createAccountModel(response);
  }

  Future<Response<AccountModel>> _createAccountModel(Response<AuthenticationResult> response) async {
    CredentialsModel? credentials = state.serverLoginModel?.tempCredentials;
    if (credentials == null) return Response(response.base, null);
    if (response.isSuccessful && (response.body?.accessToken?.isNotEmpty ?? false)) {
      var serverResponse = await api.systemInfoPublicGet();
      credentials = credentials.copyWith(
        token: response.body?.accessToken ?? "",
        serverId: response.body?.serverId ?? "",
        serverName: serverResponse.body?.serverName ?? "",
      );
      var imageUrl = ref.read(imageUtilityProvider).getUserImageUrl(response.body?.user?.id ?? "");
      AccountModel newUser = AccountModel(
        name: response.body?.user?.name ?? "",
        id: response.body?.user?.id ?? "",
        avatar: imageUrl,
        credentials: credentials,
        lastUsed: DateTime.now(),
      );
      ref.read(sharedUtilityProvider).addAccount(newUser);
      ref.read(userProvider.notifier).userState = newUser;
      final currentAccounts = getSavedAccounts();

      state = state.copyWith(
        accounts: currentAccounts,
      );

      return Response(response.base, newUser);
    }
    return Response(response.base, null);
  }

  Future<Response?> logOutUser() async {
    final currentUser = ref.read(userProvider);
    state = state.copyWith(serverLoginModel: null);
    await ref.read(sharedUtilityProvider).removeAccount(currentUser);

    try {
      await ref.read(seerrApiProvider).logout();
    } catch (e) {
      // Ignore logout errors for seerr
    }
    clearAllProviders();
    return null;
  }

  Future<void> switchUser() async => clearAllProviders();

  void clearAllProviders() {
    ref.read(dashboardProvider.notifier).clear();
    ref.read(viewsProvider.notifier).clear();
    ref.read(favouritesProvider.notifier).clear();
    ref.read(userProvider.notifier).clear();
    ref.read(libraryScreenProvider.notifier).clear();
    ref.read(seerrDashboardProvider.notifier).clear();
    ref.read(musicDashboardProvider.notifier).clear();
  }

  Future<void> setServer(String server) async {
    final attempt = ++_connectAttempt;
    final target = state.hasBaseUrl ? FladderConfig.baseUrl! : server.trim();
    if (target.isEmpty) return;
    state = state.copyWith(connecting: true, errorMessage: null);
    if (state.hasBaseUrl) {
      await _fetchServerInfo(target, attempt);
      return;
    }
    final result = await probeAndNormalizeUrl(target, probeJellyfinUrl);
    if (attempt != _connectAttempt) return;
    await _fetchServerInfo(result.url, attempt);
  }

  /// Back to the address step, to connect somewhere else.
  void changeServer() {
    _connectAttempt++;
    state = state.copyWith(
      serverLoginModel: null,
      connecting: false,
      errorMessage: null,
      screen: LoginScreenType.login,
    );
  }

  List<AccountModel> getSavedAccounts() {
    state = state.copyWith(accounts: ref.read(sharedUtilityProvider).getAccounts());
    return state.accounts;
  }

  void reOrderUsers(int oldIndex, int newIndex) {
    final accounts = state.accounts.toList();
    accounts.reorderInPlace(oldIndex, newIndex);
    state = state.copyWith(accounts: accounts);
    ref.read(sharedUtilityProvider).saveAccounts(accounts);
  }

  void addNewUser() {
    state = state.copyWith(
      screen: LoginScreenType.login,
    );
  }

  void goUserSelect() {
    if (!state.hasBaseUrl) _connectAttempt++;
    state = state.copyWith(
      connecting: false,
      errorMessage: null,
      serverLoginModel: state.hasBaseUrl ? state.serverLoginModel : null,
      screen: LoginScreenType.users,
    );
  }

  String? _findSeerrUrlForServer(String? serverId) {
    if (FladderConfig.seerrBaseUrl?.isNotEmpty == true) {
      return FladderConfig.seerrBaseUrl;
    }
    if (serverId == null || serverId.isEmpty) return null;
    final matches = state.accounts.where(
      (account) =>
          account.credentials.serverId == serverId && (account.seerrCredentials?.serverUrl.isNotEmpty ?? false),
    );

    if (matches.isEmpty) return null;

    final sorted = matches.toList()..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));

    return sorted.first.seerrCredentials?.serverUrl;
  }

  void setTempSeerrUrl(String? url) {
    state = state.copyWith(tempSeerrUrl: url?.trim().isEmpty == true ? null : url?.trim());
  }

  void setTempSeerrSessionCookie(String? cookie) {
    state = state.copyWith(tempSeerrSessionCookie: cookie?.trim().isEmpty == true ? null : cookie?.trim());
  }
}

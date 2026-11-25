import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chudder/models/account_model.dart';
import 'package:chudder/models/last_seen_notifications_model.dart';
import 'package:chudder/models/settings/client_settings_model.dart';
import 'package:chudder/models/settings/home_settings_model.dart';
import 'package:chudder/models/settings/subtitle_settings_model.dart';
import 'package:chudder/models/settings/video_player_settings.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/providers/settings/book_viewer_settings_provider.dart';
import 'package:chudder/providers/settings/client_settings_provider.dart';
import 'package:chudder/providers/settings/home_settings_provider.dart';
import 'package:chudder/providers/settings/photo_view_settings_provider.dart';
import 'package:chudder/providers/settings/pigeon_player_settings_provider.dart';
import 'package:chudder/providers/settings/subtitle_settings_provider.dart';
import 'package:chudder/providers/settings/syncplay_settings_provider.dart';
import 'package:chudder/providers/settings/video_player_settings_provider.dart';
import 'package:chudder/providers/update_notifications_provider.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final sharedUtilityProvider = Provider<SharedUtility>((ref) {
  final sharedPrefs = ref.watch(sharedPreferencesProvider);

  ref.read(pigeonPlayerSettingsSyncProvider);

  return SharedUtility(ref: ref, sharedPreferences: sharedPrefs)..init();
});

SharedHelper get sharedHelper => SharedHelper(sharedPreferences: SharedPreferences.getInstance() as SharedPreferences);

class SharedUtility extends SharedHelper {
  SharedUtility({
    required Ref ref,
    required super.sharedPreferences,
  }) : _ref = ref;

  final Ref _ref;

  late final JellyService api = _ref.read(jellyApiProvider);

  void init() {
    unawaited(retryPendingRevocations());
    SharedKeys.instance.onKeyChanged.listen((key) async {
      await Future.delayed(const Duration(milliseconds: 500));
      switch (key) {
        case SharedKeys.lastSeenNotificationsKey:
          _ref.read(notificationsProvider.notifier).state = lastSeenNotifications;
          break;
      }
    });
  }

  Future<bool?> loadSettings() async {
    try {
      _ref.read(clientSettingsProvider.notifier).initialize(clientSettings);
      _ref.read(homeSettingsProvider.notifier).state = homeSettings;
      _ref.read(videoPlayerSettingsProvider.notifier).state = videoPlayerSettings;
      _ref.read(subtitleSettingsProvider.notifier).state = subtitleSettings;
      _ref.read(syncPlaySettingsProvider.notifier).state = syncPlaySettings;
      _ref.read(bookViewerSettingsProvider.notifier).state = bookViewSettings;
      _ref.read(photoViewSettingsProvider.notifier).state = photoViewSettings;
      _ref.read(notificationsProvider.notifier).state = lastSeenNotifications;
      return true;
    } catch (e) {
      return false;
    }
  }
}

class SharedKeys {
  SharedKeys._();

  //Singleton
  static final SharedKeys instance = SharedKeys._();

  static const String _loginCredentialsKey = 'loginCredentialsKey';
  static const String _pendingRevocationsKey = 'pendingTokenRevocations';
  static const String _clientSettingsKey = 'clientSettings';
  static const String _homeSettingsKey = 'homeSettings';
  static const String _videoPlayerSettingsKey = 'videoPlayerSettings';
  static const String _subtitleSettingsKey = 'subtitleSettings';
  static const String _syncPlaySettingsKey = 'syncPlaySettings';
  static const String _bookViewSettingsKey = 'bookViewSettings';
  static const String _photoViewSettingsKey = 'photoViewSettings';
  static const String lastSeenNotificationsKey = 'lastSeenNotifications';

  final _keyChanged = StreamController<String>.broadcast();

  Stream<String> get onKeyChanged => _keyChanged.stream;
}

class SharedHelper {
  final Ref? ref;
  final SharedPreferences sharedPreferences;

  const SharedHelper({this.ref, required this.sharedPreferences});

  Future<bool?> addAccount(AccountModel account) async {
    final newAccount = account.copyWith(
      lastUsed: DateTime.now(),
    );

    List<AccountModel> accounts = getAccounts().toList();
    if (accounts.any((element) => element.sameIdentity(newAccount))) {
      accounts = accounts
          .map(
            (e) => e.sameIdentity(newAccount)
                ? e.copyWith(
                    credentials: newAccount.credentials,
                    lastUsed: newAccount.lastUsed,
                  )
                : e,
          )
          .toList();
    } else {
      accounts = [
        ...accounts,
        newAccount,
      ];
    }

    return await saveAccounts(accounts);
  }

  Future<bool?> removeAccount(AccountModel? account) async {
    if (account == null) return null;

    // End the session on the server, so the token stops working everywhere
    // it might have been copied to. Offline, it is queued and retried on the
    // next start instead of staying valid forever.
    final credentials = account.credentials;
    if (credentials.token.isNotEmpty && credentials.url.isNotEmpty) {
      final pending = (
        url: normalizeUrl(credentials.url),
        authorization: ref != null
            ? credentials.header(ref!)['authorization']!
            : 'MediaBrowser Token="${credentials.token}", DeviceId="${credentials.deviceId}"',
      );
      if (!await _revokeToken(pending)) {
        log('Could not end the session on the server; retrying on next start');
        await _savePendingRevocations([..._pendingRevocations(), pending]);
      }
    }

    //Remove from local database
    final savedAccounts = getAccounts();
    savedAccounts.removeWhere((element) {
      return element.sameIdentity(account);
    });
    return (await saveAccounts(savedAccounts));
  }

  /// Signed-out accounts whose session the server has not confirmed ended.
  List<({String url, String authorization})> _pendingRevocations() {
    try {
      final saved = sharedPreferences.getStringList(SharedKeys._pendingRevocationsKey) ?? [];
      return saved.map((entry) {
        final map = jsonDecode(entry) as Map<String, dynamic>;
        return (url: map['url'] as String, authorization: map['authorization'] as String);
      }).toList();
    } catch (e) {
      log('Unreadable pending revocations: $e');
      return [];
    }
  }

  Future<void> _savePendingRevocations(List<({String url, String authorization})> pending) async {
    if (pending.isEmpty) {
      await sharedPreferences.remove(SharedKeys._pendingRevocationsKey);
      return;
    }
    await sharedPreferences.setStringList(
      SharedKeys._pendingRevocationsKey,
      pending.map((entry) => jsonEncode({'url': entry.url, 'authorization': entry.authorization})).toList(),
    );
  }

  /// Whether the server is done with the session: it ended it (204), or no
  /// longer knows the token (401/403/404). Unreachable or a server error is
  /// "not yet".
  Future<bool> _revokeToken(({String url, String authorization}) entry) async {
    try {
      final response = await http
          .post(Uri.parse('${entry.url}/Sessions/Logout'), headers: {'authorization': entry.authorization})
          .timeout(const Duration(seconds: 10));
      return response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }

  /// Tries the queued sign-outs again; called once per start.
  Future<void> retryPendingRevocations() async {
    final pending = _pendingRevocations();
    if (pending.isEmpty) return;
    final remaining = <({String url, String authorization})>[];
    for (final entry in pending) {
      if (!await _revokeToken(entry)) remaining.add(entry);
    }
    await _savePendingRevocations(remaining);
  }

  List<AccountModel> getAccounts() {
    final savedAccounts = sharedPreferences.getStringList(SharedKeys._loginCredentialsKey);
    try {
      return savedAccounts != null ? savedAccounts.map((e) => AccountModel.fromJson(jsonDecode(e))).toList() : [];
    } catch (_, stacktrace) {
      log(stacktrace.toString());
      return [];
    }
  }

  AccountModel? getActiveAccount() {
    try {
      final accounts = getAccounts();
      AccountModel recentUsedAccount = accounts.reduce((lastLoggedIn, element) {
        return (element.lastUsed.compareTo(lastLoggedIn.lastUsed)) > 0 ? element : lastLoggedIn;
      });

      if (recentUsedAccount.authMethod == Authentication.autoLogin) return recentUsedAccount;
      return null;
    } catch (e) {
      log(e.toString());
      return null;
    }
  }

  Future<bool?> saveAccounts(List<AccountModel> accounts) async =>
      sharedPreferences.setStringList(SharedKeys._loginCredentialsKey, accounts.map((e) => jsonEncode(e)).toList());

  ClientSettingsModel get clientSettings {
    try {
      return ClientSettingsModel.fromJson(jsonDecode(sharedPreferences.getString(SharedKeys._clientSettingsKey) ?? ""));
    } catch (e) {
      log(e.toString());
      return ClientSettingsModel.defaultModel();
    }
  }

  set clientSettings(ClientSettingsModel settings) =>
      sharedPreferences.setString(SharedKeys._clientSettingsKey, jsonEncode(settings.toJson()));

  HomeSettingsModel get homeSettings {
    try {
      return HomeSettingsModel.fromJson(jsonDecode(sharedPreferences.getString(SharedKeys._homeSettingsKey) ?? ""));
    } catch (e) {
      log(e.toString());
      return HomeSettingsModel.defaultModel();
    }
  }

  set homeSettings(HomeSettingsModel settings) =>
      sharedPreferences.setString(SharedKeys._homeSettingsKey, jsonEncode(settings.toJson()));

  BookViewerSettingsModel get bookViewSettings {
    try {
      return BookViewerSettingsModel.fromJson(sharedPreferences.getString(SharedKeys._bookViewSettingsKey) ?? "");
    } catch (e) {
      log(e.toString());
      return BookViewerSettingsModel();
    }
  }

  set bookViewSettings(BookViewerSettingsModel settings) {
    sharedPreferences.setString(SharedKeys._bookViewSettingsKey, settings.toJson());
  }

  Future<void> updateAccountInfo(AccountModel account) async {
    final accounts = getAccounts();
    await Future.microtask(() async {
      await saveAccounts(accounts.map((e) {
        if (e.sameIdentity(account)) {
          return account.copyWith(
            lastUsed: DateTime.now(),
          );
        } else {
          return e;
        }
      }).toList());
    });
  }

  LastSeenNotificationsModel get lastSeenNotifications {
    try {
      return LastSeenNotificationsModel.fromJson(
          jsonDecode(sharedPreferences.getString(SharedKeys.lastSeenNotificationsKey) ?? ""));
    } catch (e) {
      log(e.toString());
      return const LastSeenNotificationsModel();
    }
  }

  Future<void> setLastSeenNotifications(LastSeenNotificationsModel serverLastSeen) async {
    await sharedPreferences.setString(SharedKeys.lastSeenNotificationsKey, jsonEncode(serverLastSeen.toJson()));
    SharedKeys.instance._keyChanged.add(SharedKeys.lastSeenNotificationsKey);
  }

  SubtitleSettingsModel get subtitleSettings {
    try {
      return SubtitleSettingsModel.fromJson(sharedPreferences.getString(SharedKeys._subtitleSettingsKey) ?? "");
    } catch (e) {
      log(e.toString());
      return const SubtitleSettingsModel();
    }
  }

  set subtitleSettings(SubtitleSettingsModel settings) {
    sharedPreferences.setString(SharedKeys._subtitleSettingsKey, settings.toJson());
  }

  SyncPlaySettingsModel get syncPlaySettings {
    try {
      return SyncPlaySettingsModel.fromJson(sharedPreferences.getString(SharedKeys._syncPlaySettingsKey) ?? "");
    } catch (e) {
      log(e.toString());
      return SyncPlaySettingsModel();
    }
  }

  set syncPlaySettings(SyncPlaySettingsModel settings) {
    sharedPreferences.setString(SharedKeys._syncPlaySettingsKey, settings.toJson());
  }

  VideoPlayerSettingsModel get videoPlayerSettings {
    try {
      return VideoPlayerSettingsModel.fromJson(
          jsonDecode(sharedPreferences.getString(SharedKeys._videoPlayerSettingsKey) ?? ""));
    } catch (e) {
      log(e.toString());
      return VideoPlayerSettingsModel();
    }
  }

  set videoPlayerSettings(VideoPlayerSettingsModel settings) {
    sharedPreferences.setString(SharedKeys._videoPlayerSettingsKey, jsonEncode(settings.toJson()));
  }

  PhotoViewSettingsModel get photoViewSettings {
    try {
      return PhotoViewSettingsModel.fromJson(sharedPreferences.getString(SharedKeys._photoViewSettingsKey) ?? "");
    } catch (e) {
      log(e.toString());
      return PhotoViewSettingsModel();
    }
  }

  set photoViewSettings(PhotoViewSettingsModel settings) {
    sharedPreferences.setString(SharedKeys._photoViewSettingsKey, settings.toJson());
  }
}

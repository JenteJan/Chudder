import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/shared_provider.dart';

/// Whether scanning the local network for servers makes the system ask the
/// user for permission first: iOS, macOS and Android ask for local network
/// access, and Windows Defender Firewall asks when the scan opens its socket.
/// Linux asks for nothing, and the web cannot scan.
///
/// Scanning is what asks, so it waits for the user instead of running as soon
/// as the sign-in screen opens. Connecting to a server by its address is not
/// held back: that is the user's own request, and a system that wants to ask
/// about a server on the local network asks then.
bool get serverDiscoveryNeedsPermission =>
    !kIsWeb &&
    const {
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.android,
      TargetPlatform.windows,
    }.contains(defaultTargetPlatform);

/// Whether the user has chosen to scan on this device before. From then on the
/// sign-in screen scans by itself, since the system has been asked and the
/// answer stands.
final serverDiscoveryConsentProvider =
    NotifierProvider<ServerDiscoveryConsent, bool>(ServerDiscoveryConsent.new);

class ServerDiscoveryConsent extends Notifier<bool> {
  static const _key = 'serverDiscoveryChosen';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> choose() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
  }
}

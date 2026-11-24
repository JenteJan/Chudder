import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/providers/shared_provider.dart';
import 'package:chudder/util/local_network_permission.dart';

/// Whether the sign-in screen has to wait for the user before it scans the
/// network for servers, because scanning would make the system ask for
/// something first. `null` while that is still being found out.
///
/// - iOS and macOS ask for local network access, and Windows Defender Firewall
///   asks when the scan opens its socket. They wait until the user has chosen
///   to scan once on this device ([ServerDiscoveryConsent]); after that the
///   system has been asked and its answer stands.
/// - Android asks only from Android 17 on, and can be asked silently whether it
///   has been granted: it waits only while the permission is both required and
///   missing, so older phones and TVs scan at once.
/// - Linux asks for nothing, and the web cannot scan.
///
/// Only the scan waits. Connecting to a server by its address is not held back:
/// that is the user's own request, and the system asks about a server on the
/// local network then.
final serverDiscoveryWaitsProvider = NotifierProvider<ServerDiscoveryWaits, bool?>(ServerDiscoveryWaits.new);

class ServerDiscoveryWaits extends Notifier<bool?> {
  @override
  bool? build() {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        _probe();
        return null;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return !ref.watch(serverDiscoveryConsentProvider);
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _probe() async {
    final granted = await LocalNetworkPermission.isGranted;
    if (ref.mounted) state = !granted;
  }

  /// Asks for what the scan needs, where there is something to ask, and looks
  /// again. Called by the button that starts a scan.
  Future<void> prepare() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await LocalNetworkPermission.ensure();
      await _probe();
      return;
    }
    if (state == true) await ref.read(serverDiscoveryConsentProvider.notifier).choose();
  }
}

/// Whether the user has chosen to scan on this device before.
final serverDiscoveryConsentProvider = NotifierProvider<ServerDiscoveryConsent, bool>(ServerDiscoveryConsent.new);

class ServerDiscoveryConsent extends Notifier<bool> {
  static const _key = 'serverDiscoveryChosen';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> choose() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_key, true);
  }
}

// Routes "latest release" + "has new update" reads to either the upstream
// GitHub provider or the AList variant, based on the build-time
// UPDATE_SOURCE flag. Defined in its own file so upstream's update_provider.dart
// stays untouched.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/update_provider.dart';
import 'package:fladder/providers/update_provider_alist.dart';
import 'package:fladder/util/update_checker.dart';

const kUpdateSource = String.fromEnvironment('UPDATE_SOURCE', defaultValue: 'github');

final latestReleaseRoutedProvider = Provider<ReleaseInfo?>((ref) {
  if (kUpdateSource == 'alist') {
    return ref.watch(updateAlistProvider.select((v) => v.latestRelease));
  }
  return ref.watch(updateProvider.select((v) => v.latestRelease));
});

final hasNewUpdateRoutedProvider = Provider<bool>((ref) {
  final latestVersion = ref.watch(latestReleaseRoutedProvider)?.version;
  final lastViewedVersion = ref.watch(
    clientSettingsProvider.select((v) => v.lastViewedUpdate),
  );
  if (latestVersion == null || lastViewedVersion == null) return false;
  return latestVersion != lastViewedVersion;
});

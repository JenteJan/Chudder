import 'dart:async';

import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/util/alist_release_extras.dart';
import 'package:fladder/util/update_checker.dart';
import 'package:fladder/util/update_checker_alist.dart';

part 'update_provider_alist.freezed.dart';
part 'update_provider_alist.g.dart';

@Riverpod(keepAlive: true)
class UpdateAlist extends _$UpdateAlist {
  final _checker = AlistUpdateChecker();
  Timer? _timer;

  @override
  UpdatesModelAlist build() {
    ref.listen(
      clientSettingsProvider.select((value) => value.checkForUpdates),
      (previous, next) => _toggle(next),
    );

    final enabled = ref.read(
      clientSettingsProvider.select((value) => value.checkForUpdates),
    );

    if (!enabled || !_checker.isConfigured) {
      _timer?.cancel();
      return const UpdatesModelAlist();
    }

    ref.onDispose(() => _timer?.cancel());

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => _fetchLatest());
    _fetchLatest();

    return const UpdatesModelAlist();
  }

  void _toggle(bool enabled) {
    _timer?.cancel();
    if (enabled && _checker.isConfigured) {
      _timer = Timer.periodic(const Duration(minutes: 30), (_) => _fetchLatest());
      _fetchLatest();
    }
  }

  Future<void> _fetchLatest() async {
    final result = await _checker.fetchRecentReleases();
    state = UpdatesModelAlist(
      lastRelease: result.releases,
      extras: result.extras,
    );
  }

  Future<void> refresh() => _fetchLatest();
}

@Freezed(toJson: false, fromJson: false)
abstract class UpdatesModelAlist with _$UpdatesModelAlist {
  const UpdatesModelAlist._();

  const factory UpdatesModelAlist({
    @Default([]) List<ReleaseInfo> lastRelease,
    @Default({}) Map<String, AlistReleaseExtras> extras,
  }) = _UpdatesModelAlist;

  ReleaseInfo? get latestRelease =>
      lastRelease.firstWhereOrNull((value) => value.isNewerThanCurrent);

  AlistReleaseExtras? extrasFor(String version) => extras[version];
}

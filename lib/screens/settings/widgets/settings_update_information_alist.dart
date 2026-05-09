import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown_widget/widget/markdown.dart';

import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/update_downloader_provider.dart';
import 'package:fladder/providers/update_provider_alist.dart';
import 'package:fladder/screens/settings/settings_list_tile.dart';
import 'package:fladder/util/list_padding.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/util/theme_extensions.dart';
import 'package:fladder/util/update_checker.dart';

bool get _isSupportedPlatform {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isWindows;
}

String get _currentPlatformKey {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows_installer';
  return '';
}

String get _filenameForCurrentPlatform {
  if (Platform.isAndroid) return 'Fladder-Android.apk';
  if (Platform.isWindows) return 'Fladder-Windows-Setup.exe';
  return 'Fladder-Update.bin';
}

class SettingsUpdateInformationAlist extends ConsumerStatefulWidget {
  const SettingsUpdateInformationAlist({super.key});

  @override
  ConsumerState<SettingsUpdateInformationAlist> createState() =>
      _SettingsUpdateInformationAlistState();
}

class _SettingsUpdateInformationAlistState
    extends ConsumerState<SettingsUpdateInformationAlist> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final latest = ref.read(updateAlistProvider.select((v) => v.latestRelease));
      if (latest == null) return;
      final lastViewed = ref.read(
          clientSettingsProvider.select((value) => value.lastViewedUpdate));
      if (lastViewed != latest.version) {
        ref.read(clientSettingsProvider.notifier).update(
            (value) => value.copyWith(lastViewedUpdate: latest.version));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupportedPlatform) return const SizedBox.shrink();

    final updates = ref.watch(updateAlistProvider);
    final latest = updates.latestRelease;
    final others = updates.lastRelease;
    final checkForUpdate = ref.watch(
        clientSettingsProvider.select((value) => value.checkForUpdates));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Divider(),
          SettingsListTile(
            label: Text(context.localized.latestReleases),
            subLabel: Text(context.localized.autoCheckForUpdates),
            onTap: () => ref.read(clientSettingsProvider.notifier).update(
                (value) => value.copyWith(checkForUpdates: !checkForUpdate)),
            trailing: Switch(
              value: checkForUpdate,
              onChanged: (value) => ref.read(clientSettingsProvider.notifier).update(
                  (v) => v.copyWith(checkForUpdates: !checkForUpdate)),
            ),
          ),
          if (latest != null)
            _AlistReleaseTile(release: latest, expanded: true),
          ...others
              .where((e) => e != latest)
              .map((r) => _AlistReleaseTile(release: r)),
        ],
      ),
    );
  }
}

class _AlistReleaseTile extends ConsumerWidget {
  final ReleaseInfo release;
  final bool expanded;

  const _AlistReleaseTile({required this.release, this.expanded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platformUrl = release.downloads[_currentPlatformKey];
    final extras = ref.watch(updateAlistProvider).extrasFor(release.version);
    final sha256 = extras?.sha256[_currentPlatformKey];

    return ExpansionTile(
      backgroundColor: release.isNewerThanCurrent
          ? context.colors.primaryContainer
          : context.colors.surfaceContainer,
      collapsedBackgroundColor:
          release.isNewerThanCurrent ? context.colors.primaryContainer : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      collapsedShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(release.version),
      initiallyExpanded: expanded,
      childrenPadding: const EdgeInsets.all(16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: MarkdownWidget(
              data: release.changelog,
              shrinkWrap: true,
            ),
          ),
        ),
        if (platformUrl != null)
          _DownloadButton(
            version: release.version,
            url: platformUrl,
            filename: _filenameForCurrentPlatform,
            expectedSha256: sha256,
          ),
      ].addInBetween(const SizedBox(height: 12)),
    );
  }
}

class _DownloadButton extends ConsumerWidget {
  final String version;
  final String url;
  final String filename;
  final String? expectedSha256;

  const _DownloadButton({
    required this.version,
    required this.url,
    required this.filename,
    required this.expectedSha256,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateDownloaderProvider);
    final notifier = ref.read(updateDownloaderProvider.notifier);

    switch (state.kind) {
      case UpdateDownloadStateKind.idle:
      case UpdateDownloadStateKind.done:
        return FilledButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Download'),
          onPressed: () => notifier.start(
            version: version,
            url: url,
            filename: filename,
            expectedSha256: expectedSha256,
          ),
        );
      case UpdateDownloadStateKind.downloading:
        return Column(
          children: [
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => notifier.cancel(),
              child: Text(context.localized.cancel),
            ),
          ],
        );
      case UpdateDownloadStateKind.verifying:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Verifying…'),
          ],
        );
      case UpdateDownloadStateKind.ready:
        return FilledButton.icon(
          icon: const Icon(Icons.install_mobile),
          label: const Text('Install'),
          onPressed: () => notifier.install(),
        );
      case UpdateDownloadStateKind.installing:
        return const Center(child: CircularProgressIndicator());
      case UpdateDownloadStateKind.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText.rich(
              TextSpan(
                text: 'Update failed: ${state.failure?.name ?? 'unknown'}'
                    '${state.message != null ? ' (${state.message})' : ''}',
                style: TextStyle(color: context.colors.error),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () => notifier.start(
                version: version,
                url: url,
                filename: filename,
                expectedSha256: expectedSha256,
              ),
            ),
          ],
        );
    }
  }
}

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/providers/sync_provider.dart';
import 'package:chudder/screens/home_screen.dart';
import 'package:chudder/util/localization_helper.dart';

/// What a page shows in place of its content when that content lives on the
/// server and the server cannot be reached.
///
/// Calm on purpose. Being offline is a state the app is built to work in, not
/// an error: the page says what is missing, that it comes back by itself, and
/// - when there is something downloaded - where the things that do work are.
/// A spinner that never stops or a raw connection error said none of that.
class OfflineEmptyState extends ConsumerWidget {
  const OfflineEmptyState({
    this.title,
    this.body,
    this.showDownloads = true,
    super.key,
  });

  /// Defaults to saying the page is not available offline.
  final String? title;

  /// Defaults to saying it comes back with the connection.
  final String? body;

  /// Offers the way to the downloads, when there are any. Off on the
  /// downloads' own page, and anywhere the button would lead nowhere new.
  final bool showDownloads;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasDownloads = showDownloads && ref.watch(syncProvider.select((value) => value.items.isNotEmpty));
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, shape: BoxShape.circle),
                child: Icon(IconsaxPlusLinear.cloud_cross, size: 30, color: theme.colorScheme.onSurfaceVariant),
              ),
              Text(
                title ?? context.localized.offlinePageTitle,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              Text(
                body ?? context.localized.offlinePageBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (hasDownloads) ...[
                const SizedBox(height: 4),
                FilledButton.tonalIcon(
                  onPressed: () => showHomeTab(context.router.root, HomeTabs.sync),
                  icon: const Icon(IconsaxPlusLinear.document_download),
                  label: Text(context.localized.offlineOpenDownloads),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/routes/auto_router.gr.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/navigation_scaffold/components/adaptive_fab.dart';

/// The dashboard's floating action button. SyncPlay used to sit beside it;
/// it lives in the app bar now, next to Cast, so it is on every screen.
class DashboardFabs extends ConsumerWidget {
  const DashboardFabs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveFab(
      context: context,
      title: context.localized.search,
      key: const Key('dashboard_search'),
      onPressed: () => context.router.navigate(LibrarySearchRoute()),
      child: const Icon(IconsaxPlusLinear.search_normal_1),
    ).normal;
  }
}

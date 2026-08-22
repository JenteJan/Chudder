import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/seerr/seerr_dashboard_model.dart';
import 'package:fladder/providers/seerr_api_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// What a search turns up that the server does not have.
///
/// The tail of a result list: everything the library holds comes first, and
/// then the things you would have to ask for. Anything Jellyseerr can already
/// see on the server is dropped — that is a row further up, and showing it
/// twice reads as two different films.
///
/// Empty, without asking anyone anything, when Jellyseerr is not set up.
final discoverSearchProvider =
    FutureProvider.autoDispose.family<List<SeerrDashboardPosterModel>, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];
  if (ref.watch(userProvider.select((user) => user?.seerrCredentials?.isConfigured)) != true) return const [];

  try {
    final results = await ref.read(seerrApiProvider).searchPosters(query: trimmed);
    return results.where((poster) => poster.jellyfinItemId == null).toList(growable: false);
  } catch (_) {
    // A search that half works is better than a screen that errors: the
    // library results above this are the answer either way.
    return const [];
  }
});

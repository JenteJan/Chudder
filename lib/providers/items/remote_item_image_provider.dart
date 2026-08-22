import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/providers/api_provider.dart';

/// The first artwork the server's own metadata providers can find for an item
/// that has none in the library.
///
/// This is how a studio gets a picture without the app carrying a TMDB key: the
/// Jellyfin instance already has those providers configured, so it is the one
/// that goes and looks. It needs an admin account and it may find nothing.
///
/// One request per item, so ask only where there is no artwork already — for a
/// list, that means the rare item rather than every row.
final remoteItemImageProvider = FutureProvider.autoDispose.family<String?, String>((ref, itemId) async {
  // A studio's artwork does not change while you are looking at it, and the
  // same one turns up in a search, in a row and on its own page.
  ref.keepAlive();

  final api = ref.read(jellyApiProvider);
  const wanted = [ImageType.logo, ImageType.thumb, ImageType.primary];

  for (final type in wanted) {
    try {
      final response = await api.itemsItemIdRemoteImagesGet(itemId: itemId, type: type);
      final url = response.body?.images?.firstOrNull?.url;
      if (url != null && url.isNotEmpty) return url;
    } catch (_) {
      // No provider, no permission, no image: all the same to the caller.
      return null;
    }
  }
  return null;
});

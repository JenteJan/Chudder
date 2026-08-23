import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/item_shared_models.dart' show UserData;
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/models/items/episode_model.dart';
import 'package:fladder/providers/settings/client_settings_provider.dart';
import 'package:fladder/providers/user_provider.dart';

/// Toggles an item's favorite state, with episode smarts: favoriting an
/// episode asks — once per show — whether the user means the episode or the
/// whole show, and remembers the answer per show. Everything else (other
/// item types, un-favoriting) passes straight through.
///
/// Returns the item's own updated [UserData] when the item itself was
/// toggled, and null otherwise (dialog dismissed, request failed, or the
/// choice was "the show" — in which case the SHOW got favorited, a snackbar
/// says so, and the episode's own state is untouched on purpose).
Future<UserData?> setAsFavoriteWithPrompt(
  BuildContext context,
  WidgetRef ref,
  ItemBaseModel item,
  bool favorite,
) async {
  final seriesId = item is EpisodeModel ? item.parentId : null;
  if (!favorite || item is! EpisodeModel || seriesId == null || seriesId.isEmpty) {
    return (await ref.read(userProvider.notifier).setAsFavorite(favorite, item.id))?.body;
  }

  final remembered = ref.read(clientSettingsProvider).episodeFavoritePrefersShow[seriesId];
  bool? prefersShow = remembered;
  if (prefersShow == null) {
    prefersShow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to favorites'),
        content: Text(
          'Favorite just this episode, or all of "${item.seriesName ?? 'this show'}"?\n\n'
          'Your choice is remembered for this show.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('This episode')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Whole show')),
        ],
      ),
    );
    if (prefersShow == null) return null; // dismissed — do nothing
    final choice = prefersShow;
    ref.read(clientSettingsProvider.notifier).update(
          (state) => state.copyWith(
            episodeFavoritePrefersShow: {...state.episodeFavoritePrefersShow, seriesId: choice},
          ),
        );
  }

  if (prefersShow) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final response = await ref.read(userProvider.notifier).setAsFavorite(true, seriesId);
    if (response?.isSuccessful == true) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Added "${item.seriesName ?? 'show'}" to favorites')),
      );
    }
    return null;
  }
  return (await ref.read(userProvider.notifier).setAsFavorite(true, item.id))?.body;
}

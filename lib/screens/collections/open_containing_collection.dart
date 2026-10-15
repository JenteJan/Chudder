import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/film_collection_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/focus_provider.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/alert_content.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

/// Opens the collection [item] is in; with more than one, asks which.
Future<void> openContainingCollection(BuildContext context, WidgetRef ref, ItemBaseModel item) async {
  final collections = await ref.read(filmCollectionsProvider).containing(item);
  if (!context.mounted) return;
  if (collections.isEmpty) {
    FladderSnack.show(context.localized.notInAnyCollection, context: context);
    return;
  }
  final chosen = collections.length == 1
      ? collections.first
      : await showTvDialog<({String id, String name})>(
          context: context,
          builder: (context) => ContainingCollectionsDialog(collections: collections),
        );
  if (chosen == null || !context.mounted) return;
  openCollection(context, chosen.id);
}

/// The page of the collection [id].
void openCollection(BuildContext context, String id) => context.router.push(DetailsRoute(id: id));

/// Which of the collections an item is in to go to.
class ContainingCollectionsDialog extends StatelessWidget {
  const ContainingCollectionsDialog({required this.collections, super.key});

  final List<({String id, String name})> collections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ActionContent(
          title: Text(context.localized.goToCollection, style: theme.textTheme.titleLarge),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              for (final (index, collection) in collections.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: FocusButton(
                    autoFocus: index == 0,
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => Navigator.of(context).pop(collection),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: theme.colorScheme.surfaceContainer,
                      ),
                      child: Row(
                        spacing: 12,
                        children: [
                          const Icon(IconsaxPlusLinear.archive_book, size: 20),
                          Expanded(child: Text(collection.name, style: theme.textTheme.bodyLarge)),
                          const Icon(IconsaxPlusLinear.arrow_right_3, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.localized.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

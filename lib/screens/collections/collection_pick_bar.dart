import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/util/localization_helper.dart';

/// The foot of the library while picking titles for a collection: how many
/// are selected, and the button that puts them in and goes back to it.
class CollectionPickBar extends ConsumerStatefulWidget {
  const CollectionPickBar({required this.collection, required this.selected, required this.onClear, super.key});

  final ItemBaseModel collection;
  final List<ItemBaseModel> selected;
  final VoidCallback onClear;

  @override
  ConsumerState<CollectionPickBar> createState() => _CollectionPickBarState();
}

class _CollectionPickBarState extends ConsumerState<CollectionPickBar> {
  bool _adding = false;

  Future<void> _add() async {
    final ids = widget.selected.map((e) => e.id).toList();
    if (ids.isEmpty || _adding) return;
    setState(() => _adding = true);
    final response =
        await ref.read(jellyApiProvider).collectionsCollectionIdItemsPost(collectionId: widget.collection.id, ids: ids);
    if (!mounted) return;
    setState(() => _adding = false);
    if (!response.isSuccessful) {
      FladderSnack.show('${context.localized.somethingWentWrong} - (${response.statusCode})', context: context);
      return;
    }
    FladderSnack.show(context.localized.collectionAddedTitles(ids.length, widget.collection.name), context: context);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.selected.length;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          shadowColor: Colors.black45,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
            child: Row(
              spacing: 8,
              children: [
                Icon(IconsaxPlusLinear.archive_add, color: scheme.primary),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.collection.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        count == 0 ? context.localized.collectionPickHint : context.localized.selectedCount(count),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  TextButton(
                    onPressed: widget.onClear,
                    child: Text(context.localized.clearSelection),
                  ),
                FilledButton.icon(
                  onPressed: count == 0 || _adding ? null : _add,
                  icon: _adding
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(IconsaxPlusLinear.add, size: 18),
                  label: Text(context.localized.collectionAddCount(count)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

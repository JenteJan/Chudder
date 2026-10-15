import 'dart:async';

import 'package:flutter/material.dart';

import 'package:auto_route/auto_route.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/related_provider.dart';
import 'package:chudder/providers/user_provider.dart';
import 'package:chudder/routes/auto_router.gr.dart';
import 'package:chudder/screens/shared/adaptive_dialog.dart';
import 'package:chudder/screens/shared/fladder_notification_overlay.dart';
import 'package:chudder/screens/shared/outlined_text_field.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/localization_helper.dart';
import 'package:chudder/widgets/shared/alert_content.dart';

/// Whether the signed-in account may change collections: administrators, and
/// anyone the server allows to manage them.
bool canManageCollections(WidgetRef ref) {
  final policy = ref.read(userProvider)?.policy;
  return (policy?.isAdministrator ?? false) || (policy?.enableCollectionManagement ?? false);
}

/// Grows [collection] from its own page: titles the server finds alike to
/// what is in it, a search across the films and shows, and a way into the
/// library with every filter, to pick from there.
///
/// True when something was added or taken out, so the page fetches again.
Future<bool> showAddTitlesToCollection(
  BuildContext context, {
  required ItemBaseModel collection,
  required List<ItemBaseModel> members,
}) async {
  var changed = false;
  var browse = false;
  await showDialogAdaptive(
    context: context,
    builder: (context) => _AddTitles(
      collection: collection,
      members: members,
      onChanged: () => changed = true,
      onBrowse: () => browse = true,
    ),
  );
  if (browse && context.mounted) {
    // Waited for, so the page fetches again once the picking is done.
    await context.router.push(LibrarySearchRoute(
      types: const {FladderItemType.movie: true, FladderItemType.series: true},
      recursive: true,
      pickForCollection: collection,
    ));
    return true;
  }
  return changed;
}

class _AddTitles extends ConsumerStatefulWidget {
  const _AddTitles({
    required this.collection,
    required this.members,
    required this.onChanged,
    required this.onBrowse,
  });

  final ItemBaseModel collection;
  final List<ItemBaseModel> members;
  final VoidCallback onChanged;
  final VoidCallback onBrowse;

  @override
  ConsumerState<_AddTitles> createState() => _AddTitlesState();
}

class _AddTitlesState extends ConsumerState<_AddTitles> {
  final _query = TextEditingController();
  Timer? _debounce;

  /// What is in the collection now, as changed from here.
  late final Set<String> _inside = widget.members.map((e) => e.id).toSet();

  /// Titles being added or taken out right now, so a second press waits.
  final Set<String> _busy = {};

  List<ItemBaseModel>? _suggestions;
  List<ItemBaseModel>? _results;
  bool _searching = false;
  int _search = 0;

  static const _kinds = [BaseItemKind.movie, BaseItemKind.series];

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// What the server finds alike to the collection and to its newest
  /// entries, the titles that turn up most often first. A franchise's next
  /// film tends to be alike to every film in it.
  Future<void> _loadSuggestions() async {
    final related = ref.read(relatedUtilityProvider);
    final seeds = [
      widget.collection.id,
      ...widget.members.reversed.take(5).map((e) => e.id),
    ];
    final lists = await Future.wait(seeds.map((id) => related
        .relatedContent(id)
        .then((response) => response.body ?? <ItemBaseModel>[])
        .catchError((_) => <ItemBaseModel>[])));
    if (!mounted) return;
    final counts = <String, int>{};
    final byId = <String, ItemBaseModel>{};
    for (final list in lists) {
      for (final item in list) {
        if (item.type != FladderItemType.movie && item.type != FladderItemType.series) continue;
        if (item.id == widget.collection.id) continue;
        counts[item.id] = (counts[item.id] ?? 0) + 1;
        byId[item.id] = item;
      }
    }
    final ranked = byId.values.toList()..sort((a, b) => counts[b.id]!.compareTo(counts[a.id]!));
    setState(() => _suggestions = ranked.where((item) => !_inside.contains(item.id)).take(24).toList());
  }

  void _onQuery(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value.trim()));
  }

  Future<void> _runSearch(String query) async {
    final search = ++_search;
    final response = await ref.read(jellyApiProvider).itemsGet(
      searchTerm: query,
      includeItemTypes: _kinds,
      recursive: true,
      limit: 40,
      fields: [ItemFields.primaryimageaspectratio],
    );
    if (!mounted || search != _search) return;
    setState(() {
      _searching = false;
      _results = response.body?.items ?? const [];
    });
  }

  Future<void> _toggle(ItemBaseModel item) async {
    if (_busy.contains(item.id)) return;
    final adding = !_inside.contains(item.id);
    setState(() => _busy.add(item.id));
    final api = ref.read(jellyApiProvider);
    final response = adding
        ? await api.collectionsCollectionIdItemsPost(collectionId: widget.collection.id, ids: [item.id])
        : await api.collectionsCollectionIdItemsDelete(collectionId: widget.collection.id, ids: [item.id]);
    if (!mounted) return;
    setState(() {
      _busy.remove(item.id);
      if (response.isSuccessful) {
        adding ? _inside.add(item.id) : _inside.remove(item.id);
      }
    });
    if (response.isSuccessful) {
      widget.onChanged();
    } else {
      FladderSnack.show(
        '${context.localized.somethingWentWrong} - (${response.statusCode})',
        context: context,
      );
    }
  }

  void _browseLibrary() {
    widget.onBrowse();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typed = _query.text.trim().isNotEmpty;
    final list = typed ? _results : _suggestions;
    final loading = typed ? _searching || _results == null : _suggestions == null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: AdaptiveLayout.viewSizeOf(context) >= ViewSize.tablet
            ? MediaQuery.sizeOf(context).height * 0.85
            : double.infinity,
      ),
      child: ActionContent(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Text(context.localized.collectionAddTitles, style: theme.textTheme.titleLarge),
            Text(
              widget.collection.name,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            OutlinedTextField(
              label: context.localized.collectionSearchTitles,
              controller: _query,
              autoFocus: AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer,
              onChanged: _onQuery,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                typed ? context.localized.collectionSearchResults : context.localized.collectionSuggested,
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            Flexible(
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : list!.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            typed ? context.localized.noResults : context.localized.collectionNoSuggestions,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final item = list[index];
                            return _TitleRow(
                              item: item,
                              inside: _inside.contains(item.id),
                              busy: _busy.contains(item.id),
                              onToggle: () => _toggle(item),
                            );
                          },
                        ),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: _browseLibrary,
            icon: const Icon(IconsaxPlusLinear.filter_search, size: 18),
            label: Text(context.localized.collectionBrowseLibrary),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.localized.done),
          ),
        ],
      ),
    );
  }
}

/// A title with its poster and year, and whether it is in the collection - a
/// press puts it in or takes it out again.
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.item, required this.inside, required this.busy, required this.onToggle});

  final ItemBaseModel item;
  final bool inside;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final year = item.overview.yearAired ?? item.overview.productionYear;
    final subtitle = [
      if (year != null && year > 0) '$year',
      item.type.label(context.localized),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: inside ? scheme.primaryContainer.withValues(alpha: 0.45) : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onToggle,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              spacing: 12,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    width: 40,
                    height: 60,
                    color: scheme.surfaceContainerHighest,
                    child: FladderImage(
                      image: item.images?.primary,
                      fit: BoxFit.cover,
                      placeHolder: Icon(item.type.icon, size: 18),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: busy
                      ? const SizedBox.square(
                          key: ValueKey('busy'),
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : inside
                          ? Row(
                              key: const ValueKey('in'),
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                Icon(IconsaxPlusBold.tick_circle, size: 20, color: scheme.primary),
                                Text(context.localized.collectionInIt,
                                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                              ],
                            )
                          : Row(
                              key: const ValueKey('out'),
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                Icon(IconsaxPlusLinear.add_circle, size: 20, color: scheme.onSurfaceVariant),
                                Text(context.localized.add, style: theme.textTheme.labelLarge),
                              ],
                            ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

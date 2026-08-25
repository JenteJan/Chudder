import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/providers/items/remote_item_image_provider.dart';
import 'package:fladder/providers/library_search_provider.dart';
import 'package:fladder/screens/shared/outlined_text_field.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/localization_helper.dart';

class SuggestionSearchBar extends ConsumerStatefulWidget {
  final String? title;
  final bool autoFocus;
  final Duration debounceDuration;
  final SuggestionsController<ItemBaseModel>? suggestionsBoxController;
  final Function(String value)? onSubmited;
  final Function(String value)? onChanged;

  /// Told which item was chosen, and the tag its artwork was flying under, so
  /// whatever opens the item can be the far end of that flight.
  final Function(ItemBaseModel value, Object heroTag)? onItem;
  const SuggestionSearchBar({
    this.title,
    this.autoFocus = false,
    this.debounceDuration = const Duration(milliseconds: 250),
    this.suggestionsBoxController,
    this.onSubmited,
    this.onChanged,
    this.onItem,
    super.key,
  });

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<SuggestionSearchBar> {
  late final SuggestionsController<ItemBaseModel> suggestionsBoxController =
      widget.suggestionsBoxController ?? SuggestionsController<ItemBaseModel>();
  final TextEditingController textEditingController = TextEditingController();
  bool isEmpty = true;
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      textEditingController.text =
          ref.read(librarySearchProvider(widget.key!).select((value) => value.filters.searchQuery));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(librarySearchProvider(widget.key!).select((value) => value.filters.searchQuery), (previous, next) {
      if (textEditingController.text != next) {
        setState(() {
          textEditingController.text = next;
        });
      }
    });
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: TypeAheadField<ItemBaseModel>(
        // It was held in a Debouncer nothing ever called, so every keystroke
        // went straight to the server on the field's own default.
        debounceDuration: widget.debounceDuration,
        controller: textEditingController,
        focusNode: focusNode,
        hideOnEmpty: isEmpty,
        emptyBuilder: (context) => Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            "${context.localized.noSuggestionsFound}...",
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        suggestionsController: suggestionsBoxController,
        decorationBuilder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: FladderTheme.smallShape.borderRadius,
          ),
          child: child,
        ),
        builder: (context, controller, focusNode) => OutlinedTextField(
          focusNode: focusNode,
          autoFocus: widget.autoFocus,
          controller: controller,
          onSubmitted: (value) {
            widget.onSubmited!(value);
            suggestionsBoxController.close();
          },
          onChanged: (value) {
            setState(() {
              isEmpty = value.isEmpty;
            });
          },
          searchQuery: (query) async {
            if (query.isEmpty) return [];
            if (widget.key != null) {
              final items =
                  await ref.read(librarySearchProvider(widget.key!).notifier).fetchSuggestions(query, limit: 5);
              return items.map((e) => e.name).toList();
            }
            return [];
          },
          placeHolder: widget.title ?? "${context.localized.search}...",
          decoration: InputDecoration(
            hintText: widget.title ?? "${context.localized.search}...",
            prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1),
            contentPadding: const EdgeInsets.only(top: 13),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      widget.onSubmited?.call('');
                      controller.text = '';
                      suggestionsBoxController.close();
                      setState(() {
                        isEmpty = true;
                      });
                    },
                    icon: const Icon(Icons.clear))
                : null,
            border: InputBorder.none,
          ),
        ),
        loadingBuilder: (context) => const SizedBox(
          height: 50,
          child: Center(child: CircularProgressIndicator(strokeCap: StrokeCap.round)),
        ),
        onSelected: (suggestion) {
          suggestionsBoxController.close();
        },
        itemBuilder: (context, suggestion) {
          // One tag per suggestion, steady across the rebuilds this list does
          // while it is being typed into. Unique within the list, and the
          // posters behind it fly under keys of their own, so nothing collides.
          final heroTag = ValueKey('search-suggestion-${suggestion.id}');
          return ListTile(
            onTap: () {
              if (widget.onItem != null) {
                widget.onItem?.call(suggestion, heroTag);
              } else {
                // Through the route rather than straight to the widget: the
                // page reads the tag it is meant to be flying from off the
                // route, and pushed by hand it would never be told.
                suggestion.navigateTo(context, tag: heroTag);
              }
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 50,
                maxHeight: 65,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    Hero(
                      tag: heroTag,
                      child: Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        child: AspectRatio(
                          // The artwork's own shape, not the poster cell's - the
                          // cell ratio leaves room for a title this row draws
                          // beside the image, and pinching the image to it made
                          // every poster look starved.
                          aspectRatio: suggestion.type.imageAspectRatio,
                          child: suggestion.images?.primary != null
                              ? FladderImage(image: suggestion.images?.primary, fit: BoxFit.cover)
                              : _RemoteThumbnail(item: suggestion),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                              child: Text(
                            suggestion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )),
                          if (suggestion.overview.yearAired.toString().isNotEmpty)
                            Flexible(
                                child: Opacity(
                                    opacity: 0.45, child: Text(suggestion.overview.yearAired?.toString() ?? ""))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        suggestionsCallback: (pattern) async {
          if (pattern.isEmpty) return [];
          if (widget.key != null) {
            return (await ref.read(librarySearchProvider(widget.key!).notifier).fetchSuggestions(pattern));
          }
          return [];
        },
      ),
    );
  }
}

/// The thumbnail for an item the library has no picture of — a studio, in
/// practice. It asks the server what its own metadata providers can see, and
/// falls back to the type's icon, which at least says what kind of thing this
/// is rather than looking like an image that failed to load.
class _RemoteThumbnail extends ConsumerWidget {
  const _RemoteThumbnail({required this.item});

  final ItemBaseModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        item.type.icon,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );

    // Only where there is nothing to lose: each of these is a request, and
    // everything else in a result list already has a poster.
    if (item.jellyType != BaseItemKind.studio) return fallback;

    return ref.watch(remoteItemImageProvider(item.id)).maybeWhen(
          data: (url) => url == null
              ? fallback
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) => fallback,
                ),
          orElse: () => fallback,
        );
  }
}

import 'package:chopper/chopper.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:chudder/models/boxset_model.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:chudder/util/list_extensions.dart';
import 'package:chudder/util/map_bool_helper.dart';

final collectionStateProvider = StateProvider<List<BoxSetModel>>((ref) => []);

class _CollectionSetModel {
  final bool isLoading;
  final List<ItemBaseModel> items;
  final Map<BoxSetModel, bool?> collections;
  _CollectionSetModel({
    this.isLoading = false,
    required this.items,
    required this.collections,
  });

  _CollectionSetModel copyWith({
    bool? isLoading,
    List<ItemBaseModel>? items,
    Map<BoxSetModel, bool?>? collections,
  }) {
    return _CollectionSetModel(
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      collections: collections ?? this.collections,
    );
  }
}

final collectionsProvider = StateNotifierProvider.autoDispose<BoxSetNotifier, _CollectionSetModel>((ref) {
  // Filled by the dialog's own setItems. Starting a lookup here as well ran
  // the whole thing twice, the two runs writing over each other.
  return BoxSetNotifier(ref);
});

class BoxSetNotifier extends StateNotifier<_CollectionSetModel> {
  BoxSetNotifier(this.ref)
      : super(
          // What the dialog shows until its lookup has started: the
          // collections from last time, each still unknown.
          _CollectionSetModel(
            items: [],
            collections: {for (final boxSet in ref.read(collectionStateProvider)) boxSet: null},
            isLoading: true,
          ),
        );
  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<void> setItems(List<ItemBaseModel> items) async {
    final collections = ref.read(collectionStateProvider);
    state = state.copyWith(
      collections: Map.fromIterables(collections, List.generate(collections.length, (index) => null)),
      items: items,
      isLoading: true,
    );
    return _init();
  }

  Future<void> _init() async {
    final collections = await api.usersUserIdItemsGet(
      recursive: true,
      includeItemTypes: [
        BaseItemKind.boxset,
      ],
    );

    final boxSets = collections.body?.items?.map((e) => BoxSetModel.fromBaseDto(e, ref)).toList();

    ref.read(collectionStateProvider.notifier).state = boxSets ?? [];

    state = state.copyWith(
      collections: Map.fromIterables(boxSets ?? [], List.generate(boxSets?.length ?? 0, (index) => null)),
    );

    // A few collections at a time rather than one after the other; each
    // tick fills in as its answer arrives.
    await (boxSets ?? <BoxSetModel>[]).mapConcurrent(4, (boxSet) async {
      final itemList = await api.usersUserIdItemsGet(
        parentId: boxSet.id,
      );
      if (!mounted) return;
      state = state.copyWith(
        collections: state.collections
            .setKey(boxSet, itemList.body?.items?.map((e) => e.id).contains(state.items.firstOrNull?.id) ?? false),
      );
    });
    if (!mounted) return;

    state = state.copyWith(isLoading: false);
  }

  Future<Response> toggleCollection(
      {required BoxSetModel boxSet, required bool value, required ItemBaseModel item}) async {
    final Response response = value
        ? await api.collectionsCollectionIdItemsPost(collectionId: boxSet.id, ids: [item.id])
        : await api.collectionsCollectionIdItemsDelete(collectionId: boxSet.id, ids: [item.id]);

    if (response.isSuccessful) {
      state = state.copyWith(collections: state.collections.setKey(boxSet, response.isSuccessful ? value : !value));
    }
    return response;
  }

  Future<Response> addToCollection({required BoxSetModel boxSet, required bool add}) async {
    final response = add
        ? await api.collectionsCollectionIdItemsPost(
            collectionId: boxSet.id, ids: state.items.map((e) => e.id).toList())
        : await api.collectionsCollectionIdItemsDelete(
            collectionId: boxSet.id, ids: state.items.map((e) => e.id).toList());

    if (response.isSuccessful) {
      state = state.copyWith(collections: state.collections.setKey(boxSet, response.isSuccessful ? add : !add));
    }
    return response;
  }

  Future<void> addToNewCollection({required String name}) async {
    final result = await api.collectionsPost(name: name, ids: state.items.map((e) => e.id).toList());
    if (result.isSuccessful) {
      await _init();
    }
  }
}

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/providers/api_provider.dart';
import 'package:chudder/providers/service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final itemDetailsProvider = StateNotifierProvider.autoDispose<ItemDetailsNotifier, ItemBaseModel?>((ref) {
  return ItemDetailsNotifier(ref);
});

class ItemDetailsNotifier extends StateNotifier<ItemBaseModel?> {
  ItemDetailsNotifier(this.ref) : super(null);

  final Ref ref;

  late final JellyService api = ref.read(jellyApiProvider);

  Future<ItemBaseModel?> fetchDetails(String itemId) async {
    final response = await api.usersUserIdItemsItemIdGet(itemId: itemId);
    if (response.body == null) return null;
    return response.bodyOrThrow;
  }
}

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/syncing/sync_item.dart';

/// [current] with the metadata [fresh] brought back from the server laid over
/// it.
///
/// A refresh is a patch, not a replacement. [fresh] is a bare row built from
/// the server's answer: it knows nothing of the subtitles, the trick play
/// images, the chapters, the file name or the transcode that came down with
/// the download, and taking it whole wiped all of them. And [current] is read
/// again just before this, so a download that finished while the server was
/// answering is not written over with the row as it was before.
SyncedItem mergeRefreshed(SyncedItem current, SyncedItem fresh, {ItemBaseModel? itemModel}) {
  // Typed nullable on purpose: determineLastUserData reduces with a
  // nullable-typed combine, which a List<UserData> refuses at runtime.
  final userData = <UserData?>[current.userData, fresh.userData].where((data) => data != null).toList();
  return current.copyWith(
    itemModel: itemModel ?? current.itemModel,
    sortName: fresh.sortName ?? current.sortName,
    syncing: false,
    fImages: fresh.fImages ?? current.fImages,
    // Of the two, the later watched: the row's own copy may hold progress made
    // offline that the server has not heard of yet.
    userData: userData.isEmpty ? null : UserData.determineLastUserData(userData),
  );
}

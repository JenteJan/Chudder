import 'package:flutter/material.dart';

import 'package:chudder/jellyfin/jellyfin_open_api.enums.swagger.dart';
import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/models/items/item_shared_models.dart';
import 'package:chudder/models/items/overview_model.dart';

extension StudioNavigation on Studio {
  /// The studio as a plain item, which is how the server hands one over and
  /// what the studio page is opened with.
  ItemBaseModel toItem() => ItemBaseModel(
        name: name,
        id: id,
        overview: const OverviewModel(),
        parentId: null,
        playlistId: null,
        images: null,
        childCount: null,
        primaryRatio: null,
        userData: const UserData(),
        canDownload: null,
        canDelete: null,
        jellyType: BaseItemKind.studio,
      );

  Future<void> navigateTo(BuildContext context) => toItem().navigateTo(context);
}

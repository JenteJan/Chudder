import 'package:flutter/material.dart';
import 'package:fladder/widgets/shared/tv_dialog_frame.dart';

import 'package:fladder/widgets/syncplay/syncplay_group_sheet.dart';

/// Show the SyncPlay group management bottom sheet
void showSyncPlaySheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Host on the root navigator: in the nested shell navigator the sheet
    // renders underneath the bottom navigation bar on small windows.
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const TvDialogFrame(
      child: SyncPlayGroupSheet(),
    ),
  );
}

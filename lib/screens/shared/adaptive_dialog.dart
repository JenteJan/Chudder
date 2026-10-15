import 'package:flutter/material.dart';

import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

/// A dialog on a large screen and a full page on a phone, with the pad kept
/// inside it on a television.
Future<void> showDialogAdaptive({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
}) {
  if (AdaptiveLayout.viewSizeOf(context) >= ViewSize.tablet) {
    return showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => TvDialogFrame(
        child: Padding(
          padding: MediaQuery.paddingOf(context),
          child: Dialog(
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  } else {
    return showDialog(
      context: context,
      useSafeArea: false,
      builder: (context) => TvDialogFrame(
        child: Dialog.fullscreen(
          child: Padding(
            padding: MediaQuery.paddingOf(context),
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }
}

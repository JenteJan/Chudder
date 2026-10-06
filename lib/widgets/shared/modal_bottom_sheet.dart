import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/item_base_model.dart';
import 'package:chudder/theme.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/widgets/shared/item_actions.dart';
import 'package:chudder/widgets/shared/tv_dialog_frame.dart';

Future<void> showItemContextMenu(
    BuildContext context, WidgetRef ref, Offset globalPos, List<ItemAction> actions) async {
  final position = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
  await showMenu(
    context: context,
    position: position,
    items: actions.popupMenuItems(useIcons: true),
  );
}

Future<void> showBottomSheetPill({
  ItemBaseModel? item,
  bool showPill = true,
  Function()? onDismiss,
  EdgeInsets padding = const EdgeInsets.all(16),
  required BuildContext context,
  required Widget Function(
    BuildContext context,
    ScrollController scrollController,
  ) content,
}) async {
  await showModalBottomSheet(
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useRootNavigator: true,
    enableDrag: true,
    context: context,
    builder: (context) {
      final controller = ScrollController();
      return TvModalScope(
        child: DismissOnOverscroll(
          child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8).add(MediaQuery.paddingOf(context)),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: FladderTheme.largeShape.borderRadius,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.touch)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Container(
                        height: 8,
                        width: 35,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          borderRadius: FladderTheme.largeShape.borderRadius,
                        ),
                      ),
                    )
                  else
                    // A sheet is dismissed by dragging it away or tapping beside
                    // it, and a remote can do neither. TvCloseButton is nothing
                    // at all anywhere else, so this stays a plain gap at a desk.
                    const Padding(
                      padding: EdgeInsets.only(top: 8, right: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TvDialogClose(),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      controller: controller,
                      children: [
                        if (item != null) ...{
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(top: 8),
                            child: ItemBottomSheetPreview(item: item),
                          ),
                          const Divider(),
                        },
                        content(context, ScrollController()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      );
    },
  );
  onDismiss?.call();
}

/// Closes the sheet it is in when a list inside it is dragged down past its
/// top.
///
/// A sheet whose content fits is dragged away by the sheet itself, but once
/// the content scrolls the list takes the drag, and pulling down at the top
/// did nothing but stretch it - the sheet could only be closed by its handle
/// or by tapping beside it.
class DismissOnOverscroll extends StatefulWidget {
  const DismissOnOverscroll({required this.child, super.key});

  final Widget child;

  /// How far past the top the finger has to pull before the sheet goes.
  static const double threshold = 56;

  @override
  State<DismissOnOverscroll> createState() => _DismissOnOverscrollState();
}

class _DismissOnOverscrollState extends State<DismissOnOverscroll> {
  double _pulled = 0;
  bool _dismissed = false;

  bool _onScroll(ScrollNotification notification) {
    if (_dismissed || notification.metrics.axis != Axis.vertical) return false;
    final metrics = notification.metrics;
    switch (notification) {
      // A clamped list (Android) reports what it refused to scroll.
      case OverscrollNotification(:final overscroll, :final dragDetails):
        if (dragDetails != null && overscroll < 0 && metrics.pixels <= metrics.minScrollExtent) {
          _pulled -= overscroll;
        }
      // A bouncing one (iOS) scrolls past its top instead.
      case ScrollUpdateNotification(:final dragDetails):
        _pulled = dragDetails != null && metrics.pixels < metrics.minScrollExtent
            ? metrics.minScrollExtent - metrics.pixels
            : 0;
      case ScrollStartNotification() || ScrollEndNotification():
        _pulled = 0;
    }
    if (_pulled > DismissOnOverscroll.threshold) {
      _dismissed = true;
      Navigator.of(context).maybePop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: widget.child,
      );
}

class ItemBottomSheetPreview extends ConsumerWidget {
  final ItemBaseModel item;
  const ItemBottomSheetPreview({required this.item, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          children: [
            Card(
              child: SizedBox(
                height: 90,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: FladderImage(
                    image: item.images?.primary,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (item.subText?.isNotEmpty ?? false)
                    Opacity(
                      opacity: 0.75,
                      child: Text(
                        item.subText!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

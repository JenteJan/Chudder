import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/items/chapters_model.dart';
import 'package:fladder/screens/shared/flat_button.dart';
import 'package:fladder/theme.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/humanize_duration.dart';
import 'package:fladder/util/localization_helper.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/widgets/shared/horizontal_list.dart';
import 'package:fladder/widgets/shared/item_actions.dart';
import 'package:fladder/widgets/shared/modal_bottom_sheet.dart';

/// The chapters of the item you are looking at, behind their own heading.
///
/// Collapsed to that heading until you ask for it: chapters are a way into the
/// middle of something you have already decided to watch, not a reason to
/// decide, and a dozen thumbnails of the film sat between its summary and its
/// cast.
///
/// The heading is drawn whether or not there are chapters, so the rows below
/// it stay where they were. On a show page the section belongs to the episode
/// you have selected, and episodes disagree about whether they have chapters
/// at all — with nothing holding the space, picking the next episode dragged
/// the cast and the seasons up the page under your cursor.
class ChapterRow extends ConsumerStatefulWidget {
  final List<Chapter> chapters;
  final EdgeInsets contentPadding;
  final Function(Chapter)? onPressed;
  const ChapterRow({required this.contentPadding, this.onPressed, required this.chapters, super.key});

  @override
  ConsumerState<ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends ConsumerState<ChapterRow> {
  bool expanded = false;

  void _toggle() => setState(() => expanded = !expanded);

  @override
  Widget build(BuildContext context) {
    final hasChapters = widget.chapters.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChapterHeader(
          contentPadding: widget.contentPadding,
          label: hasChapters ? context.localized.chapter(widget.chapters.length) : context.localized.noChapters,
          expanded: expanded,
          onTap: hasChapters ? _toggle : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.fastOutSlowIn,
          alignment: Alignment.topCenter,
          // The gap between heading and row belongs to the row, not to the
          // Column: as the Column's spacing it stayed behind when the row
          // collapsed, leaving the heading sitting on a strip of nothing.
          child: expanded && hasChapters
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: HorizontalList(
                    // The heading above is ours — it toggles, and on a remote
                    // it has to take focus, which the list's own bar excludes.
                    label: null,
                    // No ratio, so the row is as tall as the episode row above
                    // it — which passes none either — rather than the divisor
                    // shrinking chapters to three quarters of episodes that
                    // are the same shape.
                    items: widget.chapters,
                    itemBuilder: (context, index) => _ChapterCard(
                      chapter: widget.chapters[index],
                      onPressed: widget.onPressed,
                    ),
                    contentPadding: widget.contentPadding,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The heading, and on a remote the whole of the control.
///
/// A [FlatButton] rather than the list's own title bar: that one wraps its
/// label in an [ExcludeFocus], which is right for a heading that only names
/// the row under it and wrong for one that opens it.
class _ChapterHeader extends StatelessWidget {
  final EdgeInsets contentPadding;
  final String label;
  final bool expanded;
  final VoidCallback? onTap;

  const _ChapterHeader({
    required this.contentPadding,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: contentPadding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FlatButton(
          onTap: onTap,
          onFocusChange: (value) {
            if (value) context.ensureVisible();
          },
          child: Padding(
            // Vertical only, exactly as StickyHeaderText pads the label in
            // every other row's header. The 6 that used to be here was the
            // whole of why "Chapters" sat a few pixels right of "Episodes"
            // and "Seasons" on the same page.
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 6,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The heading's own style whether or not anything is
                    // behind it, so the empty state stands exactly as tall as
                    // the filled one.
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: enabled ? null : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
                ),
                if (enabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8).copyWith(bottom: 4),
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.fastOutSlowIn,
                      child: Icon(
                        IconsaxPlusLinear.arrow_down,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  final Chapter chapter;
  final Function(Chapter)? onPressed;

  const _ChapterCard({required this.chapter, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    List<ItemAction> generateActions() {
      return [
        ItemActionButton(action: () => onPressed?.call(chapter), label: Text(context.localized.playFrom(chapter.name)))
      ];
    }

    return FocusButton(
      onSecondaryTapDown: (details) async {
        Offset localPosition = details.globalPosition;
        RelativeRect position =
            RelativeRect.fromLTRB(localPosition.dx, localPosition.dy, localPosition.dx, localPosition.dy);
        await showMenu(
          context: context,
          position: position,
          items: generateActions().popupMenuItems(),
        );
      },
      onLongPress: () {
        showBottomSheetPill(
          context: context,
          content: (context, scrollController) {
            return ListView(
              shrinkWrap: true,
              controller: scrollController,
              children: [
                ...generateActions().listTileItems(context),
              ],
            );
          },
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: FladderTheme.smallShape.borderRadius,
          color: Theme.of(context).colorScheme.surfaceContainer,
        ),
        foregroundDecoration: FladderTheme.defaultPosterDecoration,
        child: AspectRatio(
          aspectRatio: 1.75,
          child: CachedNetworkImage(
            imageUrl: chapter.imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Icon(IconsaxPlusBold.image),
          ),
        ),
      ),
      overlays: [
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: FladderTheme.smallShape.borderRadius,
                color: Theme.of(context).colorScheme.surfaceContainer.withValues(alpha: 0.75),
              ),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Text(
                  "${chapter.name} \n${chapter.startPosition.humanize ?? context.localized.start}",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
      focusedOverlays: [
        if (AdaptiveLayout.inputDeviceOf(context) == InputDevice.pointer)
          Align(
            alignment: Alignment.bottomRight,
            child: ExcludeFocus(
              child: PopupMenuButton(
                tooltip: context.localized.options,
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                ),
                itemBuilder: (context) => generateActions().popupMenuItems(),
              ),
            ),
          )
      ],
    );
  }
}

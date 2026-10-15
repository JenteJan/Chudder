import 'package:flutter/material.dart';

import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:chudder/util/focus_provider.dart';

/// One track in the audio or subtitle picker.
///
/// The selection wears the ring the rest of the app wears (see [FocusButton]),
/// the track that plays a check mark. The row's own menu sits beside the row
/// rather than inside it: inside, it shared the row's box, and right from the
/// row found nothing to its right - the menu could not be reached on a remote.
/// A long press on the row (or holding OK) opens that menu as well.
class TrackOptionRow extends StatefulWidget {
  const TrackOptionRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.menu,
    this.autofocus = false,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Whether this is the track that plays.
  final bool selected;
  final VoidCallback onTap;
  final Widget? menu;
  final bool autofocus;

  @override
  State<TrackOptionRow> createState() => _TrackOptionRowState();
}

class _TrackOptionRowState extends State<TrackOptionRow> {
  final GlobalKey _menuKey = GlobalKey();

  /// Opens the menu beside the row, whichever kind of button it is.
  void _openMenu() {
    final menuContext = _menuKey.currentContext;
    if (menuContext == null) return;
    var opened = false;
    void visit(Element element) {
      if (opened) return;
      if (element is StatefulElement && element.state is PopupMenuButtonState) {
        (element.state as PopupMenuButtonState).showButtonMenu();
        opened = true;
        return;
      }
      if (element.widget case IconButton(:final onPressed?)) {
        onPressed();
        opened = true;
        return;
      }
      element.visitChildElements(visit);
    }

    (menuContext as Element).visitChildElements(visit);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final selected = widget.selected;
    final menu = widget.menu;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        spacing: 4,
        children: [
          Expanded(
            child: FocusButton(
              onTap: widget.onTap,
              onLongPress: menu != null ? _openMenu : null,
              autoFocus: widget.autofocus,
              borderRadius: radius,
              darkOverlay: false,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: selected ? scheme.primaryContainer.withValues(alpha: 0.4) : Colors.transparent,
                ),
                child: Row(
                  spacing: 12,
                  children: [
                    SizedBox(
                      width: 22,
                      child: selected ? Icon(IconsaxPlusBold.tick_circle, size: 20, color: scheme.primary) : null,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: selected ? FontWeight.w600 : null,
                            ),
                          ),
                          if (subtitle != null && subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (menu != null) KeyedSubtree(key: _menuKey, child: menu),
        ],
      ),
    );
  }
}

/// Something to do from a track picker (time the subtitles, find more), in
/// the same shape and with the same selection ring as the tracks above it.
class TrackActionRow extends StatelessWidget {
  const TrackActionRow({required this.icon, required this.title, required this.onTap, this.subtitle, super.key});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: FocusButton(
        onTap: onTap,
        borderRadius: radius,
        darkOverlay: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            spacing: 12,
            children: [
              SizedBox(width: 22, child: Icon(icon, size: 20)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(IconsaxPlusLinear.arrow_right_3, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of the player's options sheet - a setting with its current value, or
/// a page to open - with the same selection ring as the tracks.
class OptionRow extends StatelessWidget {
  const OptionRow({required this.title, required this.onTap, this.value, this.trailing, super.key});

  final String title;
  final String? value;

  /// In place of [value]: a switch, say. Never a stop of its own; the row is.
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(12);
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: FocusButton(
          onTap: onTap,
          borderRadius: radius,
          darkOverlay: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                  if (trailing != null)
                    ExcludeFocus(child: trailing!)
                  else if (value != null)
                    Flexible(
                      child: Text(
                        value!,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

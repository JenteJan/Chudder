import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:fladder/models/item_base_model.dart';
import 'package:fladder/screens/shared/animated_fade_size.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/focus_provider.dart';
import 'package:fladder/util/position_provider.dart';
import 'package:fladder/widgets/shared/ensure_visible.dart';
import 'package:fladder/util/localization_helper.dart';

class MediaPlayButton extends ConsumerWidget {
  final ItemBaseModel? item;
  final bool forceFocusOutline;
  final bool showRestartOption;
  final Function(bool restart)? onPressed;
  final Function(bool restart)? onLongPressed;

  /// Television scale: the same button with room around its label.
  ///
  /// Sized for the far end of a room rather than for a mouse. Only the copy
  /// that sits out on the artwork asks for this - the one down in the action
  /// row has to stay the height of the stream pickers beside it.
  final bool large;

  /// Whether this is the button the page opens on.
  ///
  /// Defaults to every play button on a remote, which is right while there is
  /// one of them on the page. A page that puts a second copy on its artwork
  /// has to say which of the two, or both claim the first frame and the one
  /// that wins is whichever was built last.
  final bool? autoFocus;

  const MediaPlayButton({
    required this.item,
    this.forceFocusOutline = false,
    this.showRestartOption = true,
    this.onPressed,
    this.onLongPressed,
    this.large = false,
    this.autoFocus,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = (item?.progress ?? 0) / 100.0;
    final showRestart = progress != 0 && showRestartOption;
    // The width of the page on a phone. It is the one thing the page wants
    // you to press and there is no room beside it for anything but the menu,
    // so it takes the line rather than sitting in the middle of it. With room
    // to spare - and on the artwork, where it is already large - it hugs its
    // own label as before.
    final fill = !large && AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    // Everything in a phone's action row stands the same height.
    final restartHeight = fill ? 44.0 : 40.0;
    final radius = BorderRadius.circular(16);
    final smallRadius = const Radius.circular(4);
    final theme = Theme.of(context);

    Widget buttonTitle(Color contentColor) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: large ? 28 : 10, vertical: large ? 16 : 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // Centred rather than started, because the button is given its width
          // on a phone instead of taking it: the progress copy of this row is
          // laid out at the button's full width, and started, the label under
          // the progress sat left of the label above it.
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                item?.playButtonLabel(context.localized) ?? "",
                maxLines: 1,
                overflow: TextOverflow.fade,
                style: (large ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium)?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: contentColor,
                ),
              ),
            ),
            SizedBox(width: large ? 12 : 4),
            Icon(
              IconsaxPlusBold.play,
              size: large ? 32 : null,
              color: contentColor,
            ),
          ],
        ),
      );
    }

    return AnimatedFadeSize(
      duration: const Duration(milliseconds: 250),
      child: onPressed == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
              // Apart, not welded on: the restart button is a second, smaller
              // thing beside the play button, not a lump on its end.
              spacing: 8,
              children: [
                _Fills(
                  fill: fill,
                  child: PositionProvider(
                    position: PositionContext.first,
                    child: _PlayButton(
                      onPressed: onPressed,
                      onLongPressed: onLongPressed,
                      autoFocus: autoFocus ?? (AdaptiveLayout.inputDeviceOf(context) == InputDevice.dPad),
                      forceFocusOutline: forceFocusOutline,
                      progress: progress,
                      buttonTitle: buttonTitle,
                      theme: theme,
                      radius: radius,
                      smallRadius: smallRadius,
                      showRestart: showRestart,
                    ),
                  ),
                ),
                if (showRestart)
                  PositionProvider(
                    position: PositionContext.last,
                    child: _RestartButton(
                      onPressed: onPressed,
                      onLongPressed: onLongPressed,
                      forceFocusOutline: forceFocusOutline,
                      theme: theme,
                      radius: radius,
                      smallRadius: smallRadius,
                      height: restartHeight,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The play button's share of its row: all that is left of it where the
/// button fills the line, and only what it needs where it does not.
class _Fills extends StatelessWidget {
  final bool fill;
  final Widget child;

  const _Fills({required this.fill, required this.child});

  @override
  Widget build(BuildContext context) => fill ? Expanded(child: child) : Flexible(child: child);
}

class _PlayButton extends StatelessWidget {
  final Function(bool restart)? onPressed;
  final Function(bool restart)? onLongPressed;
  final bool autoFocus;
  final bool forceFocusOutline;
  final double progress;
  final Widget Function(Color) buttonTitle;
  final ThemeData theme;
  final BorderRadius radius;
  final Radius smallRadius;
  final bool showRestart;

  const _PlayButton({
    required this.onPressed,
    required this.onLongPressed,
    required this.autoFocus,
    required this.forceFocusOutline,
    required this.progress,
    required this.buttonTitle,
    required this.theme,
    required this.radius,
    required this.smallRadius,
    required this.showRestart,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = radius;

    return FocusButton(
      onTap: () => onPressed?.call(false),
      onLongPress: () => onLongPressed?.call(false),
      autoFocus: autoFocus,
      borderRadius: borderRadius,
      forceFocusOutline: forceFocusOutline,
      darkOverlay: false,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Progress background
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: borderRadius,
              ),
            ),
          ),
          // Button content
          buttonTitle(theme.colorScheme.onPrimaryContainer),
          Positioned.fill(
            child: ClipRect(
              clipper: _ProgressClipper(progress),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: borderRadius,
                ),
                child: buttonTitle(theme.colorScheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestartButton extends StatelessWidget {
  final Function(bool restart)? onPressed;
  final Function(bool restart)? onLongPressed;
  final bool forceFocusOutline;
  final ThemeData theme;
  final BorderRadius radius;
  final Radius smallRadius;
  final double height;

  const _RestartButton({
    required this.onPressed,
    required this.onLongPressed,
    required this.forceFocusOutline,
    required this.theme,
    required this.radius,
    required this.smallRadius,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);

    return FocusButton(
      onTap: () => onPressed?.call(true),
      onLongPress: () => onLongPressed?.call(true),
      borderRadius: borderRadius,
      forceFocusOutline: forceFocusOutline,
      onFocusChanged: (value) {
        if (value) {
          context.ensureVisible(
            alignment: 1.0,
          );
        }
      },
      child: Tooltip(
        message: context.localized.playFromStart(''),
        // The same quiet outline the stream pickers and the menu button wear.
        child: Container(
          height: height,
          width: 44,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.18)),
          ),
          child: Icon(
            IconsaxPlusLinear.refresh,
            size: 20,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;
  _ProgressClipper(this.progress);

  @override
  Rect getClip(Size size) {
    final w = (progress.clamp(0.0, 1.0) * size.width);
    return Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(covariant _ProgressClipper old) => old.progress != progress;
}

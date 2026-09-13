import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chudder/models/items/images_models.dart';
import 'package:chudder/util/adaptive_layout/adaptive_layout.dart';
import 'package:chudder/util/fladder_image.dart';
import 'package:chudder/util/title_line_breaking.dart';

class MediaHeader extends ConsumerWidget {
  final String name;
  final ImageData? logo;
  final Function()? onTap;
  final Alignment alignment;
  final TextAlign textAlign;
  const MediaHeader({
    required this.name,
    required this.logo,
    this.onTap,
    this.alignment = Alignment.bottomCenter,
    this.textAlign = TextAlign.center,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxSize = 700.0;
    final isPhone = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone;
    // A logo is contained in this box, so a tall one is dead space above a wide
    // logo rather than a bigger logo. A phone cannot afford a quarter of its
    // screen for that: at this height the width is what limits the usual wide
    // logo, and the box ends up hugging it.
    final heightFactor = isPhone ? 0.13 : 0.275;
    final baseStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontSize: isPhone ? 40 : 55,
        );
    final textWidget = Container(
      constraints: const BoxConstraints(minHeight: 10, maxHeight: 200),
      alignment: alignment,
      child: LayoutBuilder(
        // Two lines at most, at whatever size gets it there. A long title used
        // to be selectable text in a box shorter than it was, which on a phone
        // meant a title you had to scroll to read.
        builder: (context, constraints) => Text(
          name.keepPunctuationWithWord,
          textAlign: textAlign,
          maxLines: _titleLines,
          overflow: TextOverflow.ellipsis,
          style: _fittedToLines(
            name.keepPunctuationWithWord,
            baseStyle,
            constraints,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
          ),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        // The short box is for logos only. A written title takes the two lines
        // it is sized for, and shrinking it to fit a box meant for a picture
        // left long names smaller than they had to be.
        maxHeight: logo != null ? (MediaQuery.sizeOf(context).height * heightFactor).clamp(0, maxSize) : maxSize,
        maxWidth: MediaQuery.sizeOf(context).width.clamp(0, maxSize),
      ),
      child: Stack(
        children: [
          logo != null
              ? FladderImage(
                  image: logo,
                  disableBlur: true,
                  alignment: alignment,
                  imageErrorBuilder: (context, object, stack) => textWidget,
                  placeHolder: const SizedBox(height: 0),
                  fit: BoxFit.contain,
                )
              : textWidget,
          if (onTap != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: onTap,
              ),
            ),
        ],
      ),
    );
  }
}

/// How many lines a written title gets before it is made smaller.
const _titleLines = 2;

/// The smallest a title is ever written. Under this it would be quieter than
/// the facts underneath it, so a title this long is cut short instead.
const _minTitleSize = 20.0;

/// [style] at the largest size, never above its own, at which [name] fits in
/// [_titleLines] lines of [constraints] and breaks only between words.
TextStyle? _fittedToLines(
  String name,
  TextStyle? style,
  BoxConstraints constraints,
  TextScaler scaler,
  TextDirection direction,
) {
  final maxWidth = constraints.maxWidth;
  if (style == null || !maxWidth.isFinite || maxWidth <= 0) return style;
  final fullSize = style.fontSize ?? 55;

  bool fits(double size) {
    final painter = TextPainter(
      text: TextSpan(text: name, style: style.copyWith(fontSize: size)),
      textDirection: direction,
      textScaler: scaler,
      maxLines: _titleLines,
    )..layout(maxWidth: maxWidth);
    final fitted = !painter.didExceedMaxLines && painter.height <= constraints.maxHeight;
    painter.dispose();
    return fitted;
  }

  // Never large enough that a word has to break inside itself: a word's width
  // grows with the size, so the size at which the widest one just fits the
  // column is the ceiling. Flutter breaks mid-word when a word cannot fit a
  // line at all, and a line opening with half a word reads as a mistake.
  double widest = 0;
  for (final word in name.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
    painter.dispose();
  }

  var high = widest > maxWidth ? fullSize * maxWidth / widest : fullSize;
  if (high <= _minTitleSize) return style.copyWith(fontSize: _minTitleSize);
  if (fits(high)) return style.copyWith(fontSize: high);

  var low = _minTitleSize;
  // Nothing smaller is worth reading, so the ellipsis takes the rest.
  if (!fits(low)) return style.copyWith(fontSize: low);

  // Eight halvings land within a fraction of a point of the largest size that
  // fits, which is closer than anybody can see.
  for (var i = 0; i < 8; i++) {
    final mid = (low + high) / 2;
    if (fits(mid)) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return style.copyWith(fontSize: low);
}

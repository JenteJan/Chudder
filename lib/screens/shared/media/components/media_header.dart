import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fladder/models/items/images_models.dart';
import 'package:fladder/util/adaptive_layout/adaptive_layout.dart';
import 'package:fladder/util/fladder_image.dart';
import 'package:fladder/util/title_line_breaking.dart';

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
    // A logo is contained in this box, so a tall one is dead space above a wide
    // logo rather than a bigger logo. A phone cannot afford a quarter of its
    // screen for that: at this height the width is what limits the usual wide
    // logo, and the box ends up hugging it.
    final heightFactor = AdaptiveLayout.viewSizeOf(context) == ViewSize.phone ? 0.13 : 0.275;
    final baseStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
          fontSize: 55,
        );
    final textWidget = Container(
      constraints: const BoxConstraints(minHeight: 10, maxHeight: 200),
      alignment: alignment,
      child: LayoutBuilder(
        // A title too wide for its column used to break inside a word. Sized to
        // its widest word, it breaks where a word ends or not at all.
        builder: (context, constraints) => SelectableText(
          name.keepPunctuationWithWord,
          textAlign: textAlign,
          style: _sizedToWidestWord(name, baseStyle, constraints.maxWidth, MediaQuery.textScalerOf(context)),
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height * heightFactor).clamp(0, maxSize),
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

/// [style] shrunk, if it has to be, until the title's widest word fits inside
/// [maxWidth] — so a line only ever breaks between words.
TextStyle? _sizedToWidestWord(String name, TextStyle? style, double maxWidth, TextScaler scaler) {
  if (style == null || !maxWidth.isFinite || maxWidth <= 0) return style;
  double widest = 0;
  for (final word in name.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
  }
  if (widest <= maxWidth) return style;
  final fullSize = style.fontSize ?? 55;
  return style.copyWith(fontSize: (fullSize * maxWidth / widest).clamp(24.0, fullSize));
}
